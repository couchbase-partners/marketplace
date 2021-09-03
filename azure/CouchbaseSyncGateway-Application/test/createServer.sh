#!/bin/bash

###############################################################################
# Dependencies:                                                               #
# azure cli                                                                   #
# JQ                                                                          #
# sshpass                                                                     #
###############################################################################

###############################################################################
#  Parameters                                                                 #
#  -l :  Location                                                             #
#     usage: -l eastus                                                        #
#     purpose: Location based on az account list-locations                    #     
#  -g : Resource Group                                                        #
#     usage: -g ja-test-1                                                     #
#     purpose: Specifies the name of the resource group to use. Will create   #
#              if not exists                                                  #
#  -s : Storage Account Name                                                  #
#     usage: -s cb-see-mkt-offer-sa                                           #
#     purposes: names storage account to use                                  #
#  -v : Version of the VM                                                     #
#     usage: -v 2.0.0                                                         #
#     purposes: specify the version of the os disk for the marketplace        # 
###############################################################################

#  Generates a 13 character random string
function __generate_random_string() {
    LENGTH=$1
    NEW_UUID=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c $LENGTH ; echo '')
    echo "${NEW_UUID}"
}

RANDOM_STRING=$(__generate_random_string 8)
VM_NAME="cb_template_${RANDOM_STRING}"
SCRIPT_SOURCE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SKU="18.04-LTS"

while getopts l:g:s:k:u:p:v: flag
do
    case "${flag}" in
        l) LOCATION=${OPTARG};;
        g) RESOURCE_GROUP=${OPTARG};;
        k) SKU=${OPTARG:="18.04-LTS"};;
        u) USERNAME=${OPTARG};;
        p) PASSWORD=${OPTARG};;
        v) VERSION=${OPTARG};;
        *) exit 1;;
    esac
done

LOCATION=${LOCATION:-"eastus"}
USERNAME=${USERNAME:-"couchbase"}
PASSWORD=${PASSWORD:-"foo123!"}
VERSION=${VERSION:-"7.0.0"}

location_exists=$(az account list-locations -o json | jq ".[] | .name" | grep "${LOCATION}" -c)

if [ "$location_exists" = 0 ]; then
    exit 1
fi


group_exists=$(az group exists --name "${RESOURCE_GROUP}")
if [ "$group_exists" != "true" ]; then
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table
fi

VM_IMAGE=$(az vm image list -f UbuntuServer --all | jq '[.[] | select(.sku=='\""$SKU"\"')] | .[-1]')
IMAGE_URN=$(echo "$VM_IMAGE" | jq -r '.urn')
SCRIPT=$(cat "$SCRIPT_SOURCE/../../../script_url.txt")
SERVER_STARTUP=$(sed -e "s~__USERNAME__~$USERNAME~g" "$SCRIPT_SOURCE/serverStartup.sh" | sed -e "s~__PASSWORD__~$PASSWORD~g" | sed -e "s~__INSTALL_SCRIPT__~$SCRIPT~g" | sed -e "s~__VERSION__~$VERSION~g")
SECURITY_GROUP=$(az network nsg create --name "$VM_NAME-nsg" -g "$RESOURCE_GROUP" --location "$LOCATION")
SEC_GROUP_NAME=$(echo "$SECURITY_GROUP" | jq -r '.NewNSG.name')
export RULE=""
RULE=$(az network nsg rule create --name "Couchbase Admin Ports" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "100" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "Couchbase Administration Ports" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 8091-8096 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")

RULE=$(az network nsg rule create --name "Couchbase Index Ports" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "101" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "Couchbase Index Ports" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 9100-9105 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")                     

RULE=$(az network nsg rule create --name "Couchbase Analytics Ports" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "102" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "Couchbase Analytics Ports" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 9110-9122 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")

RULE=$(az network nsg rule create --name "Couchbase FTS Ports" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "103" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "Couchbase FTS Ports" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 9130 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")

RULE=$(az network nsg rule create --name "Couchbase Internal Ports" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "104" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "Couchbase Internal Ports" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 9998-9999 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")

RULE=$(az network nsg rule create --name "Couchbase XDCR Ports" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "105" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "Couchbase XDCR Ports" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 11207-11215 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")                           

RULE=$(az network nsg rule create --name "Couchbase SSL Ports" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "106" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "Couchbase SSL Ports" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 18091-18096 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")

RULE=$(az network nsg rule create --name "Couchbase NDX Ports" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "107" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "Couchbase NDX Ports" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 21100-21299 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")                           

RULE=$(az network nsg rule create --name "SSH Inbound" \
                           --nsg-name "$SEC_GROUP_NAME" \
                           --priority "108" \
                           -g "$RESOURCE_GROUP" \
                           --access "Allow" \
                           --description "SSH inbound port" \
                           --direction "Inbound" \
                           --protocol "Tcp" \
                           --source-port-ranges "*" \
                           --destination-port-ranges 22 \
                           --source-address-prefixes "*" \
                           --destination-address-prefixes "*")

RANDOM_PASSWORD="$(__generate_random_string 16)!"

VM_RESPONSE=$(az vm create \
                --name "$VM_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --location "$LOCATION" \
                --image "$IMAGE_URN" \
                --admin-username couchbase \
                --admin-password "$RANDOM_PASSWORD" \
                --custom-data "$SERVER_STARTUP" \
                --size "Standard_D4s_v3" \
                --nsg "$SEC_GROUP_NAME" \
                --data-disk-sizes-gb 30 \
                )
# az vm disk attach -g "$RESOURCE_GROUP" --vm-name "$VM_NAME" --name "${VM_NAME}Disk" --lun 0 --sku "Premium_LRS" --new --caching None
VM_IP=$(echo "$VM_RESPONSE" | jq -r '.publicIpAddress' )
# If we decide to do more than just an empty OS. .we need to do it before we run this command, as you won't be able to log into the VM once we're done
sub=$(sshpass -p "$RANDOM_PASSWORD" ssh -o StrictHostKeyChecking=no "couchbase@$VM_IP" "sudo awk -F '<ns1:CustomData>|</ns1:CustomData>' '{print \$2}' /var/lib/waagent/ovf-env.xml | base64 -d | sudo bash" 2>&1 >> /dev/null)



echo "{
    \"ip\": \"${VM_IP}\",
    \"password\": \"${RANDOM_PASSWORD}\",
    \"couchbaseUser\": \"$USERNAME\",
    \"couchbasePassword\": \"$PASSWORD\"
}"
