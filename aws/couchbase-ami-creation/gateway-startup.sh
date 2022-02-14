#!/usr/bin/env bash
set -ex
echo 'Running startup script...'
# There is a race condition based on when the env vars are set by profile.d and when cloud-init executes
# this just removes that race condition
if [[ -r /etc/profile.d/couchbaseserver.sh ]]; then
   # Disabling lint for unreachable source file
   # shellcheck disable=SC1091
   source /etc/profile.d/couchbaseserver.sh
fi


# Retrieve metadata per AWS's documentation
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
instanceId=$(ec2-metadata -i | cut -d " " -f 2)

if curl http://127.0.0.1:4984/; then
   echo "Server already running. Exiting"
   exit 0
fi

TAGS=$(aws ec2 describe-instances --instance-id "$instanceId" --query 'Reservations[*].Instances[*].Tags[*]' --output json  --region "$region" | jq -r 'flatten | .[]')

HASROLE=$(curl -s -o /dev/null -w "%{http_code}" http://169.254.169.254/latest/meta-data/iam)
# we may not be able to retrieve tags due to IAM permissions.  If not we just want to start the instance and go away
if [[ -z "$TAGS" ]] && [[ "$HASROLE" == "404" ]]; then 
      echo "Unable to retrieve tags, check IAM permissions, simply starting couchbase server service."
      bash /setup/postinstall.sh 0 
      bash /setup/posttransaction.sh
      service sync_gateway restart
      exit 0
else
   # Let's wait a sec and try again
   sleep 10
   TAGS=$(aws ec2 describe-instances --instance-id "$instanceId" --query 'Reservations[*].Instances[*].Tags[*]' --output json  --region "$region" | jq -r 'flatten | .[]')
fi

VERSION=$(jq -r 'select(.Key == "couchbase:gateway:version").Value' <<< "$TAGS")
SECRET=$(jq -r 'select(.Key == "couchbase:gateway:secret").Value' <<< "$TAGS")
CONNECTION_STRING=$(jq -r 'select(.Key == "couchbase:gateway:connectionstring").Value' <<< "$TAGS")
CONNECTION_PARAM=$(jq -r 'select(.Key == "couchbase:gateway:connection_param").Value' <<< "$TAGS")
CONFIG=$(jq -r 'select(.Key == "couchbase:gateway:config").Value' <<< "$TAGS")
BUCKET=$(jq -r 'select(.Key == "couchbase:gateway:bucket").Value' <<< "$TAGS")
STACK_NAME=$(jq -r 'select(.Key == "aws:cloudformation:stack-name").Value' <<< "$TAGS")
RESOURCE=$(jq -r 'select(.Key == "aws:cloudformation:logical-id").Value' <<< "$TAGS") 
TAGGED_USERNAME=$(jq -r 'select(.Key == "couchbase:gateway:username").Value' <<< "$TAGS")
TAGGED_PASSWORD=$(jq -r 'select(.Key == "couchbase:gateway:password").Value' <<< "$TAGS")
NAME=$(jq -r 'select(.Key == "Name").Value' <<< "$TAGS")


# if no version, use built in version
if [[ -z "$VERSION" ]]; then
    VERSION="$COUCHBASE_GATEWAY_VERSION"
fi

# Connection string should be param if passed
if [[ -n "$CONNECTION_PARAM" ]]; then
    CONNECTION_STRING=$(aws ssm get-parameter --name "$CONNECTION_PARAM" --region "$region" | jq -r '.Parameter.Value')
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
   SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "${SECRET}" --version-stage AWSCURRENT --region "$region" | jq -r .SecretString)
   USERNAME=$(echo "$SECRET_VALUE" | jq -r .username)
   PASSWORD=$(echo "$SECRET_VALUE" | jq -r .password)
elif [[ -n "$TAGGED_USERNAME" ]] && [[ -n "$TAGGED_PASSWORD" ]]; then
   USERNAME="$TAGGED_USERNAME"
   PASSWORD="$TAGGED_PASSWORD"
else
   USERNAME="NO-USER"
   PASSWORD="NO-PASSWORD"
fi

echo "Using the settings:"
echo "stackName '$STACK_NAME'"
echo "region '$region'"
echo "instanceID '$instanceId'"

if [[ -z "$NAME" ]]; then 
    if [[ -n "$STACK_NAME" ]]; then
        NAME="${STACK_NAME}-couchbase-sync-gateway"
    else
        NAME="couchbase-sync-gateway"
    fi
    aws ec2 create-tags \
    --region "${region}" \
    --resources "${instanceId}" \
    --tags Key=Name,Value="$NAME"
fi


# Setup Config
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
  mkdir -p /opt/sync_gateway/etc/
  aws s3 cp "$CONFIG" "/opt/sync_gateway/etc/sync_gateway.json"
fi

SUCCESS=1

if [[ "$COUCHBASE_GATEWAY_VERSION" == "$VERSION" ]]; then
   # expecting this to error if not running.  if we use set -e that will kill the script
   if curl -q http://127.0.0.1:4985/_admin/ &> /dev/null; then
      SUCCESS=0
   else
      bash /setup/postinstall.sh 0 &> /dev/null
      bash /setup/posttransaction.sh &> /dev/null
      SUCCESS=$?
   fi
else
   # Remove existing
   rpm -e "$(rpm -qa | grep couchbase)"
   rm -rf /opt/couchbase-sync-gateway/
   # Update /etc/profile.d/couchbaseserver.sh
    echo "#!/usr/bin/env sh
export COUCHBASE_GATEWAY_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
   bash /setup/couchbase_installer.sh -ch "http://localhost:8091" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os AMAZON -e AWS -c -d -g
   SUCCESS=$?
 
fi
sleep 10
# We should be running by here. if not, RESTART!
RUNNING=$(curl -s -o /dev/null -I -w "%{http_code}" http://localhost:4984)
if [[ "$RUNNING" != "200" ]]; then
    echo "Sync Gateway is not running.  We should restart."
    service sync_gateway stop &> /dev/null
    service sync_gateway start &> /dev/null
    sleep 10
fi

if [[ "$SUCCESS" == "0" && "$VERSION" =~ ^3 ]]; then
  # here we need to hit the API and configure the database for sync gateway 3.0+
  CONFIGURED=$(curl -L -s -o /dev/null -I -w "%{http_code}"  http://127.0.0.1:4985/$BUCKET/_config -X GET --user $USERNAME:$PASSWORD)
  if [[ "$CONFIGURED" != "200" ]]; then
    curl -X PUT "http://127.0.0.1:4985/$BUCKET/" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"bucket\": \"$BUCKET\",\"name\": \"$BUCKET\", \"num_index_replicas\":0}" \
        --retry 5 \
        --retry-all-errors \
        --fail \
        --user $USERNAME:$PASSWORD
  fi
fi



if [[ -n "$RESOURCE" ]] && [[ -n "$STACK_NAME" ]]; then
    echo "We need to notify $RESOURCE that $STACK_NAME is complete"
    if [[ "$SUCCESS" == "0" ]]; then
        # Calls back to AWS to signify that installation is complete
        /opt/aws/bin/cfn-signal -e 0 --stack "$STACK_NAME" --resource "$RESOURCE" --region "$region"
    else
        /opt/aws/bin/cfn-signal -e 1 --stack "$STACK_NAME" --resource "$RESOURCE" --region "$region"
        exit 1
    fi
fi

