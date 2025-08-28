variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "shakespeare"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gke_num_nodes" {
  description = "Number of GKE nodes"
  type        = number
  default     = 2
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "shakespeare_words" {
  description = "List of words for Shakespeare analysis instances (lowercase)"
  type        = list(string)
  default     = ["the", "coffee", "and", "tea"]
}

variable "dev_words" {
  description = "List of words for development environment (lowercase)"
  type        = list(string)
  default     = ["the", "coffee"]
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "shakespeare.example.com"
}

variable "enable_monitoring" {
  description = "Enable monitoring and logging"
  type        = bool
  default     = true
}

variable "enable_autoscaling" {
  description = "Enable cluster autoscaling"
  type        = bool
  default     = true
}