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
#  -z : Zip Contents                                                          #
#     usage: -z                                                               #
#     purposes: The package will be created in a specific folder, however if  #
#     zip is specified that folder will be zipped into an archive             #
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
  ZIP="${10}"
  mkdir -p "$dir../../build/azure/CouchbaseServerAndSyncGateway/"
  if [[ -f "$dir../../build/azure/CouchbaseServerAndSyncGateway/azure-cbs-archive-${license}.zip" ]]; then
    rm "$dir../../build/azure/CouchbaseServerAndSyncGateway/azure-cbs-archive-${license}.zip"
  fi
  PACKAGE_DIR="$dir../../build/azure/CouchbaseServerAndSyncGateway/azure-cbs-archive-${license}"
  mkdir -p "$PACKAGE_DIR"
  SED_VALUE="s~<<LICENSE>>~${sku}~g;s~<<PUBLISHER>>~${publisher}~g;s~<<OFFER>>~${offer}~g;s~<<IMAGE_VERSION>>~${image_version}~g;s~<<SYNC_GATEWAY_IMAGE_VERSION>>~${sync_gateway_image_version}~g;s~<<SYNC_GATEWAY_OFFER>>~${sync_gateway_offer}~g;s~<<SYNC_GATEWAY_SKU>>~${sync_gateway_sku}~g;"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$PACKAGE_DIR/mainTemplate.json"
  else
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$PACKAGE_DIR/mainTemplate.json"
  fi

  #cp "$dir/mainTemplate.json" "$dir../../build/tmp/mainTemplate.json"
  cp "$dir/createUiDefinition.json" "$PACKAGE_DIR"
  SCRIPT_URL=$(cat "$dir../../script_url.txt")
  echo "Downloading install script at: $SCRIPT_URL"
  curl -L "$SCRIPT_URL" -o "$PACKAGE_DIR/couchbase_installer.sh"
  if [[ "$ZIP" == 1 ]]; then
    cd "$PACKAGE_DIR" || exit
    zip -r -j -X "../azure-combined-archive-${license}.zip" *
    cd - || exit
    rm -rf "$PACKAGE_DIR"
  fi
}


ZIP=0
while getopts l:p:s:o:v:g:i:u:z flag
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
        z) ZIP=1;;
        *) exit 1;;
    esac
done

makeArchive "$license" "$SCRIPT_SOURCE" "$sku" "$publisher" "$offer" "$image_version" "$sync_gateway_offer" "$sync_gateway_image_version" "$sync_gateway_sku" "$ZIP"
