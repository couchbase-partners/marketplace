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
  mkdir -p "$dir../../build/azure/CouchBaseServer/"
  rm "$dir../../build/azure/CouchbaseServer/azure-cbs-archive-${license}.zip"
  mkdir -p "$dir../../build/tmp"
  SED_VALUE="s~<<LICENSE>>~${sku}~g;s~<<PUBLISHER>>~${publisher}~g;s~<<OFFER>>~${offer}~g;s~<<IMAGE_VERSION>>~${image_version}~g;"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$dir../../build/tmp/mainTemplate.json"
  else
    sed -e "$SED_VALUE" "$dir/mainTemplate.json" > "$dir../../build/tmp/mainTemplate.json"
  fi

  #cp "$dir/mainTemplate.json" "$dir../../build/tmp/mainTemplate.json"
  cp "$dir/createUiDefinition.json" "$dir../../build/tmp"

  cd "$dir../../build/tmp" || exit
  zip -r -j -X "$dir../../build/azure/CouchBaseServer/azure-cbs-archive-${license}.zip" *
  cd - || exit
  rm -rf "$dir../../build/tmp"
}

while getopts l:p:s:o:v: flag
do
    case "${flag}" in
        l) license=${OPTARG};;
        p) publisher=${OPTARG};;
        s) sku=${OPTARG};;
        o) offer=${OPTARG};;
        v) image_version=${OPTARG};;
        *) exit 1;;
    esac
done

makeArchive "$license" "$SCRIPT_SOURCE" "$sku" "$publisher" "$offer" "$image_version"
