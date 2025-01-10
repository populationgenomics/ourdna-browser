# Terraform for deploying infrastructure for GnomAD Browser

This directory contains Terraform code for deploying infrastructure on Google Cloud Platform.

First, follow the steps in `terraform/initial-setup` with a new GCP project to get required initial setup:

- storage bucket for remote state (with appropriate configuration)
- GCP API's enabled for various services

When that is complete, create a `terraform.tfvars` file (see `terraform.tfvars.example` for a template) with relevant configuration.

Then create a `backend.hcl` file (see `backend.hcl.example` for a template).
Update this with information about storage bucket from `terraform/initial-state` steps and appropriate prefix for terraform state files stored in the bucket.

Then run `terraform init -backend-config=backend.hcl`, followed by `terraform apply` to create infrastructure.

Note: GKE cluster creation can take up to 20 minutes. 

To remove infrastructure, use `terraform destroy`.

Note: the terraform code in this directory refers to modules stored in a different repository. If you update the code in that repository, or change the url for the modules, you will need to run `terraform init -backend-config=backend.hcl -upgrade`  ([here are the docs](https://developer.hashicorp.com/terraform/cli/commands/init))
