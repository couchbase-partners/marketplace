#!/usr/bin/env bash
set -x
echo 'Running startup script...'

yum install jq aws-cfn-bootstrap -q -y
#These values will be replaced with appropriate values during compilation into the Cloud Formation Template
#To run directly, simply set values prior to executing script.  Any variable with $__ prefix and __ suffix will
#get replaced during compliation

# shellcheck disable=SC2154
VERSION=$__SyncGatewayVersion__
# shellcheck disable=SC2154
stackName=$__AWSStackName__
resource="SyncGatewayAutoScalingGroup"
region=$(ec2-metadata -z | cut -d " " -f 2 | sed 's/.$//')
instanceId=$(ec2-metadata -i | cut -d " " -f 2)

USERNAME=$(aws ssm get-parameter --with-decryption --name  "/${stackName}/cb_username" --region "$region" | jq -r '.Parameter.Value')
PASSWORD=$(aws ssm get-parameter --with-decryption --name  "/${stackName}/cb_password" --region "$region" | jq -r '.Parameter.Value')



echo "Using the settings:"
echo "stackName '$stackName'"
echo "region '$region'"
echo "instanceID '$instanceId'"
aws ec2 create-tags \
  --region "${region}" \
  --resources "${instanceId}" \
  --tags Key=Name,Value="${stackName}-SyncGateway"

CLUSTER_HOST=$(curl -s  http://169.254.169.254/latest/meta-data/public-hostname)

# __SCRIPT_URL__ gets replaced during build
if [[ ! -e "couchbase_installer.sh" ]]; then
    curl -L --output "couchbase_installer.sh" "__SCRIPT_URL__"
fi

bash ./couchbase_installer.sh -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os AMAZON -e AWS -c -d -g
# calls back to AWS to signify that installation is complete and the stack can complete.
/opt/aws/bin/cfn-signal -e 0 --stack "$stackName" --resource "$resource" --region "$region"