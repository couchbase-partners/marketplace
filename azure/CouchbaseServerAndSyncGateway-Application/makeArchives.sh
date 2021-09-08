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
#  -o : Couchbase Server Offer Id                                             #
#     usage: -o couchbase-server-enterprise                                   #
#     purposes: the offer id of the azure marketplace offer for cbs           #
#  -v : Couchbase Server Image Version                                        #
#     usage: -v 18.4.0                                                        #
#     purposes: The image version specified in the cbs plan                   #
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
  sku=$3
  publisher=$4
  offer=$5
  image_version=$6
  sync_gateway_offer=$7
  sync_gateway_image_version=$8
  sync_gateway_sku=$9
  mkdir -p "$dir../../build/azure/CouchBaseServerAndSyncGateway/"
  rm "$dir../../build/azure/CouchbaseServerAndSyncGateway/azure-cbs-archive-${license}.zip"
  mkdir -p "$dir../../build/tmp"
  SED_VALUE="s~<<LICENSE>>~${sku}~g;s~<<PUBLISHER>>~${publisher}~g;s~<<OFFER>>~${offer}~g;s~<<IMAGE_VERSION>>~${image_version}~g;s~<<SYNC_GATEWAY_IMAGE_VERSION>>~${sync_gateway_image_version}~g;s~<<SYNC_GATEWAY_OFFER>>~${sync_gateway_offer}~g;s~<<SYNC_GATEWAY_SKU>>~${sync_gateway_sku}~g;"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$dir../../build/tmp/mainTemplate.json"
  else
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$dir../../build/tmp/mainTemplate.json"
  fi

  #cp "$dir/mainTemplate.json" "$dir../../build/tmp/mainTemplate.json"
  cp "$dir/createUiDefinition.json" "$dir../../build/tmp"
  SCRIPT_URL=$(cat "$dir../../script_url.txt")
  echo "Downloading install script at: $SCRIPT_URL"
  curl -L "$SCRIPT_URL" -o "$dir../../build/tmp/couchbase_installer.sh"

  cd "$dir../../build/tmp" || exit
  zip -r -j -X "$dir../../build/azure/CouchBaseServerAndSyncGateway/azure-combined-archive-${license}.zip" *
  cd - || exit
  rm -rf "$dir../../build/tmp"
}

while getopts l:p:s:o:v:g:i:u: flag
do
    case "${flag}" in
        l) license=${OPTARG};;
        p) publisher=${OPTARG};;
        s) sku=${OPTARG};;
        o) offer=${OPTARG};;
        v) image_version=${OPTARG};;
        g) sync_gateway_offer=${OPTARG};;
        i) sync_gateway_image_version=${OPTARG};;
        u) sync_gateway_sku=${OPTARG};;
        *) exit 1;;
    esac
done

makeArchive "$license" "$SCRIPT_SOURCE" "$sku" "$publisher" "$offer" "$image_version" "$sync_gateway_offer" "$sync_gateway_image_version" "$sync_gateway_sku"
