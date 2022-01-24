#!/bin/bash

BYOL=0
ARCHIVE_NAME="gcp-gateway-archive.zip"
while getopts b flag
do
    case "${flag}" in
        b) BYOL=1;;
        *) exit 1;;
    esac
done


# Here's what we need to do
# 1.  Copy everything except this script into a /build/tmp folder
# 2.  If BYOL -> modify files for BYOL images
# 3.  Create an archive with the appropriate name in /build/gcp/couchbase-sync-gateway/
# 4.  Delete tmp folder

SCRIPT_SOURCE=${BASH_SOURCE[0]/%makeArchives.sh/}

# Create temp directory
mkdir -p "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/"



# copy files into package directory
cp -a "${SCRIPT_SOURCE}/." "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/"

# remove the archives creation tool
rm "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/makeArchives.sh"

# Here is where we need to change the files for byol if byol is set
if [[ "$BYOL" == "1" ]]; then
    echo "BYOL SET!"
    ARCHIVE_NAME="gcp-gateway-byol-archive.zip"
    # modify couchbase.py.schema to change the default value
    yq e -i '.properties.imageFamily.default = "couchbase-sync-gateway-byol"' "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py.schema"
    # update the c2d_deployment_configuration.json
    config=$(jq '.imageName = "couchbase-sync-gateway-byol"' "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/c2d_deployment_configuration.json")
    cat <<< "$config" > "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/c2d_deployment_configuration.json"
    # update the test_config.yaml
    yq e -i '.resources[0].properties.imageFamily = "couchbase-sync-gateway-byol"' "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/test_config.yaml"
fi
# remove existing archive
rm -f "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/$ARCHIVE_NAME"
# zip up the contents of the package into the archive
WDIR=$(pwd) && cd "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/" && zip -r -X  "../$ARCHIVE_NAME" ./* && cd "$WDIR" || exit

# remove package folder
rm -rf "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/"