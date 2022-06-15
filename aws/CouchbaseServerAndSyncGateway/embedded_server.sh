#!/usr/bin/env bash

set -x
echo "Beginning"
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

region=$(ec2-metadata -z | cut -d " " -f 2 | sed 's/.$//')
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
if [[ ! -e "couchbase_installer.sh" ]]; then
    curl -L --output "couchbase_installer.sh" "__SCRIPT_URL__"
fi

if bash ./couchbase_installer.sh -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os AMAZON -e AWS -s -c -d --format-disk /dev/sdk --alternate-address "$nodePublicDNS"; then
   # Calls back to AWS to signify that installation is complete
   /opt/aws/bin/cfn-signal -e 0 --stack "$stackName" --resource "$resource" --region "$region"
else
   /opt/aws/bin/cfn-signal -e 1 --stack "$stackName" --resource "$resource" --region "$region"
   exit 1
fi
