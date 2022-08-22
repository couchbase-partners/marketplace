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
#  -g : Couchbase Sync Gateway Offer                                          #
#     usage: -g couchbase-sync-gateway-enterprise                             #
#     purposes: the offer id of the azure marketplace offer for sg            #
#  -i : Couchbase Sync Gateway Image Version                                  #
#     usage: -i 18.4.0                                                        #
#     purposes: the image version specified in the sg plan                    #
#  -u : Sync Gateway SKU                                                      #
#     usage: -u byol_2019                                                     #
#     purposes: specifies the plan id of the VM offer to use                  #
#  -z : Zip Contents                                                          #
#     usage: -z                                                               #
#     purposes: The package will be created in a specific folder, however if  #
#     zip is specified that folder will be zipped into an archive             #
#  -u : Unlicense                                                             #
#     usage: -u                                                               #
#     purposes:  creates an "unlicensed" version that uses a different UI     #
#     definition file to allow user to select license to be used in deployment#
###############################################################################

SCRIPT_SOURCE=${BASH_SOURCE[0]/%makeArchives.sh/}

function makeArchive()
{
  license=$1
  dir=$2
  publisher=$3
  sync_gateway_offer=$4
  sync_gateway_image_version=$5
  sync_gateway_sku=$6
  ZIP=$7
  UNLICENSED=$8

  if [ "$UNLICENSED" == "1" ]; then
    license="unlicensed"
  fi

  mkdir -p "$dir../../build/azure/CouchbaseSyncGateway/"
  if [[ -f "$dir../../build/azure/CouchbaseSyncGateway/azure-sg-archive-${license}.zip" ]]; then
    rm "$dir../../build/azure/CouchbaseSyncGateway/azure-sg-archive-${license}.zip"
  fi
  PACKAGE_DIR="$dir../../build/azure/CouchbaseSyncGateway/azure-sg-archive-${license}"
  mkdir -p "$PACKAGE_DIR"
  SED_VALUE="s~<<PUBLISHER>>~${publisher}~g;s~<<SYNC_GATEWAY_IMAGE_VERSION>>~${sync_gateway_image_version}~g;s~<<SYNC_GATEWAY_OFFER>>~${sync_gateway_offer}~g;s~<<SYNC_GATEWAY_SKU>>~${sync_gateway_sku}~g;"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$PACKAGE_DIR/mainTemplate.json"
  else
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$PACKAGE_DIR/mainTemplate.json"
  fi

  if [ "$UNLICENSED" == "1" ]; then
    cp "$dir/createUiDefinition.Unlicensed.json" "$PACKAGE_DIR/createUiDefinition.json"
  else
    cp "$dir/createUiDefinition.json" "$PACKAGE_DIR"
  fi

  if [[ "$ZIP" == 1 ]]; then
    cd "$PACKAGE_DIR" || exit
    zip -r -j -X "../azure-sg-archive-${license}.zip" *
    cd - || exit
    rm -rf "$PACKAGE_DIR"
  fi
}

ZIP=0
while getopts l:p:g:i:s:zu flag
do
    case "${flag}" in
        l) license=${OPTARG};;
        p) publisher=${OPTARG};;
        g) sync_gateway_offer=${OPTARG};;
        i) sync_gateway_image_version=${OPTARG};;
        s) sync_gateway_sku=${OPTARG};;
        z) ZIP=1;;
        u) UNLICENSED=1;;
        *) exit 1;;
    esac
done
echo "Making Archive"
makeArchive "$license" "$SCRIPT_SOURCE" "$publisher" "$sync_gateway_offer" "$sync_gateway_image_version" "$sync_gateway_sku" "$ZIP" "$UNLICENSED"
