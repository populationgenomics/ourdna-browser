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
ES_MASTER_NODE:=$(ES_MASTER_NODE)
ES_BACKUP_BUCKET:=$(ES_BACKUP_BUCKET)


### Stand up infra
tf-init: ## Initial terraform
	terraform -chdir=./terraform init -backend-config=backend.hcl

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

redis-create:
	pushd $(GNOMAD_DEPLOYMENTS_PROJECT_PATH)/redis && kustomize build $(ENVIRONMENT_TAG) | kubectl apply -f -

blog-create:
	pushd $(GNOMAD_DEPLOYMENTS_PROJECT_PATH)/blog && kustomize build $(ENVIRONMENT_TAG) | kubectl apply -f -

forward-es-http:
	kubectl port-forward service/gnomad-es-http 9200 &> /dev/null &


# Cannot set env var in parent shell from within make
es-secret-get:
	$(GNOMAD_PROJECT_PATH)/deployctl elasticsearch get-password

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

external-security-add:
	curl "https://raw.githubusercontent.com/external-secrets/external-secrets/v0.16.1/deploy/crds/bundle.yaml" | kubectl apply -f -



# OAUTH for blog
oauth-secret-create-zsh:
	echo "$$OAUTH_REC\c" | gcloud secrets create gke-blog-sso-oauth --data-file=- --locations=$(REGION) --replication-policy=user-managed
	# echo "$$OAUTH_REC\c" | kubectl create secret generic gke-blog-sso-oauth -f -

blog-es-secret-add:
	gcloud secrets add-iam-policy-binding gke-blog-sso-oauth \
		--member="serviceAccount:$(CLUSTER_NAME)-$(ENVIRONMENT_TAG)-data-pipeline@$(PROJECT_ID).iam.gserviceaccount.com" \
		--role="roles/secretmanager.secretAccessor"


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
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl ingress apply-ingress --browser-deployment $(PROJECT_ID)-$(DEPLOYMENT_STATE) --env $(ENVIRONMENT_TAG)

ingress-describe:
	kubectl describe ingress gnomad-ingress

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
	
es-dataproc-stop:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl dataproc-cluster stop es

es-secret-add:
	gcloud secrets add-iam-policy-binding gnomad-elasticsearch-password \
		--member="serviceAccount:$(CLUSTER_NAME)-$(ENVIRONMENT_TAG)-data-pipeline@$(PROJECT_ID).iam.gserviceaccount.com" \
		--role="roles/secretmanager.secretAccessor"


# ES backup / restore
es-setup-backup:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-XPUT "localhost:9200/_snapshot/backups" \
		-H 'Content-Type: application/json' \
		--data '{"type": "gcs", "settings": { "bucket": $(ES_BACKUP_BUCKET), "client": "default", "compress": true }}'

es-setup-backup-readonly:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-XPUT "localhost:9200/_snapshot/backups" \
		-H 'Content-Type: application/json' \
		--data '{"type": "gcs", "settings": { "bucket": $(ES_BACKUP_BUCKET), "client": "default", "compress": true, "readonly": true }}'


# This does not remove the content of the bucket, only deregister from the ES
es-deregister-backup:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XDELETE "localhost:9200/_snapshot/backups" 


es-start-backup:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-XPUT "http://localhost:9200/_snapshot/backups/%3Csnapshot-%7Bnow%7BYYYY.MM.dd.HH.mm%7D%7D%3E"

es-ls-backups:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" http://localhost:9200/_snapshot/backups/_all | jq ".snapshots[].snapshot"

es-backup-details:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" http://localhost:9200/_snapshot/backups/$(SNAPSHOT_NAME)/_status | jq ".snapshots[0]"

es-restore-idx:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-X POST "localhost:9200/_snapshot/backups/$(SNAPSHOT_NAME)/_restore?wait_for_completion=false&pretty" \
		-H 'Content-Type: application/json' \
		-d '{ "indices": "$(INDEX_NAME)", "index_settings": { "index.number_of_replicas": 0 }, "include_global_state": false, "rename_pattern": "(.+)", "rename_replacement": "restored-$(INDEX_NAME)", "include_aliases": false }'

es-restore-all:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-X POST "localhost:9200/_snapshot/backups/$(SNAPSHOT_NAME)/_restore?wait_for_completion=false&pretty" \
		-H 'Content-Type: application/json' \
		-d '{ "indices": "*", "index_settings": { "index.number_of_replicas": 0 }, "include_global_state": false, "rename_pattern": "(.+)", "include_aliases": false }'

es-restore-details:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" http://localhost:9200/_cat/recovery

es-del-backup:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XDELETE http://localhost:9200/_snapshot/backups/$(SNAPSHOT_NAME)


# I'm assuming DATASET refers to a `.ht` file in the datapipeline bucket
# run with `make DATASET=gnomad_v2_exome_coverage es-load`
es-load:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl elasticsearch load-datasets --dataproc-cluster es $(DATASET) --secret=gnomad-elasticsearch-password

