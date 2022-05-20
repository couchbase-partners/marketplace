#!/usr/bin/env bash

set -x
echo "Beginning"
# There is a race condition based on when the env vars are set by profile.d and when cloud-init executes
# this just removes that race condition
if [[ -r /etc/profile.d/couchbaseserver.sh ]]; then
   # Disabling lint for unreachable source file
   # shellcheck disable=SC1091
   source /etc/profile.d/couchbaseserver.sh
fi

# Retrieve metadata per AWS's documentation
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

region=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
instanceId=$(ec2-metadata -i | cut -d " " -f 2)

if curl http://127.0.0.1:8091/; then
   echo "Server already running. Exiting"
   exit 0
fi

function __get_tag_value() {
   __get_meta_data "tags/instance/$1"
}

function __get_meta_data() {
   curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/$1"
}

HASTAGS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" -o /dev/null -w "%{http_code}"  http://169.254.169.254/latest/meta-data/tags)
# we may not be able to retrieve tags due to IAM permissions.  If not we just want to start the instance and go away
if [[  "$HASTAGS" == "404" ]]; then 
      echo "Unable to retrieve tags, enable tags in metadata option."
      bash /setup/postinstall.sh 0
      bash /setup/posttransaction.sh
      exit 0
fi

VERSION=$(__get_tag_value "couchbase:server:version")
SECRET=$(__get_tag_value "couchbase:server:secret")
SERVICES=$(__get_tag_value "couchbase:server:services")
RALLY_PARAM=$(__get_tag_value "couchbase:server:rally_parameter")
RALLY_URL=$(__get_tag_value "couchbase:server:rally_url")
RALLY_AUTOSCALING_GROUP=$(__get_tag_value "aws:autoscaling:groupName")
STACK_NAME=$(__get_tag_value "aws:cloudformation:stack-name")
RESOURCE=$(__get_tag_value "aws:cloudformation:logical-id")
MAKE_CLUSTER=$(__get_tag_value "couchbase:server:make_cluster")
TAGGED_USERNAME=$(__get_tag_value "couchbase:server:username")
TAGGED_PASSWORD=$(__get_tag_value "couchbase:server:password")
DISK=$(__get_tag_value "couchbase:server:disk")

# If disk isn't passed and we have a /dev/sdk we'll use that as the default
if [[ -z "$DISK"  && -b "/dev/sdk" ]]; then
   DISK="/dev/sdk"
fi

# If no services, we should use some defaults
# TODO:  Add backup for > 7.0.0 versions
if [[ -z "$SERVICES" ]]; then
   SERVICES="data,query,index,analytics,eventing,fts"
   if [[ -n $VERSION ]] && [[ $VERSION == 7* ]]; then
      SERVICES="$SERVICES,backup"
   fi
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

# Rally DNS will default to self regardless.  We'll do --no-cluster if MAKE_CLUSTER != true
rallyPublicDNS=$(__get_meta_data "public-hostname") || nodePublicDNS=$(hostname)
# Rally DNS can be a few different things beyond the default
# 1)  It can be the RALLY_PARAM's value (If we have a rally param but no RALLY_URL)
if [[ -n "$RALLY_PARAM" ]] && [[ "$MAKE_CLUSTER" != "true" ]]; then
   rallyPublicDNS=$(aws ssm get-parameter --name "$RALLY_PARAM" --region "$region" | jq -r '.Parameter.Value')
# 2) It can be the rally url if they just tag with the url
elif [[ -n "$RALLY_URL" ]]; then
   rallyPublicDNS="$RALLY_URL"
# 3) It can be the first instance of the auto scaling group that this instance belongs too.
elif [[ -n "$RALLY_AUTOSCALING_GROUP" ]]; then
   rallyAutoscalingGroupInstanceIDs=$(aws autoscaling describe-auto-scaling-groups \
                                                --region "${region}" \
                                                   --query 'AutoScalingGroups[*].Instances[*].InstanceId' \
                                                   --auto-scaling-group-name "${RALLY_AUTOSCALING_GROUP}" \
                                                | jq -r '.[] | .[]')

   # shellcheck disable=SC2206
   IFS=$'\n' rallyAutoscalingGroupInstanceIDsArray=($rallyAutoscalingGroupInstanceIDs)
   rallyInstanceID=${rallyAutoscalingGroupInstanceIDsArray[0]}

   for i in "${rallyAutoscalingGroupInstanceIDsArray[@]}"; do
      tags=$(aws ec2 describe-tags --region "${region}"  --filter "Name=tag:Name,Values=*Rally" "Name=resource-id,Values=$i")
      tags=$(echo "$tags" | jq '.Tags')
      echo "Instance: ${i} Tags: ${tags}"
      if [ "$tags" != "[]" ]
      then
         rallyInstanceID=$i
      fi
   done
   rallyPublicDNS=$(aws ec2 describe-instances \
                              --region "${region}" \
                                    --query  'Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicDnsName' \
                                    --instance-ids "${rallyInstanceID}" \
                  --output text)
   if [[ -z "$rallyPublicDNS" || "$rallyPublicDNS" == "None" ]]; then
      rallyPublicDNS=$(aws ec2 describe-instances \
                              --region "${region}" \
                                    --query  'Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp' \
                                    --instance-ids "${rallyInstanceID}" \
                  --output text)
   fi
   if [[ -z "$rallyPublicDNS" || "$rallyPublicDNS" == "None" ]]; then
      rallyPublicDNS=$(aws ec2 describe-instances \
                              --region "${region}" \
                                    --query  'Reservations[0].Instances[0].NetworkInterfaces[0].PrivateDnsName' \
                                    --instance-ids "${rallyInstanceID}" \
                  --output text)
   fi
   if [[ -z "$rallyPublicDNS" || "$rallyPublicDNS" == "None" ]]; then
   rallyPublicDNS=$(aws ec2 describe-instances \
                              --region "${region}" \
                                    --query  'Reservations[0].Instances[0].NetworkInterfaces[0].PrivateIpAddress' \
                                    --instance-ids "${rallyInstanceID}" \
                  --output text)
   fi
