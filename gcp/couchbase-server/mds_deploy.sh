#!/bin/bash

SCRIPT_SOURCE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

while getopts n: flag
do
    case "${flag}" in
        n) STACK_NAME=${OPTARG};;
        *) exit 1;;
    esac
done

CREATE_STACK_NAME="${STACK_NAME}-create"
JOIN_STACK_NAME="${STACK_NAME}-join"

# Step one is perform a deployment to create and read in the runtime config
$SCRIPT_SOURCE/deploy.sh -b -n "$CREATE_STACK_NAME"

JOIN_IP=$($SCRIPT_SOURCE/ip_retrieval.sh -n "$CREATE_STACK_NAME")

YQ_COMMAND=".resources[0].properties.existingRallyUrl = \"${JOIN_IP}\""
yq -i "$YQ_COMMAND" "$SCRIPT_SOURCE/test_config.local.yaml"
yq -i '.resources[0].properties.eventing = true' "$SCRIPT_SOURCE/test_config.local.yaml"
yq -i '.resources[0].properties.analytics = true' "$SCRIPT_SOURCE/test_config.local.yaml"
yq -i '.resources[0].properties.data = false' "$SCRIPT_SOURCE/test_config.local.yaml"
yq -i '.resources[0].properties.query = false' "$SCRIPT_SOURCE/test_config.local.yaml"
yq -i '.resources[0].properties.index = false' "$SCRIPT_SOURCE/test_config.local.yaml"
# Step 3 is to join a deployment to the first deployment
$SCRIPT_SOURCE/deploy.sh -b -n "$JOIN_STACK_NAME"