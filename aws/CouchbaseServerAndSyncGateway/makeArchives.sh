#!/usr/bin/env bash

SCRIPT_SOURCE=${BASH_SOURCE[0]/%makeArchives.sh/}
mkdir -p "$SCRIPT_SOURCE../../build/aws/CouchbaseServerAndSyncGateway/"
# First we need to replace the URL to the install script based on the root script_url txt
node "${SCRIPT_SOURCE}compiler.js" "${SCRIPT_SOURCE}mappings.byol.json" "${SCRIPT_SOURCE}../../script_url.txt" > "$SCRIPT_SOURCE../../build/aws/CouchbaseServerAndSyncGateway/aws-cbs-byol.template"
node "${SCRIPT_SOURCE}compiler.js" "${SCRIPT_SOURCE}mappings.hourly.json" "${SCRIPT_SOURCE}../../script_url.txt" > "$SCRIPT_SOURCE../../build/aws/CouchbaseServerAndSyncGateway/aws-cbs-hourly-pricing.template"