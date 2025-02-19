# ourdna-browser

This repo contains source code relevant to OurDNA Browser.

OurDNA Browser is CPG customised version of [gnomadBrowser](https://github.com/populationgenomics/gnomad-browser)

It depends as well on [tgg-terraform-modules](https://github.com/populationgenomics/tgg-terraform-modules)

Terraform folder contains infrastracture setup originally provided by [Garvan Institute of Medical Research](https://github.com/Garvan-Data-Science-Platform/gnomad-browser/tree/autism-crc-coverage/terraform)

makefile is work in progress file originally developed by [Garvan Institute of Medical Research](https://github.com/Garvan-Data-Science-Platform/gnomad-browser/blob/autism-crc-coverage/makefile)

Major challange is gnomad code contain a lot fo hardcoded strings, e.g. cluster name is always 'gnomad', the same name is used to create GCP buckets, but GCP buckets have to be unique across all the Google cloud.

# Requirements

python3 (minimum 3.8)

terraform

docker

make

kustomize (e.g snap install kustomize)

gcloud: gke-gcloud-auth-plugin, kubectl

service account on GCP with private key


# Steps to setup

create .env file with all the env variables

create terraform.tfvars in terraform folder (look at terraform.tfvars.example)

source .env

create tf-remote-state bucket on GCP

make tf-init (will ask for the bucket name)

make config

make config-ls

make gcloud-auth

make tf-apply

type 'yes' when prompted

make kube-config

make eck-create

make eck-apply

# wait a bit for container to start

make eck-check

# start ES server

make elastic-create

# more details here https://github.com/broadinstitute/gnomad-deployments/tree/main/elasticsearch

# wait a bit for ES VMs to be created

make forward-es-http

export ELASTICSEARCH_PASSWORD=$(make -s es-secret-get)

make es-secret-create

# created edit 'browser/build.env' in gnomad-browser location
update with the gnomad API url

echo 'GNOMAD_API_URL="https://ourdna-dev.popgen.rocks/api"' > $GNOMAD_PROJECT_PATH/browser/build.env

make docker

make deploy-create

make deploy-apply

make deployments-list

make ingress-apply

# TODO fix this one - different for DEV and PRD
make ingress-describe

# wait for up to 5 minutes for IP to be allocated
make ingress-get

# load data:






# to destroy all:

stop port frowarding:
ps -ef | grep port-forward
kill PID

make ingress-delete
make deployments-local-clean
make deployments-cluster-delete
make es-secret-delete
make tf-destroy

# check for any VM disks, which might be still present, esp. created by ES-create terraform



