#!/usr/bin/env bash

set -eu

SCRIPT_SOURCE=${BASH_SOURCE[0]/%deploy.sh/}
bash "${SCRIPT_SOURCE}makeArchives.sh"
STACK_NAME=$1
PRICING_TYPE=$2 #byol or hourlypricing
TEMPLATE_BODY="file://${SCRIPT_SOURCE}../../build/aws/CouchbaseServerAndSyncGateway/aws-cbs-$PRICING_TYPE.template"
echo "$TEMPLATE_BODY"
#TEMPLATE_BODY="file://couchbase-$2.template"
REGION=$(aws configure get region)
echo "$REGION"
if [ -z "$REGION" ]; then
    REGION="us-east-1"
fi
Username="couchbase"
Password="foo123!"
KeyName="couchbase-${REGION}"
#KeyName="ja-test-kp"
SSHCIDR="0.0.0.0/0"
ServerInstanceCount=$3
ServerVersion=$4
SyncGatewayInstanceCount=$5
SyncGatewayVersion=$6
VpcName=$(aws ec2 describe-vpcs --filter "Name=isDefault,Values=true" | jq -r '.Vpcs[].VpcId')
#VpcName=vpc-0c1cd329084365f10
SubnetId=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${VpcName}" --max-items 1 --region "$REGION" | jq -r '.Subnets[].SubnetId')
#SubnetId=subnet-08476a90d895839b4


aws cloudformation create-stack \
--disable-rollback \
--capabilities CAPABILITY_IAM \
--template-body "${TEMPLATE_BODY}" \
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
while [[ $Output != '"CREATE_COMPLETE"' && $Output != '"ROLLBACK_COMPLETE"' && $Counter -le 75 ]]
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

if [[ $Output == '"ROLLBACK_COMPLETE"' || $Counter -ge 75 ]]; then
    printf "Failed!\n"
    exit 1
fi
