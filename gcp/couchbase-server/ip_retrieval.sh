#!/bin/bash

# GET IP ADDRESS FROM DEPLOYMENT
while getopts n: flag
do
    case "${flag}" in
        n) STACK_NAME=${OPTARG};;
        *) exit 1;;
    esac
done
gcloud components install beta --quiet > /dev/null 2>&1
RUNTIME_CONFIG=$(gcloud deployment-manager deployments describe "$STACK_NAME" --format=json --quiet | jq -r '.outputs[] | select(.name=="runtimeConfigName") | .finalValue')
EXTERNALIP=$(gcloud beta runtime-config configs variables describe ExternalIp --config-name="$RUNTIME_CONFIG" --format=json --quiet | jq -r '.value')

echo "$EXTERNALIP"