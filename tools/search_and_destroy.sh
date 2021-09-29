#!/bin/bash

: '
    Copyright (C) 2021 IBM Corporation
    Rafael Sene <rpsene@br.ibm.com> - Initial implementation.
'

CONTAINER_IMAGE=quay.io/powercloud/powervs-actions:delete-ocp-cluster

clear(){
    local API_KEY="$1"
    local POWERVS_CRN="$2"
    local CLUSTER_ID="$3"
    local PVS_REGION
    local GUID

    PVS_REGION=$(echo "$POWERVS_CRN" | awk -F ":" '{print $6}')
    GUID=$(echo "$POWERVS_CRN" | awk -F ':' '{print $8}')

    docker run -d -t --rm --name=pvsdel-"$CLUSTER_ID"-"$PVS_REGION"-"$GUID" \
    -e API_KEY="$API_KEY" -e POWERVS_CRN="$POWERVS_CRN" \
    -e CLUSTER_ID="$CLUSTER_ID" -e VPC_REGION="$VPC_REGION" "$CONTAINER_IMAGE"
}

main(){

    API_KEY="$1"
    CLUSTER_ID="$2"
    
    if [ -z "$API_KEY" ]; then
        echo "API_KEY was not set."
        exit 1
    fi
    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi

    # get all CRN
    CRN=("$(ibmcloud pi service-list --json | jq -r '.[] | "\(.CRN)"')")
    for crn in "${CRN[@]}"; do
        clear "$API_KEY" "$crn" "$CLUSTER_ID" &
    done
    wait 
    echo "INFO: all containers were launched."
    docker ps
}

main "$IBM_CLOUD_API_KEY" "$CLUSTER_ID"
