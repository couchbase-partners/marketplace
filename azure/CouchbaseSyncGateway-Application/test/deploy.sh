#!/bin/bash

###############################################################################
# Dependencies:                                                               #
# azure cli                                                                   #
# JQ                                                                          #
###############################################################################

###############################################################################
#  Parameters                                                                 #
#  -l :  Location                                                             #
#     usage: -l eastus                                                        #
#     purpose: Location based on az account list-locations                    #     
#  -p : Parameters                                                            #
#     usage:  -p mainTemplateParameterss.json                                 #
#     purpose:  Pass in a parameters file for the mainTemplate                #
#  -g : Resource Group                                                        #
#     usage: -g ja-test-1                                                     #
#     purpose: Specifies the name of the resource group to use. Will create   #
#              if not exists                                                  #
#  -n : Deployment Name                                                       #
#     usage: -n test_deployment_one                                           #
#     purposes: names the deployment in azure                                 #
###############################################################################

SCRIPT_SOURCE=${BASH_SOURCE[0]/%deploy.sh/}

dir="${SCRIPT_SOURCE}../"
# RUN THIS TO CREATE THE TEMPLATE
#mkdir -p "${dir}../../build/azure/CouchBaseSyncGateway"
#node "${dir}compiler.js" "${dir}mainTemplate.json" "${dir}embedded_gateway.sh" "${dir}../../script_url.txt" > "$dir../../build/azure/CouchBaseSyncGateway/azure-sg-template.json"
###
TEMPLATE="${dir}../../build/azure/CouchBaseSyncGateway/azure-sg-template.json"

while getopts l:p:g:n:s:b:d:u:v:q: flag
do
    case "${flag}" in
        l) LOCATION=${OPTARG};;
        p) PARAMETERS=${OPTARG};;
        g) RESOURCE_GROUP=${OPTARG};;
        n) NAME=${OPTARG};;
        s) SERVER=${OPTARG};;
        b) BUCKET=${OPTARG};;
        d) DATABASE=${OPTARG};;
        u) USERNAME=${OPTARG};;
        v) VERSION=${OPTARG};;
        q) PASSWORD=${OPTARG};;
        *) exit 1;;
    esac
done

echo "Location: ${LOCATION}"
echo "Parameters: ${PARAMETERS}"
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Deployment Name: ${NAME}"

if [ -f "$PARAMETERS" ]; then
    echo "${PARAMETERS} exists"
else
    echo "Parameters file does not exist."
    exit 1
fi
location_exists=$(az account list-locations -o json | jq ".[] | .name" | grep ${LOCATION} -c)

if [ "$location_exists" = 0 ]; then
    echo "Invalid location."
    exit 1
fi

if [ "$(az group exists --name ${RESOURCE_GROUP})" = "true" ]; then
    echo "Group Exists, skipping creation"
else
    az group create --name $RESOURCE_GROUP --location $LOCATION --output table
fi
JQVals=".couchbaseServerUrl.value = \"$SERVER\" | .couchbaseBucket.value = \"$BUCKET\" | .couchbaseDatabaseName.value = \"$DATABASE\" | .couchbaseUser.value = \"$USERNAME\" | .couchbasePassword.value = \"$PASSWORD\" | .syncGatewayVersion.value = \"$VERSION\""
PARAMS=$(jq "$JQVals" "$PARAMETERS")

az deployment group create --verbose --template-file "$TEMPLATE" --parameters "$PARAMS" --resource-group "$RESOURCE_GROUP" --name "$NAME" --output table
