# Makefile to make it easier to deploy gnomAD
# This file was originally developed by Garvan team:
# https://github.com/Garvan-Data-Science-Platform/gnomad-browser/blob/autism-crc-coverage/makefile
# It has been refactored to move all hardcoded variables to env variables

# Here is the list of required ENV variables:

PROJECT_ID:=$(PROJECT_ID)
REGION:=$(REGION)
ZONE:=$(REGION)-a
OUTPUT_BUCKET:=$(OUTPUT_BUCKET)
CLUSTER_NAME:=$(CLUSTER_NAME)
SUBNET_NAME:=$(SUBNET_NAME)
AUTOSCALING_POLICY_NAME:=$(AUTOSCALING_POLICY_NAME)
ENVIRONMENT_TAG:=$(ENVIRONMENT_TAG)
DOCKER_TAG:=$(DOCKER_TAG)
DEPLOYMENT_STATE:=$(DEPLOYMENT_STATE)
READS_INSTANCE_NAME:=$(READS_INSTANCE_NAME)
LOAD_NODE_POOL_SIZE:=$(LOAD_NODE_POOL_SIZE)
READS_DISK_SIZE:=$(READS_DISK_SIZE)
GNOMAD_PROJECT_PATH:=$(GNOMAD_PROJECT_PATH)


### Stand up infra
tf-init: ## Create infrastructure
	terraform -chdir=./terraform init

tf-apply: ## Create infrastructure
	terraform -chdir=./terraform apply

tf-destroy: ## Destroy infrastructure
	terraform -chdir=./terraform destroy


### Initial Config ###
config: ## Set deployctl config
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set project $(PROJECT_ID)
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set zone $(ZONE)
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set data_pipeline_output $(OUTPUT_BUCKET)
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set environment_tag $(ENVIRONMENT_TAG)

config-ls: ## Set deployctl config
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config list

gcloud-auth: ## Authenticate with gcloud
	gcloud auth login --project $(PROJECT_ID)

kube-config: ## Configure kubectl
	gcloud container clusters get-credentials $(CLUSTER_NAME) \
		    --region=$(ZONE)