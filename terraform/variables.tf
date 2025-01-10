variable "project_id" {
  description = "The name of the target GCP project, for creating IAM memberships"
  type        = string
}

# Unfortunately cannot use variables in module source blocks
# variable "vpc_module_source" {
#   description = "The URL of repository and specific release of gnomad-vpc module"
#   type        = string
#   default     = "github.com/broadinstitute/tgg-terraform-modules//gnomad-vpc?ref=main"
# }
# 
# variable "vpc_sub_module_source" {
#   description = "The URL of repository and specific release of vpc-with-nat-subnet module"
#   type        = string
#   default     = "github.com/broadinstitute/tgg-terraform-modules//vpc-with-nat-subnet?ref=vpc-with-nat-subnet-v1.0.0"
# }

variable "network_name_prefix" {
  description = ""
  type        = string
  default     = "gnomad-mynetwork"
}

variable "infra_prefix" {
  description = ""
  type        = string
  default     = "gnomad-dev"
}

# Unfortunately cannot use variables in module source blocks
# variable "gke_module_source" {
#   description = "The URL of repository and specific release of gnomad-browser-infra module"
#   type        = string
#   default     = "github.com/broadinstitute/tgg-terraform-modules//gnomad-browser-infra?ref=main"
# }
# 
# variable "gke_sub_module_source" {
#   description = "The URL of repository and specific release of private-gke-cluster module"
#   type        = string
#   default     = "github.com/broadinstitute/tgg-terraform-modules//private-gke-cluster?ref=private-gke-cluster-v1.0.3"
# }

variable "deletion_protection" {
  description = "Whether Terraform is prevented from destroying the cluster"
  type        = string
  default     = true
}

variable "default_resource_region" {
  type        = string
  description = "For managed items that require a region/location"
}

variable "default_resource_zone" {
  type        = string
  description = "For managed items that require a zone"
}

variable "authorized_networks" {
  description = "The IPv4 CIDR ranges that should be allowed to connect to the control plane"
  type        = list(string)
  default     = []
}


variable "bucket_force_destroy" {
  description = "Whether or not to allow Terraform to delete datapipeline and snapshot buckets if they are not empty"
  type        = string
  default     = false
}

variable "gke_node_pools" {
  description = "A list of node pools and their configuration that should be created within the GKE cluster; pools with an empty string for the zone will deploy in the same region as the control plane"
  type = list(object({
    pool_name            = string
    pool_num_nodes       = number
    pool_machine_type    = string
    pool_preemptible     = bool
    pool_zone            = string
    pool_resource_labels = map(string)
  }))
}
