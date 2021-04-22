Force delete resources created when deploying an RedHat OpenShift Cluster using PowerVS

## Usage


```
  docker build -t powervs-cluster-delete .
  
  docker run -e API_KEY="YOUR_IBM_CLOUD_API_KEY" \
  -e POWERVS_CRN="YOUR_TARGET_POWERVS_CRN" \
  -e CLUSTER_ID="THE_ID_ASSOCIATED_WITH_YOUR_CLUSTER_RESOURCES" \
  powervs-cluster-delete:latest

```

## Getting the CRN

```

ibmcloud login --no-region --apikey $APY_KEY

ibmcloud pi service-list --json | jq '.[] | "\(.CRN),\(.Name)"'

```
