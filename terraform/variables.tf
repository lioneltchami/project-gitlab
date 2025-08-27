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

variable "shakespeare_words" {
  description = "List of words for Shakespeare analysis instances"
  type        = list(string)
  default     = ["the", "COFFEE", "AND", "tea"]
}

variable "dev_words" {
  description = "List of words for development environment"
  type        = list(string)
  default     = ["the", "COFFEE"]
}