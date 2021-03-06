#!/bin/bash

SCRIPT_SOURCE=${BASH_SOURCE[0]/%makeArchives.sh/}

function makeArchive()
{
  license=$1
  dir=$2
  mkdir -p "$dir../../build/gcp/couchbase-enterprise-edition-byol/package/"
  rm "$dir../../build/gcp/couchbase-enterprise-edition-byol/archive-${license}.zip"


  cp "${dir}couchbase.py" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package/couchbase.py"
  cp "${dir}couchbase.py.display" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"
  cp "${dir}couchbase.py.schema" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"
  cp "${dir}c2d_deployment_configuration.json" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"
  cp "${dir}test_config.yaml" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"

  cp "$dir../shared/deployment.py" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"
  cp "$dir../shared/cluster.py" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"
  cp "$dir../shared/group.py" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"
  cp "$dir../shared/naming.py" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"

  cp -r "${dir}resources" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"
  # Need to perform the replacement on the group.py for the script_url
  bash "$dir../../script_url_replacer.sh" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package/group.py"
  zip -r -j -X "$dir../../build/gcp/couchbase-enterprise-edition-byol/gcp-cbs-archive-${license}.zip" "$dir../../build/gcp/couchbase-enterprise-edition-byol/package"
  #rm -rf "$dir../../build/tmp"
}

makeArchive byol "$SCRIPT_SOURCE"
