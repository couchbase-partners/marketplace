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

yum install jq aws-cfn-bootstrap -y -q
#These values will be replaced with appropriate values during compilation into the Cloud Formation Template
#To run directly, simply set values prior to executing script.  Any variable with $__ prefix and __ suffix will
#get replaced during compliation

# shellcheck disable=SC2154
stackName=$__AWSStackName__
# shellcheck disable=SC2154
VERSION=$__ServerVersion__
# shellcheck disable=SC2154
SECRET=$__CouchbaseSecret__
# shellcheck disable=SC2154
SIGNAL_URL="$__RallyUrlWaitConditionHandler__"
echo "$SIGNAL_URL"
region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
instanceId=$(ec2-metadata -i | cut -d " " -f 2)
resource="ServerAutoScalingGroup"

SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "${SECRET}" --version-stage AWSCURRENT --region "$region" | jq -r .SecretString)
USERNAME=$(echo "$SECRET_VALUE" | jq -r .username)
PASSWORD=$(echo "$SECRET_VALUE" | jq -r .password)


rallyAutoscalingGroup=$(aws ec2 describe-instances \
                                  --region "${region}" \
                                   --instance-ids "${instanceId}" \
                                | jq -r '.Reservations[0]|.Instances[0]|.Tags[] | select(.Key == "aws:autoscaling:groupName") | .Value')

rallyAutoscalingGroupInstanceIDs=$(aws autoscaling describe-auto-scaling-groups \
                                                    --region "${region}" \
                                                       --query 'AutoScalingGroups[*].Instances[*].InstanceId' \
                                                       --auto-scaling-group-name "${rallyAutoscalingGroup}" \
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
nodePublicDNS=$(curl -sf http://169.254.169.254/latest/meta-data/public-hostname) || nodePublicDNS=$(hostname)
echo "Using the settings:"
echo "rallyPublicDNS $rallyPublicDNS"
echo "region $region"
echo "instanceID $instanceId"
echo "nodePublicDNS $nodePublicDNS"

if [[ "${rallyPublicDNS}" == "${nodePublicDNS}" ]];
then
    curl -X PUT -H 'Content-Type:' --data-binary "{ \"Status\":\"SUCCESS\", \"Reason\":\"Complete\", \"UniqueId\":\"signal\", \"Data\":\"|$rallyPublicDNS|\"}" "$SIGNAL_URL"
    aws ec2 create-tags \
        --region "${region}" \
        --resources "${instanceId}" \
        --tags Key=Name,Value="${stackName}-ServerRally"
else
    aws ec2 create-tags \
        --region "${region}" \
        --resources "${instanceId}" \
        --tags Key=Name,Value="${stackName}-Server"
fi

CLUSTER_HOST=$rallyPublicDNS
# __SCRIPT_URL__ gets replaced during build
if [[ ! -e "/setup/couchbase_installer.sh" ]]; then
    curl -L --output "/setup/couchbase_installer.sh" "__SCRIPT_URL__"
fi

SUCCESS=1

if [[ "$COUCHBASE_SERVER_VERSION" == "$VERSION" ]]; then
   CLUSTER_MEMBERSHIP=$(curl -q -u "$CB_USERNAME:$CB_PASSWORD" http://127.0.0.1:8091/pools/default | jq -r '') || CLUSTER_MEMBERSHIP="unknown pool"
   if [[ "$CLUSTER_MEMBERSHIP" != "unknown pool" ]] && curl -q -u "$CB_USERNAME:$CB_PASSWORD" http://127.0.0.1:8091/pools/default; then
      SUCCESS=0
   else
      export CLI_INSTALL_LOCATION=${COUCHBASE_HOME:-/opt/couchbase/bin/}
      bash /setup/postinstall.sh 0
      bash /setup/posttransaction.sh 
      bash /setup/couchbase_installer.sh -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os AMAZON -e AWS -s -c -d --cluster-only
      SUCCESS=$?
   fi
else
   # Remove existing
   rm -rf /usr/lib/systemd/system/couchbase-server.service
   rm -rf /opt/couchbase/
   rpm -e "$(rpm -qa | grep couchbase)"
   # Update /etc/profile.d/couchbaseserver.sh
   echo "#!/usr/bin/env sh
export COUCHBASE_GATEWAY_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
   bash /setup/couchbase_installer.sh -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os AMAZON -e AWS -s -c -d
   SUCCESS=$?
fi

if [[ "$SUCCESS" == "0" ]]; then
   # Calls back to AWS to signify that installation is complete
   /opt/aws/bin/cfn-signal -e 0 --stack "$stackName" --resource "$resource" --region "$region"
else
   /opt/aws/bin/cfn-signal -e 1 --stack "$stackName" --resource "$resource" --region "$region"
   exit 1
fi
