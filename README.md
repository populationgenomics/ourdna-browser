# ourdna-browser

This repo contains source code relevant to OurDNA Browser.

OurDNA Browser is CPG customised version of [gnomadBrowser](https://github.com/populationgenomics/gnomad-browser)

It depends as well on [tgg-terraform-modules](https://github.com/populationgenomics/tgg-terraform-modules)

Terraform folder contains infrastracture setup originally provided by [Garvan Institute of Medical Research](https://github.com/Garvan-Data-Science-Platform/gnomad-browser/tree/autism-crc-coverage/terraform)

makefile is work in progress file originally developed by [Garvan Institute of Medical Research](https://github.com/Garvan-Data-Science-Platform/gnomad-browser/blob/autism-crc-coverage/makefile)



# Steps to setup

create .env file with all the env variables

source .env

create tf-remote-state bucket on GCP

make tf-init (will ask for the bucket name)

make config

make config-ls

make gcloud-auth

make tf-apply

make kube-config

make eck-create

make eck-apply

# wait a bit

make eck-check

kubectl port-forward service/gnomad-es-http 9200

export ELASTICSEARCH_PASSWORD=$(make -s es-secret-get)

make es-secret-create-zsh
or make es-secret-create-bash

# created edit 'browser/build.env' in gnomad-browser location
update with the gnomad API url

make docker

make deploy-create

make deploy-apply

make deployments-list

make ingress-apply

make ingress-describe

make ingress-get




# to destroy all:
make ingress-delete
make deployments-local-clean
make deployments-cluster-delete
make es-secret-delete
make tf-destroy

