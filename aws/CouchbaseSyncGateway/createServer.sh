#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

function __generate_random_string() {
    NEW_UUID=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 10 ; echo '')
    echo "${NEW_UUID}"
}

REGION="us-east-1"
INSTANCE_TYPE=m4.xlarge

while getopts r:t:i:u:p: flag
do
    case "${flag}" in
        r) REGION=${OPTARG};;
        t) TAG=${OPTARG};;
        i) INSTANCE_TYPE=${OPTARG};;
        u) USERNAME=${OPTARG};;
        p) PASSWORD=${OPTARG};;
        *) exit 1;;
    esac
done

USERNAME=${USERNAME:-"couchbase"}
PASSWORD=${PASSWORD:-"foo123!"}
REGION=${REGION:-"us-east-1"}
INSTANCE_TYPE=${INSTANCE_TYPE:-"m4.xlarge"}

BASE_AMI_ID=$(jq --arg region "$REGION" -r '.CouchbaseServer[$region].AMI' "$SCRIPT_DIR/../CouchbaseServer/mappings.json")

#Generate a SSH key for ssh into instance
KEY_NAME="ami-creation-$(__generate_random_string)"
mkdir -p "$HOME/.ssh" 2>&1
rm -rf "$HOME/.ssh/aws-keypair.pem" 2>&1
aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "$HOME/.ssh/aws-keypair.pem"
chmod 400 "$HOME/.ssh/aws-keypair.pem"

SECURITY_GROUP=aws-ami-creation

AWS_RESPONSE=$(aws ec2 run-instances \
    --image-id "$BASE_AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --security-groups "$SECURITY_GROUP" \
    --key-name "$KEY_NAME" \
    --region "$REGION" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=identifier,Value=$TAG}, {Key=couchbase.server.username,Value=$USERNAME},{Key=couchbase.server.password,Value=$PASSWORD},{Key=couchbase.server.make_cluster,Value=true},]" \
    --block-device-mappings "DeviceName=/dev/sdk,Ebs={DeleteOnTermination=true,VolumeSize=100,VolumeType=gp3}" \
    --output json)

INSTANCE_ID=$(echo "$AWS_RESPONSE" | jq -r '.Instances[] | .InstanceId')
PUBLIC_IP=$(aws ec2 describe-instances --instance-id "$INSTANCE_ID" | jq -r '.Reservations[] | .Instances[] | .NetworkInterfaces[] | .Association.PublicIp')
echo "$PUBLIC_IP"
instanceState=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --output json | jq -r '.Reservations[] | .Instances[] | .State.Name')

# wait until the instance state reaches running
until [[ "$instanceState" == "running" ]]; do
    sleep 5
    instanceState=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --output json | jq -r '.Reservations[] | .Instances[] | .State.Name')
done
# wait until the couchbase server is responsive
until curl -q "http://$PUBLIC_IP:8091" &> /dev/null; do
    sleep 1
done

curl -X POST -u "$USERNAME:$PASSWORD" "http://$PUBLIC_IP:8091/sampleBuckets/install" -d '["travel-sample"]'