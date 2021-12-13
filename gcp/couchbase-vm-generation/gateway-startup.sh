#!/usr/bin/env bash
set -x
echo 'Running startup script...'
# There is a race condition based on when the env vars are set by profile.d and when cloud-init executes
# this just removes that race condition
if [[ -r /etc/profile.d/couchbaseserver.sh ]]; then
   # Disabling lint for unreachable source file
   # shellcheck disable=SC1091
   source /etc/profile.d/couchbaseserver.sh
fi

function __get_gcp_metadata_value() {
    wget -O - \
         --header="Metadata-Flavor:Google" \
         -q \
         --retry-connrefused \
         --waitretry=1 \
         --read-timeout=10 \
         --timeout=10 \
         -t 5 \
         "http://metadata/computeMetadata/v1/$1"
}

function __get_gcp_attribute_value() {
    __get_gcp_metadata_value "instance/attributes/$1"
}


if curl http://127.0.0.1:4984/; then
   echo "Server already running. Exiting"
   exit 0
fi

VERSION=$(__get_gcp_attribute_value "couchbase-gateway-version")
SECRET=$(__get_gcp_attribute_value "couchbase-gateway-secret")
CONNECTION_STRING=$(__get_gcp_attribute_value "couchbase-gateway-connection-string")
CONNECTION_PARAM=$(__get_gcp_attribute_value "couchbase-gateway-connection-parameter")
CONFIG=$(__get_gcp_attribute_value "couchbase-gateway-config")
BUCKET=$(__get_gcp_attribute_value "couchbase-gateway-bucket")
TAGGED_USERNAME=$(__get_gcp_attribute_value "couchbase-gateway-username")
TAGGED_PASSWORD=$(__get_gcp_attribute_value "couchbase-gateway-password")



# if no version, use built in version
if [[ -z "$VERSION" ]]; then
    VERSION="$COUCHBASE_GATEWAY_VERSION"
fi

# Connection string should be param if passed
if [[ -n "$CONNECTION_PARAM" ]]; then
    CONNECTION_STRING=$(gcloud secrets versions access latest --secret="$CONNECTION_PARAM")
fi


# if we don't have a connection string we need some default.. so we'll default to localhost
if [[ -z "$CONNECTION_STRING" ]]; then
    CONNECTION_STRING="couchbase://localhost"
fi

if [[ ! "$CONNECTION_STRING" =~ ^couchbase*|^http* ]]; then
    CONNECTION_STRING="couchbase://${CONNECTION_STRING}"
fi

# if we don't have a bucket we need to default to something
if [[ -z "$BUCKET" ]]; then
    BUCKET="travel-sample"
fi


if [[ -n "$SECRET" ]]; then
   SECRET_VALUE=$(gcloud secrets versions access latest --secret="$SECRET")
   USERNAME=$(echo "$SECRET_VALUE" | jq -r .username)
   PASSWORD=$(echo "$SECRET_VALUE" | jq -r .password)
elif [[ -n "$TAGGED_USERNAME" ]] && [[ -n "$TAGGED_PASSWORD" ]]; then
   USERNAME="$TAGGED_USERNAME"
   PASSWORD="$TAGGED_PASSWORD"
else
   USERNAME="NO-USER"
   PASSWORD="NO-PASSWORD"
fi


mkdir -p /opt/sync_gateway/etc/
# Setup Config


SUCCESS=1

if [[ "$COUCHBASE_GATEWAY_VERSION" == "$VERSION" ]]; then
   # expecting this to error if not running.  if we use set -e that will kill the script
   if curl -q http://127.0.0.1:4985/_admin/ &> /dev/null; then
      SUCCESS=0
   else
      /setup/control/preinst "install"
      /setup/control/postinst "configure"
      SUCCESS=$?
   fi
else
   rm -rf /opt/couchbase-sync-gateway/
   # Update /etc/profile.d/couchbaseserver.sh
    echo "#!/usr/bin/env sh
export COUCHBASE_GATEWAY_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
   bash /setup/couchbase_installer.sh -ch "http://localhost:8091" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os UBUNTU -e GCP -c -d -g
   SUCCESS=$?

fi

if [[ -z "$CONFIG" ]]; then
cat << _EOF > /home/sync_gateway/sync_gateway.json
{
  "interface":"0.0.0.0:4984",
  "adminInterface":"0.0.0.0:4985",
  "metricsInterface":"0.0.0.0:4986",
  "logging": {
    "console": {
      "log_keys": ["*"]
    }
  },
  "databases": {
    "$BUCKET": {
      "server": "$CONNECTION_STRING",
      "username": "$USERNAME",
      "password": "$PASSWORD",
      "bucket": "$BUCKET",
      "users": {
        "GUEST": {
          "disabled": false,
          "admin_channels": ["*"]
        }
      },
      "allow_conflicts": false,
      "revs_limit": 20,
      "import_docs": true,
      "enable_shared_bucket_access":true,
      "num_index_replicas":0
    }
  }
} 
_EOF
else
    # get config from blob storage
    gsutil cp "$CONFIG" /home/sync_gateway/sync_gateway.json
    echo "Retrieving configuration from blob storage"
fi

service sync_gateway restart

if [[ "$SUCCESS" == 0 && -n "$CONFIG" ]]; then

        SUCCESS_PAYLOAD=""

       echo "Sending success notification for startup waiter on GCP"

        # Notify waiter
        wget -O - \
            --retry-connrefused \
            --waitretry=1 \
            --read-timeout=10 \
            --timeout=10 \
            -t 5 \
            --body-data="${SUCCESS_PAYLOAD}" \
            --header="Authorization: Bearer ${ACCESS_TOKEN}" \
            --header "Content-Type: application/json" \
            --header "X-GFE-SSL: yes" \
            --method=POST \
            "https://runtimeconfig.googleapis.com/v1beta1/projects/${PROJECT_ID}/configs/${CONFIG}/variables"
fi

# We should be running by here. if not, RESTART!
RUNNING=$(curl -s -o /dev/null -I -w "%{http_code}" http://localhost:4984)
if [[ "$RUNNING" != "200" ]]; then
    echo "Sync Gateway is not running.  We should restart."
    service sync_gateway stop &> /dev/null
    service sync_gateway start &> /dev/null
fi

