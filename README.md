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
This step requires policy 'deny-problematic-requests' Cloud Armor policy to be present before running the next step
https://stackoverflow.com/questions/68944745/is-there-a-workaround-to-attach-a-cloud-armor-policy-to-a-load-balancer-created

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


## Shutdown / Restart ES only to keep the dev costs down.

Take a GCS snapshot, keep the PDs, scale the ES node pool to 0. Belt-and-braces: snapshot is your durable backup, PDs give fast restore.

- Firstly we need to change the PVC to be Retain (not Delete, default)

```
kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
RECLAIM:.spec.persistentVolumeReclaimPolicy,\
CLAIM:.spec.claimRef.name,\
NS:.spec.claimRef.namespace
```

If it shows `Retain` in RECLAIM, then skip the next step:

- Patch PVC to retain so when we shutdown all the nodes disk won't be deleted:

```
kubectl get pv -o name | xargs -I{} \
  kubectl patch {} --type=merge \
    -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

Verify if patched:

```
kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
RECLAIM:.spec.persistentVolumeReclaimPolicy,\
CLAIM:.spec.claimRef.name,\
NS:.spec.claimRef.namespace
```


- Snapshot to GCS (insurance)
```
export ELASTICSEARCH_PASSWORD=$(make -s es-secret-get)
export ES_MASTER_NODE=<pod-name>
make es-start-backup
make es-ls-backups              # confirm it landed
```

- Scale the Elasticsearch resource to 0 (clean shutdown, PVCs retained)

```
# Find the actual Elasticsearch CR name and namespace
kubectl get elasticsearch -A
# or shortcut:
kubectl get es -A
That'll give you something like:


NAMESPACE   NAME         HEALTH   NODES   VERSION   PHASE   AGE
default     gnomad    green    5       8.x.x     Ready   100d
Then scale with the real name + namespace:


kubectl -n <namespace> scale elasticsearch <name> --replicas=0

# e.g.: kubectl -n default scale elasticsearch gnomad --replicas=0
```

- Resize the es-data node pool to 0

```
gcloud container clusters resize "$CLUSTER_NAME-$ENVIRONMENT_TAG" \
    --node-pool=es-data --num-nodes=0 --zone=$TF_VAR_default_resource_zone
```

- We might need to unblock the drain if GKE is stucked for more than 10-15 minutes:

```
# check if resize is still running 
gcloud container operations list --filter="status=RUNNING"
```

Confirm it's a PDB
```
kubectl get pdb -A
kubectl -n <es-ns> describe pdb
```

You'll likely see something like elasticsearch.k8s.elastic.co PDB with ALLOWED DISRUPTIONS: 0.

Also check what's still on the node:
```
kubectl get nodes -l cloud.google.com/gke-nodepool=es-data
NODE=$(kubectl get nodes -l cloud.google.com/gke-nodepool=es-data -o name | head -1)
kubectl describe $NODE | tail -40    # look for drain/eviction events
```

Now unblock teh drain:
```
kubectl -n default get pdb
kubectl -n default delete pdb gnomad-es-default    # or whatever name shows up
```

After unblocking - check if still running:

```
gcloud compute instances list --filter="name~gke-ourdna-dev-es-data"
```

### Verify data is safe

- PVCs should all be Bound
```
kubectl -n default get pvc | grep elasticsearch
```

- PVs should still exist with RECLAIMPOLICY=Retain

```
kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
RECLAIM:.spec.persistentVolumeReclaimPolicy,\
STATUS:.status.phase,\
CLAIM:.spec.claimRef.name
```

- Underlying GCE PDs

```
gcloud compute disks list --filter="name~pvc-" --format="table(name,sizeGb,type,zone.basename())"
```

You should see 3 ES PVCs Bound, 3 ES PVs with Retain+Bound, and 3 pvc-* disks on GCE.


### Bring-back ES from shutdown

```
gcloud container clusters resize "$CLUSTER_NAME-$ENVIRONMENT_TAG" --node-pool=es-data --num-nodes=5 --zone=$TF_VAR_default_resource_zone
```


