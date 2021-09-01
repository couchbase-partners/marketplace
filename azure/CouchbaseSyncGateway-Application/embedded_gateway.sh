#!/usr/bin/env bash
# This script is embedded in the ARM template and injected as the userData on the Azure VM.  
set -eux
echo "Running startup script..."

mkdir -p /setup/

until apt-get update > /dev/null; do
    echo "Error getting lock"
    sleep 2
done

until apt-get install jq -y -qq > /dev/null; do
    echo "Error getting lock"
    sleep 2
done
#These values will be replaced with appropriate values during compilation into the Cloud Formation Template
#To run directly, simply set values prior to executing script.  Any variable with $__ prefix and __ suffix will
#get replaced during compliation

# shellcheck disable=SC2154
VERSION=$__syncGatewayVersion__
# shellcheck disable=SC2154
CLUSTER_HOST=$__couchbaseServerUrl__
# shellcheck disable=SC2154
USERNAME=$__couchbaseUser__
# shellcheck disable=SC2154
PASSWORD=$__couchbasePassword__
# shellcheck disable=SC2154
DATABASE=$__couchbaseDatabaseName__
# shellcheck disable=SC2154
BUCKET=$__couchbaseBucket__


# __SCRIPT_URL__ gets replaced during build
if [[ ! -e "/setup/couchbase_installer.sh" ]]; then
    curl -L --output "/setup/couchbase_installer.sh" "__SCRIPT_URL__"
fi

bash /setup/couchbase_installer.sh -ch "http://localhost:8091" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os UBUNTU -e AZURE -c -d -g
echo "
{
  \"interface\":\"0.0.0.0:4984\",
  \"adminInterface\":\"0.0.0.0:4985\",
  \"metricsInterface\":\"0.0.0.0:4986\",
  \"logging\": {
    \"console\": {
      \"log_keys\": [\"*\"]
    }
  },
  \"databases\": {
    \"$DATABASE\": {
      \"server\": \"$CLUSTER_HOST\",
      \"username\": \"$USERNAME\",
      \"password\": \"$PASSWORD\",
      \"bucket\": \"$BUCKET\",
      \"users\": {
        \"GUEST\": {
          \"disabled\": false,
          \"admin_channels\": [\"*\"]
        }
      },
      \"allow_conflicts\": false,
      \"revs_limit\": 20,
      \"import_docs\": true,
      \"enable_shared_bucket_access\":true,
      \"num_index_replicas\":0
    }
  }
}      
   " > /home/sync_gateway/sync_gateway.json

service sync_gateway restart