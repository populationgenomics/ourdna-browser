# ourdna-browser

This repo contains source code relevant to OurDNA Browser.

OurDNA Browser is CPG customised version of [gnomadBrowser](https://github.com/populationgenomics/gnomad-browser)

It depends on:

[tgg-terraform-modules](https://github.com/populationgenomics/tgg-terraform-modules)

[gnomad-deployments](https://github.com/populationgenomics/gnomad-deployments)

Terraform folder contains infrastracture setup originally provided by [Garvan Institute of Medical Research](https://github.com/Garvan-Data-Science-Platform/gnomad-browser/tree/autism-crc-coverage/terraform)

makefile is work in progress file originally developed by [Garvan Institute of Medical Research](https://github.com/Garvan-Data-Science-Platform/gnomad-browser/blob/autism-crc-coverage/makefile)

Major challange is gnomAD code contains a lot of hardcoded strings, e.g. cluster name is always 'gnomad', the same name is used to create GCP buckets, but GCP buckets have to be unique across all the Google cloud.
This repository is trying to address those things, using environment variables where possible.



## Requirements

-  python3 (minimum 3.8)

-  terraform

-  docker

-  make

-  kustomize (e.g snap install kustomize)

-  gcloud: gke-gcloud-auth-plugin, kubectl

-  service account on GCP with private key

-  Google bucket where terraform state is going to be stored (tf-remote-state)



## Setting Up OurDNA Browser Infrastracture

- Create .env file with all the env variables (look at example.env)

- Create terraform.tfvars in terraform folder (look at terraform.tfvars.example)

- Load the environmental variables:
```
source .env
```

- Initialise terraform, provide tf-remote-state bucket on GCP created prior
```
make tf-init 
```

- Configure / set initial variables:
```
make config
```

- Preview the configuration values:
```
make config-ls
```

- Autheticate GCP service account:
```
make gcloud-auth
```

- Create Cluster (type 'yes' when prompted), this step might take a long time:
```
make tf-apply
```

- Configure Kubernetes:
```
make kube-config
```

- Prepare ES cluster master nodes:
```
make eck-create
make eck-apply
```

- Wait a bit for nodes to start, then check if running:
```
make eck-check
```

- Create ES server
more details [here](https://github.com/broadinstitute/gnomad-deployments/tree/main/elasticsearch)

```
make elastic-create
```

- Create Redis server
```
make redis-create
```

- Wait a bit for ES disks to be created
- Forward ES port so we can talk to it
```
make forward-es-http
```

- Store ES password for later use
```
export ELASTICSEARCH_PASSWORD=$(make -s es-secret-get)
make es-secret-create
```

- Create 'browser/build.env' in gnomad-browser location and provide gnomAD (OurDNA Browser) API url

```
echo 'GNOMAD_API_URL="https://ourdna-dev.popgen.rocks/api"' > $GNOMAD_PROJECT_PATH/browser/build.env
```

- Build all components:
```
make docker
```

-  Create new deployment:
```
make deploy-create
```

- Deploy:
```
make deploy-apply
```

- Preview all deployments:
```
make deployments-list
```

- Setup Ingress (TODO get static IP address working):
```
make ingress-apply
```

- *TODO* fix this one - different for DEV and PRD
```
make ingress-describe
```

- Wait for up to 5 minutes for IP to be allocated
```
make ingress-get

kubectl get ingress
NAME                                           CLASS    HOSTS   ADDRESS        PORTS   AGE
gnomad-ingress-demo-ourdna-browser-dev-green   <none>   *       34.36.115.66   80      3h55m
```


## How to load data into OurDNA Browser ES database:

- Setup your favourite python environment.

- Install requirements:
```
pip install setuptools
pip install -r $GNOMAD_PROJECT_PATH/data-pipeline/requirements.txt
```

- Start dataproc cluster - this might take a while
```
make es-dataproc-start   
```

- Add permissions to existing data-pipeline service account so it can access ES secrets 
```
make es-secret-add
```

- Have hail tables ready in $OUTPUT_BUCKET

- Load dataset
```
make DATASET=clinvar_grch38_variants es-load
```

- Review the loaded indexes:
```
make es-show-indices
```

- Show how much space on ES cluster:
```
make es-show-space
```

- When done with loading shutdown ES loading dataproc cluster (to lower the cost), it will shutdown itself after hour on inactivity

```
make es-dataproc-stop
```


## Destroy all OurDNA Browser Infrastracture (usefull for dev / test environment)

- Stop port frowarding:
```
ps -ef | grep port-forward
kill PID
```

- Delete all:
```
make ingress-delete
```

```
make deployments-local-clean
```

```
make deployments-cluster-delete
```

```
make es-secret-delete
```

- Finally destroy GCP cluster:
```
make tf-destroy
```

- Check for any VM disks, which might be still present, esp. created by ES-create terraform




## How to setup github action to enable CI

TODO !!!

Details [here](https://docs.github.com/en/actions/use-cases-and-examples/deploying/deploying-to-google-kubernetes-engine#configuring-a-service-account-and-storing-its-credentials)

Setup SA

gcloud projects add-iam-policy-binding ourdna-browser \
  --member=serviceAccount:github-deploy@ourdna-browser.iam.gserviceaccount.com \
  --role=roles/container.admin
gcloud projects add-iam-policy-binding ourdna-browser \
  --member=serviceAccount:github-deploy@ourdna-browser.iam.gserviceaccount.com \
  --role=roles/storage.admin
gcloud projects add-iam-policy-binding ourdna-browser \
  --member=serviceAccount:github-deploy@ourdna-browser.iam.gserviceaccount.com \
  --role=roles/container.clusterViewer




