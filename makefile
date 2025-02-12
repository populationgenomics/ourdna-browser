SHELL = /bin/bash

# Makefile to make it easier to deploy gnomAD
# This file was originally developed by Garvan team:
# https://github.com/Garvan-Data-Science-Platform/gnomad-browser/blob/autism-crc-coverage/makefile
# It has been refactored to move all hardcoded variables to env variables

# Here is the list of required ENV variables:
PROJECT_ID:=$(PROJECT_ID)
REGION:=$(REGION)
READS_INSTANCE_NAME:=
ZONE:=$(REGION)-a
OUTPUT_BUCKET:=$(OUTPUT_BUCKET)
CLUSTER_NAME:=$(CLUSTER_NAME)
SUBNET_NAME:=$(SUBNET_NAME)
AUTOSCALING_POLICY_NAME:=$(AUTOSCALING_POLICY_NAME)
ENVIRONMENT_TAG:=$(ENVIRONMENT_TAG)
DOCKER_TAG:=$(DOCKER_TAG)
DEPLOYMENT_STATE:=$(DEPLOYMENT_STATE)$(READS_INSTANCE_NAME)
LOAD_NODE_POOL_SIZE:=$(LOAD_NODE_POOL_SIZE)
READS_DISK_SIZE:=$(READS_DISK_SIZE)
GCP_DOCKER_REGISTRY:=$(GCP_DOCKER_REGISTRY)
GNOMAD_PROJECT_PATH:=$(GNOMAD_PROJECT_PATH)
GNOMAD_DEPLOYMENTS_PROJECT_PATH:=$(GNOMAD_DEPLOYMENTS_PROJECT_PATH)
SERVICE_ACCOUNT:=$(SERVICE_ACCOUNT)
SERVICE_ACCOUNT_PKEY:=$(SERVICE_ACCOUNT_PKEY)
GOOGLE_APPLICATION_CREDENTIALS:=$(SERVICE_ACCOUNT_PKEY)


### Stand up infra
tf-init: ## Initial terraform
	terraform -chdir=./terraform init

tf-plan: ## Show plan
	terraform -chdir=./terraform plan

tf-apply: ## Create infrastructure
	terraform -chdir=./terraform apply

tf-refresh: ## Sync infrastructure
	terraform -chdir=./terraform refresh

tf-destroy: ## Destroy infrastructure
	terraform -chdir=./terraform destroy


### Initial Config ###
config: ## Set deployctl config
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set project $(PROJECT_ID)
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set zone $(ZONE)
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set data_pipeline_output $(OUTPUT_BUCKET)
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set environment_tag "$(ENVIRONMENT_TAG)"
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set docker_registry $(GCP_DOCKER_REGISTRY)

config-ls: ## Set deployctl config
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config list

gcloud-auth: ## Authenticate with gcloud
	gcloud auth activate-service-account $(SERVICE_ACCOUNT) --key-file=$(SERVICE_ACCOUNT_PKEY) --project=$(PROJECT_ID)

kube-config: ## Configure kubectl
	gcloud container clusters get-credentials $(CLUSTER_NAME) \
		    --region=$(ZONE)


### Pre-Deployment ###

eck-create:
	kubectl create -f https://download.elastic.co/downloads/eck/2.16.0/crds.yaml

eck-apply:
	kubectl apply -f https://download.elastic.co/downloads/eck/2.16.0/operator.yaml

eck-check:
	kubectl -n elastic-system logs -f statefulset.apps/elastic-operator

elastic-create:
# 	# pushd $(GNOMAD_PROJECT_PATH) && ./deployctl elasticsearch apply --cluster-name=$(CLUSTER_NAME)
	pushd $(GNOMAD_DEPLOYMENTS_PROJECT_PATH)/elasticsearch/base && kubectl apply -f .

# Cannot set env var in parent shell from within make
es-secret-get:
	$(GNOMAD_PROJECT_PATH)/deployctl elasticsearch get-password --cluster-name=$(CLUSTER_NAME)

# bash command to set env var with password
# `-s` is silent (e.g. doesn't print recipe)
# export ELASTICSEARCH_PASSWORD=$(make -s es-secret-get)

es-secret-create-bash:
	# if using bash
	echo -n $$ELASTICSEARCH_PASSWORD | gcloud secrets create gnomad-elasticsearch-password --data-file=- --locations=$(REGION) --replication-policy=user-managed

es-secret-create-zsh:
	# is using zsh
	echo "$$ELASTICSEARCH_PASSWORD\c" | gcloud secrets create gnomad-elasticsearch-password --data-file=- --locations=$(REGION) --replication-policy=user-managed

es-secret-delete:
	gcloud secrets delete gnomad-elasticsearch-password

### Deployment ###

docker:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl images build --push --tag $(DOCKER_TAG)
	# we are not going to use reads for now
	# pushd $(GNOMAD_PROJECT_PATH) && ./deployctl reads-images build --push --tag $(DOCKER_TAG)

# OPTIONAL ARGS: --browser-tag <BROWSER_IMAGE_TAG> --api-tag <API_IMAGE_TAG>
deploy-create:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl deployments create --name $(PROJECT_ID)-$(DEPLOYMENT_STATE) 
	# we are not going to use reads for now
	# pushd $(GNOMAD_PROJECT_PATH) && ./deployctl reads-deployments create --name $(PROJECT_ID)-$(DEPLOYMENT_STATE) 

deploy-apply:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl deployments apply $(PROJECT_ID)-$(DEPLOYMENT_STATE)
	# we are not going to use reads for now
	# pushd $(GNOMAD_PROJECT_PATH) && ./deployctl reads-deployments apply $(PROJECT_ID)-$(DEPLOYMENT_STATE) 

deployments-list:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl deployments list

ingress-apply:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl demo apply-ingress $(PROJECT_ID)-$(DEPLOYMENT_STATE)

ingress-describe:
	# kubectl describe ingress gnomad-ingress-demo-$(PROJECT_ID)-$(DEPLOYMENT_STATE)
	kubectl describe ingress gnomad-ingress-production-$(PROJECT_ID)-$(DEPLOYMENT_STATE)

ingress-get:
	kubectl get ingress

### Clean up deployment ###
ingress-delete:
	# kubectl delete ingress gnomad-ingress-demo-$(PROJECT_ID)-$(DEPLOYMENT_STATE)
	kubectl delete ingress gnomad-ingress-demo-$(PROJECT_ID)-$(DEPLOYMENT_STATE) 

deployments-local-clean:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl deployments clean $(PROJECT_ID)-$(DEPLOYMENT_STATE)
	# we are not going to use reads for now
	# pushd $(GNOMAD_PROJECT_PATH) && ./deployctl reads-deployments clean $(PROJECT_ID)-$(DEPLOYMENT_STATE)

deployments-cluster-delete:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl deployments delete $(PROJECT_ID)-$(DEPLOYMENT_STATE)
	# we are not going to use reads for now
	# pushd $(GNOMAD_PROJECT_PATH) && ./deployctl reads-deployments delete $(PROJECT_ID)-$(DEPLOYMENT_STATE)


