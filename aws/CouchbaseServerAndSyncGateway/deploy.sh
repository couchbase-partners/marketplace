#!/usr/bin/env bash

set -eu

function __generate_random_string() {
    NEW_UUID=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 10 ; echo '')
    echo "${NEW_UUID}"
}

SCRIPT_SOURCE=${BASH_SOURCE[0]/%deploy.sh/}
bash "${SCRIPT_SOURCE}makeArchives.sh"
STACK_NAME=$1
PRICING_TYPE=$2 #byol or hourlypricing
REGION=$(aws configure get region)
echo "$REGION"
if [ -z "$REGION" ]; then
    REGION="us-east-1"
fi
Username="couchbase"
Password="foobarbaz123!"
#KeyName="couchbase-${REGION}"
KeyName="ja-test-kp"
SSHCIDR="0.0.0.0/0"
ServerInstanceCount=$3
ServerVersion=$4
SyncGatewayInstanceCount=$5
SyncGatewayVersion=$6
VpcName=$(aws ec2 describe-vpcs --filter "Name=isDefault,Values=true" | jq -r '.Vpcs[].VpcId')
#VpcName=vpc-0c1cd329084365f10
SubnetId=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${VpcName}" --max-items 1 --region "$REGION" | jq -r '.Subnets[].SubnetId')
#SubnetId=subnet-08476a90d895839b4

TEMPLATE_BODY_FILE="${SCRIPT_SOURCE}/../../build/aws/CouchbaseServerAndSyncGateway/aws-cbs-$PRICING_TYPE.template"
echo "$TEMPLATE_BODY_FILE"

BUCKET="mp-test-templates$(__generate_random_string)"
aws s3api create-bucket --acl private --bucket "$BUCKET" --object-ownership ObjectWriter --region "$REGION"
aws s3api delete-public-access-block --bucket "$BUCKET" --region "$REGION"
aws s3api put-bucket-acl --acl private --bucket "$BUCKET" --region "$REGION"
KEY="aws-cb-server$(__generate_random_string).template"
aws s3api put-object --bucket "$BUCKET" --key "$KEY" --body "$TEMPLATE_BODY_FILE"

aws cloudformation create-stack \
--disable-rollback \
--capabilities CAPABILITY_IAM \
--template-url "https://${BUCKET}.s3.amazonaws.com/${KEY}" \
--stack-name "${STACK_NAME}" \
--region "${REGION}" \
--parameters \
ParameterKey=Username,ParameterValue=${Username} \
ParameterKey=Password,ParameterValue=${Password} \
ParameterKey=KeyName,ParameterValue="${KeyName}" \
ParameterKey=SSHCIDR,ParameterValue=${SSHCIDR} \
ParameterKey=ServerInstanceCount,ParameterValue="${ServerInstanceCount}" \
ParameterKey=ServerVersion,ParameterValue="${ServerVersion}" \
ParameterKey=SyncGatewayInstanceCount,ParameterValue="${SyncGatewayInstanceCount}" \
ParameterKey=SyncGatewayVersion,ParameterValue="${SyncGatewayVersion}" \
ParameterKey=VpcName,ParameterValue="${VpcName}" \
ParameterKey=SubnetList,ParameterValue="${SubnetId}"

Output=$(aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" | jq '.StackEvents[] | select(.ResourceType == "AWS::CloudFormation::Stack") | . | select(.ResourceStatus == "CREATE_COMPLETE"  or .ResourceStatus == "ROLLBACK_COMPLETE") | .ResourceStatus ')
Counter=0

printf "Waiting on Stack Creation to Complete ..."
while [[ $Output != '"CREATE_COMPLETE"' && $Output != '"ROLLBACK_COMPLETE"' && $Counter -le 100 ]]
do
    printf "."
    Output=$(aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" | jq '.StackEvents[] | select(.ResourceType == "AWS::CloudFormation::Stack") | . | select(.ResourceStatus == "CREATE_COMPLETE"  or .ResourceStatus == "ROLLBACK_COMPLETE") | .ResourceStatus ')
    (( Counter += 1 ))
    sleep 10
done

if [[ $Output == '"CREATE_COMPLETE"' ]]; then
    printf "Complete!\n"
    exit 0
fi

if [[ $Output == '"ROLLBACK_COMPLETE"' || $Counter -ge 100 ]]; then
    printf "Failed!\n"
    exit 1
fi
