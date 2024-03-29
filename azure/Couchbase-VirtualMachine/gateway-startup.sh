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

echo "Retrieving Metadata"
METADATA=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01")

function __get_tag() {
    echo "$METADATA" | jq -r --arg param "$1" '.compute.tagsList[] | select(.name == $param) | .value'
}

RETRY=0
until curl http://127.0.0.1:4984/
do
  RETRY=$((RETRY+1))
  if [[ "$RETRY" == "25" ]]; then
      break
  fi
  sleep 1
done

if [[ "$RETRY" != "25" ]]; then
    echo "Gateway Service already running, exiting"
    sleep 1
fi

VAULT=$(__get_tag "key-vault")
VERSION=$(__get_tag "couchbase-gateway-version")
SECRET=$(__get_tag "couchbase-gateway-secret")
CONNECTION_STRING=$(__get_tag "couchbase-gateway-connection-string")
CONNECTION_PARAM=$(__get_tag "couchbase-gateway-connection-parameter")
CONFIG=$(__get_tag "couchbase-gateway-config")
BUCKET=$(__get_tag "couchbase-gateway-bucket")
TAGGED_USERNAME=$(__get_tag "couchbase-gateway-username")
TAGGED_PASSWORD=$(__get_tag "couchbase-gateway-password")



# if no version, use built in version
if [[ -z "$VERSION" ]]; then
    VERSION="$COUCHBASE_GATEWAY_VERSION"
fi

# Connection string should be param if passed
if [[ -n "$CONNECTION_PARAM" ]]; then
    RETRY=0
    until az login --identity --allow-no-subscriptions
    do
        RETRY=$((RETRY+1))
        if [[ "$RETRY" == "25" ]]; then
            echo "Attempted 25 times.  Exiting"
            exit 1
        fi
        sleep 1
        echo "Failed Login.  Trying again."
    done
    CONNECTION_STRING=$(az keyvault secret show --name "$CONNECTION_PARAM" --vault "$VAULT" | jq -r '.value')
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
   az login --identity
   SECRET_VALUE=$(az keyvault secret show --name "$SECRET" --vault "$VAULT" | jq -r '.value | fromjson')
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
   bash /setup/couchbase_installer.sh -ch "http://localhost:8091" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os UBUNTU -e AZURE -c -d -g
   SUCCESS=$?

fi

if [[ -z "$CONFIG" ]]; then
   if [[ !  "$VERSION" =~ ^3 ]]; then
    mkdir -p /opt/sync_gateway/etc/
    # Pre Version 3 config
    cat << _EOF > /opt/sync_gateway/etc/sync_gateway.json
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
  # Post version 3 config
    mkdir -p /home/sync_gateway/

    cat << _EOF > /home/sync_gateway/sync_gateway.json
    {
      "bootstrap": {
        "server": "$CONNECTION_STRING",
        "username":"$USERNAME",
        "password":"$PASSWORD",
        "use_tls_server":false
      },
      "api":{
        "admin_interface":"0.0.0.0:4985",
        "https":{},
        "cors":{}
      },
      "logging":{
        "console":{
          "rotation":{}
        },
        "error":{
          "rotation":{}
        },
        "warn":{
          "rotation":{}
        },
        "info":{
          "rotation":{}
        },
        "debug":{
          "rotation":{}
        },
        "trace":{
          "rotation":{}
        },
        "stats":{
          "rotation":{}
        }
      },
      "auth":{},
      "replicator":{},
      "unsupported":{
        "http2":{}
      }
    }
_EOF
  fi
else
    # get config from blob storage
    gsutil cp "$CONFIG" /home/sync_gateway/sync_gateway.json
    echo "Retrieving configuration from blob storage"
fi

service sync_gateway restart
sleep 1
# We should be running by here. if not, RESTART!
RUNNING=$(curl -s -o /dev/null -I -w "%{http_code}" http://localhost:4984)
if [[ "$RUNNING" != "200" ]]; then
    echo "Sync Gateway is not running.  We should restart."
    service sync_gateway stop &> /dev/null
    service sync_gateway start &> /dev/null
    sleep 10
fi

RUNNING=$(curl -s -o /dev/null -I -w "%{http_code}" http://localhost:4984)
if [[ "$RUNNING" == "200" && "$VERSION" =~ ^3 ]]; then
  # here we need to hit the API and configure the database for sync gateway 3.0+
  CONFIGURED=$(curl -L -s -o /dev/null -I -w "%{http_code}"  http://127.0.0.1:4985/$BUCKET/_config -X GET --user $USERNAME:$PASSWORD)
  if [[ "$CONFIGURED" != "200" ]]; then
    RESPONSE=$(curl -X PUT "http://127.0.0.1:4985/$BUCKET/" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"bucket\": \"$BUCKET\",\"name\": \"$BUCKET\", \"num_index_replicas\":0}" \
        --user $USERNAME:$PASSWORD -L -s -w '%{http_code}')
    COUNT=0
    while [[ "$RESPONSE" != "412" && "$COUNT" -lt "15" ]];
    do
      sleep 1
      COUNT=$((COUNT + 1))
      RESPONSE=$(curl -X PUT "http://127.0.0.1:4985/$BUCKET/" \
          -H "accept: application/json" \
          -H "Content-Type: application/json" \
          -d "{\"bucket\": \"$BUCKET\",\"name\": \"$BUCKET\", \"num_index_replicas\":0}" \
          --user $USERNAME:$PASSWORD -L -s -w '%{http_code}')
    done
  fi
elif [[ "$RUNNING" != "200" ]]; then
  echo "Sync Gateway is still not running.  Cannot complete configuration."
fi