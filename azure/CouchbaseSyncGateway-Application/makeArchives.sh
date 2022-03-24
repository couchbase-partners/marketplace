#!/bin/bash

###############################################################################
# Dependencies:                                                               #
# curl                                                                        #
# sed                                                                         #
###############################################################################

###############################################################################
#  Parameters                                                                 #
#  -l :  license                                                              #
#     usage: -l byol                                                          #
#     purpose: license to be used in archive name                             #     
#  -p : Publisher                                                             #
#     usage:  -p couchbase                                                    #
#     purpose:  The publisher of the VM images used in the template           #
#  -s : Couchbase Server SKU                                                  #
#     usage: -s byol_2019                                                     #
#     purpose: specifies the plan id of the VM offer to use                   #
#  -g : Couchbase Sync Gateway Offer                                          #
#     usage: -g couchbase-sync-gateway-enterprise                             #
#     purposes: the offer id of the azure marketplace offer for sg            #
#  -i : Couchbase Sync Gateway Image Version                                  #
#     usage: -i 18.4.0                                                        #
#     purposes: the image version specified in the sg plan                    #
#  -u : Sync Gateway SKU                                                      #
#     usage: -u byol_2019                                                     #
#     purposes: specifies the plan id of the VM offer to use                  #
###############################################################################

SCRIPT_SOURCE=${BASH_SOURCE[0]/%makeArchives.sh/}

function makeArchive()
{
  license=$1
  dir=$2
  publisher=$4
  sync_gateway_offer=$7
  sync_gateway_image_version=$8
  sync_gateway_sku=$9
  mkdir -p "$dir../../build/azure/CouchBaseSyncGateway/"
  rm "$dir../../build/azure/CouchBaseSyncGateway/azure-sg-archive-${license}.zip"
  mkdir -p "$dir../../build/tmp"
  SED_VALUE="s~<<PUBLISHER>>~${publisher}~g;s~<<SYNC_GATEWAY_IMAGE_VERSION>>~${sync_gateway_image_version}~g;s~<<SYNC_GATEWAY_OFFER>>~${sync_gateway_offer}~g;s~<<SYNC_GATEWAY_SKU>>~${sync_gateway_sku}~g;"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$dir../../build/tmp/mainTemplate.json"
  else
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$dir../../build/tmp/mainTemplate.json"
  fi

  cp "$dir/createUiDefinition.json" "$dir../../build/tmp"
  cd "$dir../../build/tmp" || exit
  zip -r -j -X "$dir../../build/azure/CouchBaseSyncGateway/azure-sg-archive-${license}.zip" *
  cd - || exit
  rm -rf "$dir../../build/tmp"
}

while getopts l:p:g:i:u: flag
do
    case "${flag}" in
        l) license=${OPTARG};;
        p) publisher=${OPTARG};;
        g) sync_gateway_offer=${OPTARG};;
        i) sync_gateway_image_version=${OPTARG};;
        u) sync_gateway_sku=${OPTARG};;
        *) exit 1;;
    esac
done
echo "Making Archive"
makeArchive "$license" "$SCRIPT_SOURCE" "$publisher" "$sync_gateway_offer" "$sync_gateway_image_version" "$sync_gateway_sku"
