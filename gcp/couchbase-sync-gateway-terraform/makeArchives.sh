#!/bin/bash

function __generate_random_string() {
    NEW_UUID=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 10 ; echo '')
    echo "${NEW_UUID}"
}

BYOL=0
NOZIP=0

ARCHIVE_NAME="gcp-gateway-tf-archive.zip"
IMAGE_FAMILY="couchbase-sync-gateway-hourly-pricing"
while getopts bn flag
do
    case "${flag}" in
        b) BYOL=1;;
        n) NOZIP=1;;
        *) exit 1;;
    esac
done

# Here is where we need to change the files for byol if byol is set
if [[ "$BYOL" == "1" ]]; then
    echo "BYOL SET!"
    ARCHIVE_NAME="gcp-gateway-byol-tf-archive.zip"
    # modify couchbase.py.schema to change the default value
    # update the c2d_deployment_configuration.json
    # update the test_config.yaml
    IMAGE_FAMILY="couchbase-sync-gateway-byol"
fi

IMAGE=$(gcloud compute images list --project couchbase-public --filter="family = $IMAGE_FAMILY" --format="value(NAME)" --sort-by="~creationTimestamp" --limit=1)

# Here's what we need to do
# 1.  Copy everything except this script into a /build/tmp folder
# 2.  If BYOL -> modify files for BYOL images
# 3.  Create an archive with the appropriate name in /build/gcp/couchbase-server/
# 4.  Delete tmp folder

SCRIPT_SOURCE=${BASH_SOURCE[0]/%makeArchives.sh/}

# Create temp directory
mkdir -p "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/"

# copy files into package directory
cp -a "${SCRIPT_SOURCE}/." "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/"

# remove the archives creation tool
rm "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/makeArchives.sh"
rm "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/terraform.tfvars"
rm "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/.terraform.lock.hcl"
rm "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/terraform.tfstate"
rm "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/terraform.tfstate.backup"
rm -rf "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/.terraform/"

# If we are specifying local copy the test_config.local.yaml over the test_config.yaml

cp -f "${SCRIPT_SOURCE}/terraform.tfvars" "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/marketplace_test.tfvars"



# Set the values in the metadata.display.yaml
echo "$IMAGE"
expression=".spec.ui.input.variables.source_image.enumValueLabels[0].label = \"$IMAGE\""
yq e -i "$expression"  "${SCRIPT_SOURCE}../../build/gcp/couchbase-sync-gateway-tf/package/metadata.display.yaml"
expression=".spec.ui.input.variables.source_image.enumValueLabels[0].value = \"projects/couchbase-public/global/images/$IMAGE\""
yq e -i "$expression"  "${SCRIPT_SOURCE}../../build/gcp/couchbase-sync-gateway-tf/package/metadata.display.yaml"
expression=".spec.interfaces.variables[] |= select(.name == \"source_image\").defaultValue = \"projects/couchbase-public/global/images/$IMAGE\""
yq e -i "$expression"  "${SCRIPT_SOURCE}../../build/gcp/couchbase-sync-gateway-tf/package/metadata.yaml"
random_string=$(__generate_random_string)
echo "server_password = \"$random_string\"" >> "${SCRIPT_SOURCE}../../build/gcp/couchbase-sync-gateway-tf/package/marketplace_test.tfvars"
#Set the value in the variables.tf file
IMAGE_VALUE="\"projects/couchbase-public/global/images/$IMAGE\""
hcledit -f "${SCRIPT_SOURCE}../../build/gcp/couchbase-sync-gateway-tf/package/variables.tf" -u attribute set "variable.source_image.default" "$IMAGE_VALUE"

# Depending on BYOL or not, set title and other spots where it is different
if [[ "$BYOL" == "1" ]]; then
    yq e -i ".metadata.name = \"couchbase-sync-gateway-byol\"" "${SCRIPT_SOURCE}../../build/gcp/couchbase-sync-gateway-tf/package/metadata.display.yaml"
    yq e -i ".metadata.name = \"couchbase-sync-gateway-byol\"" "${SCRIPT_SOURCE}../../build/gcp/couchbase-sync-gateway-tf/package/metadata.yaml"
fi

# Zip up the contents of the package into the archive
if [[ "$NOZIP" == "0" ]]; then
    WDIR=$(pwd) && cd "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/" && zip -r -j -X "../$ARCHIVE_NAME" ./* && cd "$WDIR" || exit
    rm -rf "$SCRIPT_SOURCE../../build/gcp/couchbase-sync-gateway-tf/package/"
fi