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
  ZIP=$7
  unlicensed=$8

  if [ "$unlicensed" == "1" ]; then
    license="unlicensed"
  fi

  mkdir -p "$dir../../build/azure/CouchbaseServer/"
  if [ -f "$dir../../build/azure/CouchbaseServer/azure-cbs-archive-${license}.zip" ]; then
    rm "$dir../../build/azure/CouchbaseServer/azure-cbs-archive-${license}.zip"
  fi
  
  PACKAGE_DIR="$dir../../build/azure/CouchbaseServer/azure-cbs-archive-${license}"
  mkdir -p "$PACKAGE_DIR"
  SED_VALUE="s~<<LICENSE>>~${sku}~g;s~<<PUBLISHER>>~${publisher}~g;s~<<OFFER>>~${offer}~g;s~<<IMAGE_VERSION>>~${image_version}~g;"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$PACKAGE_DIR/mainTemplate.json"
  else
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$PACKAGE_DIR/mainTemplate.json"
  fi

  #cp "$dir/mainTemplate.json" "$dir../../build/tmp/mainTemplate.json"
  if [ "$unlicensed" == "1" ]; then
    cp "$dir/createUiDefinition.Unlicensed.json" "$PACKAGE_DIR/createUiDefinition.json"
  else
    cp "$dir/createUiDefinition.json" "$PACKAGE_DIR"
  fi

  if [[ "$ZIP" == 1 ]]; then
    cd "$PACKAGE_DIR" || exit
    zip -r -j -X "../azure-cbs-archive-${license}.zip" *
    cd - || exit
    rm -rf "$PACKAGE_DIR"
  fi
}

ZIP=0
while getopts l:p:s:o:v:zu flag
do
    case "${flag}" in
        l) license=${OPTARG};;
        p) publisher=${OPTARG};;
        s) sku=${OPTARG};;
        o) offer=${OPTARG};;
        v) image_version=${OPTARG};;
        z) ZIP=1;;
        u) UNLICENSED=1;;
        *) exit 1;;
    esac
done

makeArchive "$license" "$SCRIPT_SOURCE" "$sku" "$publisher" "$offer" "$image_version" "$ZIP" "$UNLICENSED"
