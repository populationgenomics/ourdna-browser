# ourdna-browser

This repo contains source code relevant to OurDNA Browser.

OurDNA Browser is CPG customised version of [gnomadBrowser](https://github.com/populationgenomics/gnomad-browser)

It depends as well on [tgg-terraform-modules](https://github.com/populationgenomics/tgg-terraform-modules)

Terraform folder contains infrastracture setup originally provided by [Garvan Institute of Medical Research](https://github.com/Garvan-Data-Science-Platform/gnomad-browser/tree/autism-crc-coverage/terraform)

makefile is work in progress file originally developed by [Garvan Institute of Medical Research](https://github.com/Garvan-Data-Science-Platform/gnomad-browser/blob/autism-crc-coverage/makefile)



# Steps to setup

create .env file with all the env variables

source .env

create tf-state bucket

make tf-init

make config

make config-ls

make gcloud-auth

make tf-apply

make kube-config