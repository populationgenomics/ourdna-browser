SHELL = /bin/bash

# Makefile to make it easier to deploy gnomAD
# This file was originally developed by Garvan team:
# https://github.com/Garvan-Data-Science-Platform/gnomad-browser/blob/autism-crc-coverage/makefile
# It has been refactored to move all hardcoded variables to env variables

# Here is the list of required ENV variables:
PROJECT_ID:=$(PROJECT_ID)
REGION:=$(REGION)
READS_INSTANCE_NAME:=
DOMAIN:=$(DOMAIN)
ZONE:=$(REGION)-a
OUTPUT_BUCKET:=$(OUTPUT_BUCKET)
CLUSTER_NAME:=$(CLUSTER_NAME)
SUBNET_NAME:=$(SUBNET_NAME)
AUTOSCALING_POLICY_NAME:=$(AUTOSCALING_POLICY_NAME)

# dev or prod
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

# loading ES specific, for DEV 1 is enough
LOAD_NODE_POOL_SIZE:=$(LOAD_NODE_POOL_SIZE)


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
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set cluster_name $(CLUSTER_NAME)
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config set domain $(DOMAIN)

config-ls: ## Set deployctl config
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl config list

gcloud-auth: ## Authenticate with gcloud
	gcloud auth activate-service-account $(SERVICE_ACCOUNT) --key-file=$(SERVICE_ACCOUNT_PKEY) --project=$(PROJECT_ID)
	gcloud auth configure-docker $(GCP_DOCKER_REGISTRY)

kube-config: ## Configure kubectl
	gcloud container clusters get-credentials $(CLUSTER_NAME)-$(ENVIRONMENT_TAG) --region=$(ZONE)


### Pre-Deployment ###

eck-create:
	kubectl create -f https://download.elastic.co/downloads/eck/2.16.0/crds.yaml

eck-apply:
	kubectl apply -f https://download.elastic.co/downloads/eck/2.16.0/operator.yaml

eck-check:
	kubectl -n elastic-system logs -f statefulset.apps/elastic-operator

elastic-create:
	pushd $(GNOMAD_DEPLOYMENTS_PROJECT_PATH)/elasticsearch && kustomize build $(ENVIRONMENT_TAG) | kubectl apply -f -
	
forward-es-http:
	kubectl port-forward service/gnomad-es-http 9200 &> /dev/null &


# Cannot set env var in parent shell from within make
es-secret-get:
	$(GNOMAD_PROJECT_PATH)/deployctl elasticsearch get-password --cluster-name=$(CLUSTER_NAME)

# bash command to set env var with password
# `-s` is silent (e.g. doesn't print recipe)
# export ELASTICSEARCH_PASSWORD=$(make -s es-secret-get)

es-secret-create:
	# This is correct syntax if running under bash
	echo -n $$ELASTICSEARCH_PASSWORD | gcloud secrets create gnomad-elasticsearch-password --data-file=- --locations=$(REGION) --replication-policy=user-managed

es-secret-create-zsh:
	# if running using zsh needs different syntax
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
	ifeq($(ENVIRONMENT_TAG),dev)
		kubectl describe ingress gnomad-ingress-demo-$(PROJECT_ID)-$(DEPLOYMENT_STATE)
	else
		kubectl describe ingress gnomad-ingress-production-$(PROJECT_ID)-$(DEPLOYMENT_STATE)
	endif

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


## Loading ES data ###
es-dataproc-start:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl dataproc-cluster start es --num-preemptible-workers $(LOAD_NODE_POOL_SIZE) --service-account $(CLUSTER_NAME)-$(ENVIRONMENT_TAG)-data-pipeline@$(PROJECT_ID).iam.gserviceaccount.com
		
es-secret-add:
	gcloud secrets add-iam-policy-binding gnomad-elasticsearch-password \
		--member="serviceAccount:$(CLUSTER_NAME)-$(ENVIRONMENT_TAG)-data-pipeline@$(PROJECT_ID).iam.gserviceaccount.com" \
		--role="roles/secretmanager.secretAccessor"

# I'm assuming DATASET refers to a `.ht` file in the datapipeline bucket
# run with `make DATASET=gnomad_v2_exome_coverage es-load`
es-load:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl elasticsearch load-datasets --dataproc-cluster es $(DATASET) --cluster-name=$(CLUSTER_NAME)-$(ENVIRONMENT_TAG) --secret=gnomad-elasticsearch-password