es-show-info:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET http://localhost:9200

es-show-aliases:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET http://localhost:9200/_cat/aliases

es-show-indices:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET http://localhost:9200/_cat/indices

# Need INDEX_NAME and ALIAS_NAME as env vars
es-make-alias:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-XPOST http://localhost:9200/_aliases \
		--header "Content-Type: application/json" \
		--data '{"actions": [{"add": {"index": "$(INDEX_NAME)", "alias": "$(ALIAS_NAME)"}}]}'

es-show-space:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_cat/allocation?v"

del-es-index:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X DELETE "localhost:9200/$(INDEX_NAME)?pretty"

del-es-alias:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-XPOST http://localhost:9200/_aliases \
		--header "Content-Type: application/json" \
		--data '{"actions": [{"remove": {"index": "$(INDEX_NAME)", "alias": "$(ALIAS_NAME)"}}]}'

es-empty-index:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-XPUT "localhost:9200/$(INDEX_NAME)?pretty" \
		--header "Content-Type: application/json" \
		--data '{"settings": {"number_of_shards": 1, "number_of_replicas": 0}}'

es-alias-search-by-kv:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X POST "localhost:9200/$(ALIAS_NAME)/_search" -H 'Content-Type: application/json' -d'{"query":{"match":{"$(SEARCH_KEY)": "$(SEARCH_VALUE)"}}}'

es-alias-search-by-exome:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X POST "localhost:9200/$(ALIAS_NAME)/_search" -H 'Content-Type: application/json' -d'{"query": {"exists": {"field": "value.exome"}}}'

es-alias-show-all:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X POST "localhost:9200/$(ALIAS_NAME)/_search" -H 'Content-Type: application/json' -d'{"aggs" : {"whatever_you_like_here" : {"terms" : { "field" : "$(SEARCH_KEY)", "size":10000 }}},"size" : 0}'

es-alias-show-top-records:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X POST "localhost:9200/$(ALIAS_NAME)/_search" -H 'Content-Type: application/json' -d'{"size" : $(SEARCH_NO), "query": {"match_all": {}}}'

es-alias-show-records-with-fields:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X POST "localhost:9200/$(ALIAS_NAME)/_search" -H 'Content-Type: application/json' -d'{"size" : $(SEARCH_NO), "query": {"match_all": {}, "fields": ["$(SEARCH_FIELDS)"] }}'

es-alias-show-mapping:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X GET "localhost:9200/$(ALIAS_NAME)/_all/_mapping" -H 'Content-Type: application/json'

es-show-nodes:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_cat/nodes?v&pretty"

es-show-alloc:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_cat/allocation?v"

es-show-tasks:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_tasks?actions=*&detailed"

es-show-node-info:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_nodes/gnomad-es-data-green-1"

es-show-state:
	kubectl get -o yaml es

es-show-health:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_cluster/health"

es-nodes-stats:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_nodes/stats"

es-show-cluster-state:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_cluster/stats"

es-stop-node-shutdown:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X DELETE "localhost:9200/_nodes/gnomad-es-data-green-1/shutdown"

es-show-plugins:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_cat/plugins?v"

es-show-indices-by-node:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_cat/shards?v=true&h=node,index&s=node&index=*"

es-move-index:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -X POST "localhost:9200/_cluster/reroute" -H 'Content-Type: application/json' -d'{"commands": [{"move": {"index": "$(INDEX_NAME)", "shard": 0,"from_node": "$(SOURCE_NODE)", "to_node": "$(TARGET_NODE)"}}]}'

es-show-move-index-status:
	kubectl exec --stdin --tty $(ES_MASTER_NODE) -- curl -u "elastic:$$ELASTICSEARCH_PASSWORD" -XGET "localhost:9200/_cat/recovery/$(INDEX_NAME)?format=json&h=index,shard,time,type,stage,source_node,target_node,bytes_percent"

data-pipeline-run:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl data-pipeline run genes --cluster es

redis-flush:
	kubectl exec --stdin --tty redis-0 -- redis-cli FLUSHALL


## Preparing ClinVar data ###
vep-dataproc-start:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl dataproc-cluster start vep105 --service-account $(CLUSTER_NAME)-$(ENVIRONMENT_TAG)-data-pipeline@$(PROJECT_ID).iam.gserviceaccount.com --init "gs://gcp-public-data--gnomad/resources/vep/v105/vep105-init.sh" --metadata "VEP_CONFIG_PATH=/vep_data/vep-gcloud.json,VEP_CONFIG_URI=file:///vep_data/vep-gcloud.json,VEP_REPLICATE=us" --master-machine-type n1-highmem-8 --worker-machine-type n1-highmem-8 --worker-boot-disk-size=200 --secondary-worker-boot-disk-size=200 --num-secondary-workers 16

vep-dataproc-stop:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl dataproc-cluster stop vep105

vep-data-pipeline-run:
	pushd $(GNOMAD_PROJECT_PATH) && ./deployctl data-pipeline run --cluster vep105 clinvar_grch38


