#!/usr/bin/env bash

: '
    Copyright (C) 2021 IBM Corporation
    Rafael Sene <rpsene@br.ibm.com> - Initial implementation.
'

# Trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
    echo "Bye!"
    exit 0
}

function check_dependencies() {

    DEPENDENCIES=(ibmcloud curl sh wget jq)
    check_connectivity
    for i in "${DEPENDENCIES[@]}"
    do
        if ! command -v "$i" &> /dev/null; then
            echo "$i could not be found, exiting!"
            exit
        fi
    done
}

function check_connectivity() {

    if ! curl --output /dev/null --silent --head --fail http://cloud.ibm.com; then
        echo
        echo "ERROR: please, check your internet connection."
        exit 1
    fi
}

function authenticate() {
    echo "authenticate"
    local APY_KEY="$1"

    if [ -z "$APY_KEY" ]; then
        echo "API KEY was not set."
        exit 1
    fi
    ibmcloud update -f > /dev/null 2>&1
    ibmcloud plugin update --all -f > /dev/null 2>&1
    ibmcloud login --no-region --apikey "$APY_KEY"
}

function authenticate_with_region() {
    echo "authenticate_with_region"
    local APY_KEY="$1"
    local VPC_REGION="$2"

    if [ -z "$APY_KEY" ]; then
        echo "API KEY was not set."
        exit 1
    fi
    ibmcloud update -f > /dev/null 2>&1
    ibmcloud plugin update --all -f > /dev/null 2>&1
    ibmcloud login -r "$VPC_REGION" --apikey "$APY_KEY"
}


function set_powervs() {

    local CRN="$1"

    if [ -z "$CRN" ]; then
        echo "CRN was not set."
        exit 1
    fi
    ibmcloud pi st "$CRN"
}

function delete_unused_volumes() {

    local JSON=/tmp/volumes-log.json

    > "$JSON"
    ibmcloud pi volumes --json | jq -r '.Payload.volumes[] | "\(.volumeID),\(.pvmInstanceIDs)"' >> $JSON

    while IFS= read -r line; do
        VOLUME=$(echo "$line" | awk -F ',' '{print $1}')
        VMS_ATTACHED=$(echo "$line" | awk -F ',' '{print $2}' | tr -d "\" \[ \]")
        if [ -z "$VMS_ATTACHED" ]; then
            echo "No VMs attached, deleting ..."
	    ibmcloud pi volume-delete "$VOLUME"
        fi
    done < "$JSON"
}

function delete_vms(){
    echo "Deleting VMs..."
    rpsene-aaa5-lon06=$1

    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi
    echo "Deleting VMs which matches $CLUSTER_ID..."
    ibmcloud pi ins --json | jq -r '.Payload.pvmInstances[] | "\(.pvmInstanceID),\(.serverName)"' | \
    grep "$CLUSTER_ID" | awk -F ',' '{print $1}' | xargs -n1 ibmcloud pi instance-delete
}

function delete_network() { 
    echo "Deleting Network..."
    CLUSTER_ID=$1

    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi

    ibmcloud pi nets --json | jq -r '.Payload.networks[] | "\(.name),\(.networkID)"' | grep "$CLUSTER_ID" | \
    awk -F ',' '{print $2}' | xargs -n1 ibmcloud pi network-delete
}

function delete_ssh_key(){
    echo "Deleting SSH Key..."
    CLUSTER_ID=$1

    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi

    ibmcloud pi keys --json | jq -r '.[].name' | grep "$CLUSTER_ID" | xargs -n1 ibmcloud pi key-delete
}

function clean_vpc_and_dns(){
    echo "Cleaning VPC, DNS and Security Groups..."
    CLUSTER_ID=$1
    VPC_REGION=$2

    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi
    
    LBS=($(ibmcloud is lbs --json | jq -r '.[] | "\(.id),\(.name)"' | grep $CLUSTER_ID))
    RGROUP=($(ibmcloud is security-groups --output json | jq -r '.[] | "\(.id),\(.name)"' | grep $CLUSTER_ID))
    DNS=($(ibmcloud sl dns record-list ocp-ppc64le.com --output json | jq -r '.[] | "\(.data),\(.host),\(.id)"' | grep $CLUSTER_ID))
    
    if [ ${#DNS[@]} -eq 0 ]; then
    	echo "There is no DNS entries to delete!"
    else
	for dns in "${DNS[@]}"; do
		DNS_DATA=$(echo "$dns" | awk -F ',' '{print $1}')
        	DNS_HOST=$(echo "$dns" | awk -F ',' '{print $2}')
		DNS_ID=$(echo "$dns" | awk -F ',' '{print $3}')

        	echo "Deleting... $DNS_DATA,$DNS_HOST..."
		ibmcloud sl dns record-remove "$DNS_ID"
	done
   fi
   sleep 2m

   if [ ${#LBS[@]} -eq 0 ]; then
       echo "There is no load balancers to delete!"
   else
      for lbs in "${LBS[@]}"; do
          LBS_ID=$(echo "$lbs" | awk -F ',' '{print $1}')
          LBS_NAME=$(echo "$lbs" | awk -F ',' '{print $2}')

          if [ "$LBS_ID" ]; then
              echo "Deleting... $LBS_NAME..."
              ibmcloud is lbd "$LBS_ID" -f
          fi
       done
   fi
   sleep 8m
    
   if [ ${#RGROUP[@]} -eq 0 ]; then
       echo "There is no resource group to delete!"
   else
       for rg in "${RGROUP[@]}"; do
           RG_ID=$(echo "$rg" | awk -F ',' '{print $1}')
           RG_NAME=$(echo "$rg" | awk -F ',' '{print $2}')
           echo "Deleting... $RG_NAME..."
           ibmcloud is security-group-delete "$RG_ID" -f
       done
   fi
}

function clean_powervs(){
    echo "Cleaning PowerVS..."
    local POWERVS_CRN="$1"
    local CLUSTER_ID="$2"

    set_powervs "$POWERVS_CRN"

    delete_vms "$CLUSTER_ID"
    delete_ssh_key "$CLUSTER_ID"

    #    PowerVS takes some time to remove the VMs
    #    sleep for 1 min to avoid any issue deleting
    #    volumes andnetwork
    sleep 2m
    delete_network "$CLUSTER_ID"
    sleep 2m
    delete_unused_volumes
}

function help() {

    echo
    echo "clear-cluster.sh API_KEY POWERVS_CRN VPC_REGION (optional) CLUSTER_ID"
    echo
    echo  "CLUSTER_ID can be any string associated with your cluster and its resources"
}

function run() {

    if [ -z "$API_KEY" ]; then
        echo "API_KEY was not set."
        exit 1
    fi
    if [ -z "$POWERVS_CRN" ]; then
        echo "POWERVS was not set."
	echo "ibmcloud pi service-list --json | jq '.[] | \"\(.CRN),\(.Name)\"'"
        exit 1
    fi
    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
      	echo "Some string which identify the cluster"
      	exit 1
    fi

    check_dependencies
    check_connectivity

    if [ -z "$VPC_REGION" ]; then
        echo "VPC_REGION was not set."
      	echo "Authenticating without region."
	authenticate "$API_KEY"
	clean_powervs "$POWERVS_CRN" "$CLUSTER_ID"
    else
    	echo "VPC_REGION was set."
      	echo "Authenticating using $VPC_REGION vpc region."
	authenticate_with_region "$API_KEY" "$VPC_REGION"
	clean_powervs "$POWERVS_CRN" "$CLUSTER_ID"
	clean_vpc_and_dns "$CLUSTER_ID" "$VPC_REGION"
    fi
}

run "$@"
