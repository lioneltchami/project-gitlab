terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
  
  backend "gcs" {
    bucket = "shakespeare-terraform-state"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
  }
}

data "google_client_config" "default" {}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.project_name}-gke"
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # Enable network policy for security
  network_policy {
    enabled = true
  }

  # Enable workload identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable private cluster
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Security and maintenance
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Enable required addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }
}

# Node pool for the GKE cluster
resource "google_container_node_pool" "primary_nodes" {
  name       = "${google_container_cluster.primary.name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.gke_num_nodes

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/bigquery",
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      env = var.environment
    }

    machine_type = "e2-medium"
    disk_size_gb = 20
    disk_type    = "pd-standard"
    tags         = ["gke-node", "${var.project_name}-gke"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Enable workload identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Security configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrade settings
  upgrade_settings {
    strategy         = "SURGE"
    max_surge        = 1
    max_unavailable  = 0
  }
}

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = "false"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.2.0.0/20"
  }

  # Enable private Google access
  private_ip_google_access = true
}

# Firewall rules
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.project_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.10.0.0/24", "10.1.0.0/16", "10.2.0.0/20"]
}

# Service Account for BigQuery access
resource "google_service_account" "shakespeare_sa" {
  account_id   = "shakespeare-app"
  display_name = "Shakespeare Application Service Account"
}

# Bind BigQuery Data Viewer role to service account
resource "google_project_iam_member" "bigquery_data_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.shakespeare_sa.email}"
}

# Bind BigQuery Job User role to service account
resource "google_project_iam_member" "bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.shakespeare_sa.email}"
}

# Additional permissions for BigQuery public datasets
resource "google_project_iam_member" "bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.shakespeare_sa.email}"
}

# Create service account key (fallback for local development)
resource "google_service_account_key" "shakespeare_key" {
  service_account_id = google_service_account.shakespeare_sa.name
}

# Kubernetes service account
resource "kubernetes_service_account" "shakespeare_sa" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.primary_nodes]
  
  metadata {
    name      = "shakespeare-sa"
    namespace = "default"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.shakespeare_sa.email
    }
  }
}

# Bind GCP service account to Kubernetes service account
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.shakespeare_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/shakespeare-sa]"
}

# Secret for service account key (fallback for environments without workload identity)
resource "kubernetes_secret" "google_cloud_key" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.primary_nodes]
  
  metadata {
    name      = "google-cloud-key"
    namespace = "default"
  }

  data = {
    "service-account.json" = base64decode(google_service_account_key.shakespeare_key.private_key)
  }

  type = "Opaque"
}

# Install nginx-ingress controller
resource "helm_release" "nginx_ingress" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.primary_nodes]
  
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  version    = "4.8.3"

  create_namespace = true

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "cloud.google.com/load-balancer-type" = "External"
          }
        }
        config = {
          use-proxy-protocol = "false"
        }
        metrics = {
          enabled = true
        }
      }
    })
  ]
}

# Install cert-manager for TLS certificates
resource "helm_release" "cert_manager" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.primary_nodes]
  
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.13.2"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }
}

# ClusterIssuer for Let's Encrypt certificates
resource "kubernetes_manifest" "letsencrypt_issuer" {
  depends_on = [helm_release.cert_manager]
  
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [{
          http01 = {
            ingress = {
              class = "nginx"
            }
          }
        }]
      }
    }
  }
}

# Create namespaces for different environments
resource "kubernetes_namespace" "shakespeare_dev" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.primary_nodes]
  
  metadata {
    name = "shakespeare-dev"
    labels = {
      name        = "shakespeare-dev"
      environment = "development"
    }
  }
}

resource "kubernetes_namespace" "shakespeare_prod" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.primary_nodes]
  
  metadata {
    name = "shakespeare-prod"
    labels = {
      name        = "shakespeare-prod"
      environment = "production"
    }
  }
}