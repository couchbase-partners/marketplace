#!/bin/bash

BYOL=0
ARCHIVE_NAME="gcp-gateway-archive.zip"
IMAGE_FAMILY="couchbase-sync-gateway-hourly-pricing"
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
rm "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/test_config.local.yaml"

# Here is where we need to change the files for byol if byol is set
if [[ "$BYOL" == "1" ]]; then
    echo "BYOL SET!"
    ARCHIVE_NAME="gcp-gateway-byol-archive.zip"
    IMAGE_FAMILY="couchbase-sync-gateway-byol"
fi
echo "IMAGE FAMILY IS: $IMAGE_FAMILY"
IMAGE=$(gcloud compute images list --project couchbase-public --filter="family = $IMAGE_FAMILY" --format="value(NAME)" --sort-by="~creationTimestamp" --limit=1)
echo "IMAGE IS: $IMAGE"
expression=".resources[0].properties.imageName = \"$IMAGE\""
yq e -i "$expression" "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/test_config.yaml"
expression=".properties.imageName.default = \"$IMAGE\""
yq e -i "$expression" "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py.schema"
expression=".imageName = \"$IMAGE\""
config=$(jq "$expression" "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/c2d_deployment_configuration.json")
cat <<< "$config" > "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/c2d_deployment_configuration.json"

# remove existing archive
rm -f "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/$ARCHIVE_NAME"

#Fix pathing for marketplace
sed -e 's|./resources/||g' $SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py > $SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py.tmp && mv $SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py.tmp $SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py
sed -e 's|./resources/||g' $SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py.schema > $SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py.schema.tmp && mv $SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py.schema.tmp $SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/couchbase.py.schema

# zip up the contents of the package into the archive
WDIR=$(pwd) && cd "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/" && zip -r -j -X  "../$ARCHIVE_NAME" ./* && cd "$WDIR" || exit

# remove package folder
#rm -rf "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway/package/"