fi

nodePublicDNS=$(__get_meta_data "public-hostname") || nodePublicDNS=$(hostname)
echo "Using the settings:"
echo "rallyPublicDNS $rallyPublicDNS"
echo "region $region"
echo "instanceID $instanceId"
echo "nodePublicDNS $nodePublicDNS"


if [[ -n "$RALLY_PARAM" ]] && [[ "$MAKE_CLUSTER" == "true" ]] && [[ "$rallyPublicDNS" == "$nodePublicDNS" ]]; then
   # here is a situation where we've established that we are the rally dns, so we should update the RALLY_PARAM with our dns
   aws ssm put-parameter --name "$RALLY_PARAM" --value "$rallyPublicDNS" --region "$region" --overwrite
fi
# Here we're going to tag a name onto this based on settings
# If we are the rally and we' have a stack let's let our name be thusly
if [[ "$rallyPublicDNS" == "$nodePublicDNS" ]] && [[ -n "$STACK_NAME" ]]; then
   NAME="${STACK_NAME}-couchbase-server-rally"
elif [[ "$rallyPublicDNS" == "$nodePublicDNS" ]] && [[ -n "$RALLY_AUTOSCALING_GROUP" ]]; then
   NAME="${RALLY_AUTOSCALING_GROUP}-couchbase-server-rally"
elif [[ "$rallyPublicDNS" == "$nodePublicDNS" ]] && [[ -z "$STACK_NAME" ]] && [[ -z "$RALLY_AUTOSCALING_GROUP" ]]; then
   NAME="couchbase-server-rally"
elif [[ "$rallyPublicDNS" != "$nodePublicDNS" ]] && [[ -n "$STACK_NAME" ]]; then
   NAME="${STACK_NAME}-couchbase-${SERVICES//,/$'-'}-server"
elif [[ "$rallyPublicDNS" != "$nodePublicDNS" ]] && [[ -n "$RALLY_AUTOSCALING_GROUP" ]]; then
   NAME="${RALLY_AUTOSCALING_GROUP}-couchbase-${SERVICES//,/$'-'}-server"  
else 
   NAME="couchbase-${SERVICES//,/$'-'}-server"
fi

TAGGED_NAME=$(__get_tag_value "Name")

# We should only name the instance if they haven't already
# no need to overwrite their name
if [[ -z "$TAGGED_NAME" ]]; then
   aws ec2 create-tags \
      --region "${region}" \
      --resources "${instanceId}" \
      --tags Key=Name,Value="$NAME"
fi

CLUSTER_HOST=$rallyPublicDNS
SUCCESS=1

if [[ -z "$VERSION" ]] || [[ "$COUCHBASE_SERVER_VERSION" == "$VERSION" ]]; then
   CLUSTER_MEMBERSHIP=$(curl -q -u "$CB_USERNAME:$CB_PASSWORD" http://127.0.0.1:8091/pools/default | jq -r '') || CLUSTER_MEMBERSHIP="unknown pool"
   if [[ "$CLUSTER_MEMBERSHIP" != "unknown pool" ]] && curl -q -u "$CB_USERNAME:$CB_PASSWORD" http://127.0.0.1:8091/pools/default; then
      SUCCESS=0
   else
      export CLI_INSTALL_LOCATION=${COUCHBASE_HOME:-/opt/couchbase/bin/}
      bash /setup/postinstall.sh 0
      bash /setup/posttransaction.sh
      if [[ "$MAKE_CLUSTER" == "true" ]] || [[ -n "$RALLY_PARAM" ]] || [[ -n "$RALLY_URL" ]]; then 
         bash /setup/couchbase_installer.sh -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$COUCHBASE_SERVER_VERSION" -os AMAZON -e AWS -s -c -d --cluster-only -sv "$SERVICES" --format-disk "$DISK" --alternate-address "$nodePublicDNS"
      fi
      SUCCESS=$?
   fi
else
   rpm -e "$(rpm -qa | grep couchbase)"
   rm -rf /opt/couchbase/
   # Update /etc/profile.d/couchbaseserver.sh
   echo "#!/usr/bin/env sh
export COUCHBASE_SERVER_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
if [[ "$MAKE_CLUSTER" == "true" ]] || [[ -n "$RALLY_PARAM" ]] || [[ -n "$RALLY_URL" ]]; then
      bash /setup/couchbase_installer.sh -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os AMAZON -e AWS -s -c -d -sv "$SERVICES" --format-disk "$DISK" --alternate-address "$nodePublicDNS"
   else
      bash /setup/couchbase_installer.sh -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os AMAZON -e AWS -s -c -d -sv "$SERVICES" --no-cluster --format-disk "$DISK" --alternate-address "$nodePublicDNS"
   fi
   SUCCESS=$?
fi

# Here we're assuming that if you have a autoscaling group and stack name, then there is a creation policy
if [[ -n "$RESOURCE" ]] && [[ -n "$STACK_NAME" ]]; then
   if [[ "$SUCCESS" == "0" ]]; then
      # Calls back to AWS to signify that installation is complete
      /opt/aws/bin/cfn-signal -e 0 --stack "$STACK_NAME" --resource "$RESOURCE" --region "$region"
   else
      /opt/aws/bin/cfn-signal -e 1 --stack "$STACK_NAME" --resource "$RESOURCE" --region "$region"
      exit 1
   fi
fi
