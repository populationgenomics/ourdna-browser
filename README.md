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

## Before starting
### Google Cloud

- Ensure that you've created a service account for you project, following the [guide](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating).
- Create a set of service account keys, following the [guide](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating).
	- Note down the location of the service account key for use in the .env file.

### `.env` file

Make the following changes to the `.env` file:

- Set the following variables to the location of the service account keys:
	- `export SERVICE_ACCOUNT_PKEY="/path/to/sa-pkey.json"` 
	- `export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-pkey.json"`    
- Set `GNOMAD_DEPLOYMENTS_PROJECT_PATH` to the location that [gnomad-deployments](https://github.com/populationgenomics/gnomad-deployment) was cloned to.
- Set `GNOMAD_PROJECT_PATH` to the location that the CPG fork of [gnomad browser](https://github.com/populationgenomics/gnomad-browser) was cloned to.

## Setting Up OurDNA Browser Infrastracture

1. Create .env file with all the env variables (look at `example.env`)

2. Create `terraform.tfvars` in terraform folder (look at `terraform.tfvars.example`)

3. Load the environmental variables:
```
source .env
```

4. Initialise terraform:
```
make tf-init 
```

5. Configure / set initial variables:
```
make config
```

6. Preview the configuration values:
```
make config-ls
```

7. Authenticate GCP service account:
```
make gcloud-auth
```

8. Create Cluster (type 'yes' when prompted), this step might take a long time:
```
make tf-apply
```
The above command relies on `TF_VAR_network_name_prefix` and `TF_VAR_infra_prefix` from the `.env` file. These variables are generated with the `CLUSTER_NAME` and `ENVIRONMENT_TAG` variables.
- `CLUSTER_NAME` is the name of the cluster so it can be anything you want.
- `ENVIRONMENT_TAG` corresponds to the environments in `GNOMAD_DEPLOYMENTS_PROJECT_PATH`.

This step will create buckets based off these environment variables, so make sure that `CLUSTER_NAME` is selected such that the bucket names will be globally unique.

`ENVIRONMENT_TAG` will also determine which sub-directory of `GNOMAD_DEPLOYMENTS_PROJECT_PATH` Terraform will use for configuration, so this is the directory where you specify the amount of resources (such as storage) that the cluster has.

9. Configure Kubernetes:
```
make kube-config
```

10. Prepare ES cluster master nodes:
```
make eck-create
make eck-apply
```

11. Wait a bit for nodes to start, then check if running:
```
make eck-check
```

12. Create ES server (more details [here](https://github.com/broadinstitute/gnomad-deployments/tree/main/elasticsearch)):

```
make elastic-create
```

13. Create Redis server
```
make redis-create
```

14. Wait a bit for ES disks to be created, then forward ES port so we can talk to it:
```
make forward-es-http
```

15. Store ES password for later use:
```
export ELASTICSEARCH_PASSWORD=$(make -s es-secret-get)
make es-secret-create
```

16. Create '`browser/build.env`' in the gnomad-browser location and provide gnomAD (OurDNA Browser) API url:

```
echo 'GNOMAD_API_URL="https://ourdna.populationgenomics.org.au/api"' > $GNOMAD_PROJECT_PATH/browser/build.env
```

17. Build all components:
```
make docker
```

18.  Create new deployment:
```
make deploy-create
```

19. Deploy:
```
make deploy-apply
```

20. Preview all deployments:
```
make deployments-list
```

21. Setup Ingress (TODO get static IP address working).

This requires an external IP address (VPC Network / IP Addresses in the Google Cloud console) that corresponds to the name given by `kubernetes.io/ingress.global-static-ip-name` in `$(GNOMAD_PROJECT_PATH)/deploy/manifests/ingress/$(ENVIRONMENT_TAG)/gnomad.ingress.yaml`.

This step also requires a 'deny-problematic-requests' Cloud Armor policy to be present beforehand ([information here](https://stackoverflow.com/questions/68944745/is-there-a-workaround-to-attach-a-cloud-armor-policy-to-a-load-balancer-created)).

Once these are taken care of, run the following command:
```
make ingress-apply
```

22. **TODO** fix this one - different for DEV and PRD. Check the status of the Ingress resource:
```
make ingress-describe
```

22. Wait for up to 5 minutes, then check that the IP address has been allocated:
```
make ingress-get
```
You should see an address under the `ADDRESS` column:
```
kubectl get ingress
NAME             CLASS    HOSTS                     ADDRESS         PORTS   AGE
gnomad-ingress   <none>                             34.36.115.66    80      39m
```


## How to load data into OurDNA Browser ES database:

1. Setup your favourite python environment.

2. Install requirements:
```
pip install setuptools
pip install -r $GNOMAD_PROJECT_PATH/data-pipeline/requirements.txt
```

3. Start dataproc cluster - this might take a while:
```
make es-dataproc-start   
```

4. Add permissions to existing data-pipeline service account so it can access ES secrets: 
```
make es-secret-add
```

7. Load your dataset.

First, you must have hail tables ready in `$OUTPUT_BUCKET`. 

Then run the following command:
```
make DATASET=genes_grch38 es-load
```

8. Review the loaded indexes.

This requires `ES_MASTER_NODE` to be set in .env.
You can run `kubectl get pods` to see what to use - the pod will be named something like `gnomad-es-master-0`.

Afterwards, run the following command to view the loaded indices:
```
make es-show-indices
```

9. Show how much space on ES cluster:
```
make es-show-space
```

10. When done with loading shutdown ES loading dataproc cluster (to lower the cost), it will shutdown itself after hour on inactivity

```
make es-dataproc-stop
```


## Destroy all OurDNA Browser Infrastracture (usefull for dev / test environment)

1. Stop port forwarding:
```
ps -ef | grep port-forward
kill PID
```

2. Delete all:
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

3. Finally destroy GCP cluster.

If there's any resources (such as your Elasticsearch snapshots bucket) you wish to preserve for a future setup, then you can run `terraform -chdir=./terraform state list` to list the resource paths.
After that, run `terraform -chdir=./terraform state rm <resource.path>` for each resource you want to preserve. This will remove said resources from the Terraform state.

Once that's complete, run the following command to destroy the GCP cluster:
```
make tf-destroy
```

4. Check for any VM disks, which might be still present, esp. created by ES-create terraform

## Backing up
### Creating a backup
To create an ES backup, first create an ES repository that links to your bucket found at `ES_BACKUP_BUCKET`:
```
make es-setup-backup
```
Then create the backup:
```
make es-start-backup
```

### Restoring a backup
List the snapshots that are available for restoring a backup with:
```
make es-ls-backups
```

To determine what indices to restore, describe a snapshot with:
```
make es-backup-details SNAPSHOT_NAME=<snapshot name>
```

And then restore a specific index with:
```
make es-restore-idx SNAPSHOT_NAME=<snapshot name> INDEX_NAME=<index name>
```
