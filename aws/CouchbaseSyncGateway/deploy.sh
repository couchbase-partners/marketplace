#!/usr/bin/env bash

set -eu

function __generate_random_string() {
    NEW_UUID=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 10 ; echo '')
    echo "${NEW_UUID}"
}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

STACK_NAME_DEFAULT="cb_test_stack_$(__generate_random_string)"
SYNC_GATEWAY_INSTANCE_COUNT_DEFAULT=$(jq '.Parameters.SyncGatewayInstanceCount.Default' "${SCRIPT_DIR}/couchbase-amzn-lnx2.template" -r)
SYNC_GATEWAY_VERSION_DEFAULT=$(jq '.Parameters.SyncGatewayVersion.Default' "${SCRIPT_DIR}/couchbase-amzn-lnx2.template" -r)
DEFAULT_REGION=$(aws configure get region)
KEY_NAME_DEFAULT="couchbase-${DEFAULT_REGION}"

while getopts n:c:v:u:b:d:k:r:p:l: flag
do
    case "${flag}" in
        n) STACK_NAME=${OPTARG};;
        c) SYNC_GATEWAY_INSTANCE_COUNT=${OPTARG};;
        v) SYNC_GATEWAY_VERSION=${OPTARG};;
        l) COUCHBASE_CLUSTER_URL=${OPTARG};;
        b) BUCKET_NAME=${OPTARG};;
        k) KEY_NAME=${OPTARG};;
        r) REGION=${OPTARG};;
        p) PASSWORD=${OPTARG};;
        u) USERNAME=${OPTARG};;
        *) exit 1;;
    esac
done

STACK_NAME=${STACK_NAME:-$STACK_NAME_DEFAULT}
SYNC_GATEWAY_INSTANCE_COUNT=${SYNC_GATEWAY_INSTANCE_COUNT:-$SYNC_GATEWAY_INSTANCE_COUNT_DEFAULT}
SYNC_GATEWAY_VERSION=${SYNC_GATEWAY_VERSION:-$SYNC_GATEWAY_VERSION_DEFAULT}
REGION=${REGION:-$DEFAULT_REGION}
KEY_NAME=${KEY_NAME:-$KEY_NAME_DEFAULT}
USERNAME=${USERNAME:-"couchbase"}
PASSWORD=${PASSWORD:-"foo123!"}

echo "Before Make Archives : $SCRIPT_DIR"
${SCRIPT_DIR}/makeArchives.sh -m "${SCRIPT_DIR}/mappings.json" \
                                 -o "${SCRIPT_DIR}/../../build/aws/CouchbaseSyncGateway/" \
                                 -n "aws-cb-syncgateway.template" \
                                 -i "${SCRIPT_DIR}/couchbase-amzn-lnx2.template" 
TEMPLATE_BODY="file://${SCRIPT_DIR}/../../build/aws/CouchbaseSyncGateway/aws-cb-syncgateway.template"
echo "$TEMPLATE_BODY"
#TEMPLATE_BODY="file://couchbase-$2.template"
echo "$REGION"

SSHCIDR="0.0.0.0/0"

echo "Instance Count: $SYNC_GATEWAY_INSTANCE_COUNT"
echo "Default: $SYNC_GATEWAY_INSTANCE_COUNT_DEFAULT"

echo "GatewayVersion: $SYNC_GATEWAY_VERSION"
echo "Default: $SYNC_GATEWAY_VERSION_DEFAULT"

VPC_NAME=$(aws ec2 describe-vpcs --filter "Name=isDefault,Values=true" --region "$REGION" | jq -r '.Vpcs[].VpcId')
#VPC_NAME=vpc-03c8fd1b201ba33c3
SUBNET_ID=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${VPC_NAME}" --max-items 2 --region "$REGION" | jq -r '.Subnets[].SubnetId' | paste -s -d ',' - | sed 's~,~\\,~g' )
#SUBNET_ID="subnet-01ae02bd1e1a35fef\,subnet-04d9e6de3de2f58c5"
echo "Subnets: $SUBNET_ID"
aws cloudformation create-stack \
--capabilities CAPABILITY_IAM \
--disable-rollback \
--template-body "${TEMPLATE_BODY}" \
--stack-name "${STACK_NAME}" \
--region "${REGION}" \
--parameters \
ParameterKey=Username,ParameterValue="${USERNAME}" \
ParameterKey=Password,ParameterValue="${PASSWORD}" \
ParameterKey=KeyName,ParameterValue="${KEY_NAME}" \
ParameterKey=SSHCIDR,ParameterValue="${SSHCIDR}" \
ParameterKey=SyncGatewayInstanceCount,ParameterValue="${SYNC_GATEWAY_INSTANCE_COUNT}" \
ParameterKey=SyncGatewayVersion,ParameterValue="${SYNC_GATEWAY_VERSION}" \
ParameterKey=VpcName,ParameterValue="${VPC_NAME}" \
ParameterKey=Subnets,ParameterValue="${SUBNET_ID}" \
ParameterKey=CouchbaseClusterUrl,ParameterValue="$COUCHBASE_CLUSTER_URL" \
ParameterKey=Bucket,ParameterValue="$BUCKET_NAME"

OUTPUT=$(aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --region "$REGION" | jq '.StackEvents[] | select(.ResourceType == "AWS::CloudFormation::Stack") | . | select(.ResourceStatus == "CREATE_COMPLETE"  or .ResourceStatus == "ROLLBACK_COMPLETE") | .ResourceStatus ')
COUNTER=0

printf "Waiting on Stack Creation to Complete ..."
while [[ $OUTPUT != '"CREATE_COMPLETE"' && $OUTPUT != '"ROLLBACK_COMPLETE"' && $COUNTER -le 50 ]]
do
    printf "."
    OUTPUT=$(aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --region "$REGION" | jq '.StackEvents[] | select(.ResourceType == "AWS::CloudFormation::Stack") | . | select(.ResourceStatus == "CREATE_COMPLETE"  or .ResourceStatus == "ROLLBACK_COMPLETE") | .ResourceStatus ')
    (( COUNTER += 1 ))
    sleep 10
done

if [[ $OUTPUT == '"CREATE_COMPLETE"' ]]; then
    printf "Complete!\n"
    exit 0
fi

if [[ $OUTPUT == '"ROLLBACK_COMPLETE"' || $COUNTER -ge 50 ]]; then
    printf "Failed!\n"
    exit 1
fi
