#!/bin/bash

set -eu 

###############################################################################
# Dependencies:                                                               #
# gcloud                                                                      #
# tr                                                                          #
###############################################################################
#  Builds a blank AMI for usage in marketplace.  Base image is based off a    #
#  m4.xlarge AWS EC2 instance                                                 #
#                                                                             #
# NOTE:  This script requires an AWS Security Group created on the default    #
# VPC.  It must be named 'aws-ami-creation' and allow ingress and egress of   #
# http, https and ssh traffic                                                 #
###############################################################################
#  Parameters                                                                 #
#  -r : region                                                                #
#     usage:  -n us-east-1                                                    #
#     purpose:  The region you want the base instance to be created in        #
#  -n : AMI Name                                                              #
#     usage: -n ja-test-ami                                                   #
#     purpose: specifies the name of the AMI to create                        #
#  -v : Couchbase Version                                                     #
#     usage: -v 7.0.3                                                         #
#     purpose: specifies the version of couchbase product to use              #
#  -g : Gateway                                                               #
#     usage: -g                                                               #
#     purpose: specifies if the AMI is for server or gateway                  #
#  -p : package                                                               #
#     usage: -p couchbase-server-enterprise-7.1.0-2534-amzn2.aarch64.rpm      #
#     purpose: specifies rpm to use to install couchbase                      #
#  -a : ARM Build                                                             #
#     usage: -a                                                               #
#     purpose: specifies the ami to be an ARM AMI                             #
###############################################################################

function __generate_random_string() {
    NEW_UUID=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 10 ; echo '')
    echo "${NEW_UUID}"
}

#Constants
INSTANCE_TYPE=m4.xlarge
SECURITY_GROUP=aws-ami-creation
VERSION="7.2.4"
BASE_AMI_NAME=/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2
GATEWAY=0
PACKAGE=""
ARM=0

while getopts agr:n:v:p: flag
do
    case "${flag}" in
        r) REGION=${OPTARG};;
        n) AMI_NAME=${OPTARG};;
        v) VERSION=${OPTARG};;
        g) GATEWAY=1;;
        p) PACKAGE=${OPTARG};;
        a) ARM=1;;
        *) exit 1;;
    esac
done

# Check if we're using an ARM build.  This changes the INSTANCE_TYPE, The BASE AMI, and the structure of the installer name
if [[ "$ARM"  == "1" ]]; then
    INSTANCE_TYPE=m6g.xlarge
    BASE_AMI_NAME=/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-arm64-gp2
fi

# Create Output Folder
SCRIPT_SOURCE=${BASH_SOURCE[0]/%create.sh/}
SCRIPT_URL=$(cat "${SCRIPT_SOURCE}/../../script_url.txt")

mkdir -p "$SCRIPT_SOURCE/../../build/aws/couchbase-ami-creation/"

#Get AMI from AWS for the approved instance type
BASE_AMI_ID=$(aws ssm get-parameters --names "$BASE_AMI_NAME" --region "$REGION" | jq -r '.Parameters[] | .Value')
echo "Base AMI:  $BASE_AMI_ID"

#Generate a SSH key for ssh into instance
KEY_NAME="ami-creation-$(__generate_random_string)"
echo "Key Name to be created: $KEY_NAME"
mkdir -p "$HOME/.ssh" 2>&1
rm -rf "$HOME/.ssh/aws-keypair.pem" 2>&1
aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --region "$REGION" --output text > "$HOME/.ssh/aws-keypair.pem"
chmod 400 "$HOME/.ssh/aws-keypair.pem"
echo "$KEY_NAME Created."

# Create an instance to base our image off of.
echo "Running Instance."
AWS_RESPONSE=$(aws ec2 run-instances \
    --image-id "$BASE_AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --security-groups "$SECURITY_GROUP" \
    --key-name "$KEY_NAME" \
    --region "$REGION" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${KEY_NAME}}]" \
    --output json)

INSTANCE_ID=$(echo "$AWS_RESPONSE" | jq -r '.Instances[] | .InstanceId')
echo "Instance Id: $INSTANCE_ID"
PUBLIC_IP=$(aws ec2 describe-instances --instance-id "$INSTANCE_ID" --region "$REGION" | jq -r '.Reservations[] | .Instances[] | .NetworkInterfaces[] | .Association.PublicIp')

until [[ -n "$PUBLIC_IP" ]]; do
    PUBLIC_IP=$(aws ec2 describe-instances --instance-id "$INSTANCE_ID" --region "$REGION" | jq -r '.Reservations[] | .Instances[] | .NetworkInterfaces[] | .Association.PublicIp')
done

echo "Instance Public IP: $PUBLIC_IP"

# If we decide to do more than just an empty OS. We need to do it before we run this command, as you won't be able to log into the VM once we're done
# This ssh's into the instance updates the packages and removes ec2-user and root ssh details
echo "Waiting on instance to intialize"
instanceState=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --output json | jq -r '.Reservations[] | .Instances[] | .State.Name')

until [[ "$instanceState" == "running" ]]; do
    sleep 5
    instanceState=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --output json | jq -r '.Reservations[] | .Instances[] | .State.Name')
done
sleep 60 #We have to wait until SSH starts up.
echo "Updating packages on instance"
scp -i "$HOME/.ssh/aws-keypair.pem" -o StrictHostKeyChecking=no "${SCRIPT_SOURCE}/rpm_exploder.sh" "ec2-user@$PUBLIC_IP:/home/ec2-user/rpm_exploder.sh"

if [[ "$GATEWAY" == "1" ]]; then
    scp -i "$HOME/.ssh/aws-keypair.pem" -o StrictHostKeyChecking=no "${SCRIPT_SOURCE}/gateway-startup.sh" "ec2-user@$PUBLIC_IP:/home/ec2-user/startup.sh"
else
    scp -i "$HOME/.ssh/aws-keypair.pem" -o StrictHostKeyChecking=no "${SCRIPT_SOURCE}/server-startup.sh" "ec2-user@$PUBLIC_IP:/home/ec2-user/startup.sh"
fi

if [[ -n "$PACKAGE" ]]; then
    FILE=$(basename "$PACKAGE")
    scp -i "$HOME/.ssh/aws-keypair.pem" -o StrictHostKeyChecking=no "$PACKAGE" "ec2-user@$PUBLIC_IP:/home/ec2-user/$FILE"
fi

ssh -i "$HOME/.ssh/aws-keypair.pem" -o StrictHostKeyChecking=no "ec2-user@$PUBLIC_IP" "sudo yum update -y && sudo /usr/bin/bash ~/rpm_exploder.sh ${VERSION} ${GATEWAY} ${SCRIPT_URL} && echo 'Removing Exploder' && rm -rf ~/rpm_exploder.sh && echo 'Removing Ec2-User Authorized Keys' && sudo rm -rf /home/ec2-user/.ssh/ && echo 'Removing root Authorized Keys' && sudo rm -rf /root/.ssh/ && exit"

#Create AMI
SUFFIX="-x86_64"
if [[ "$ARM" == "1" ]]; then
    SUFFIX="-aarch64"
fi
AMI_NAME="${AMI_NAME}${SUFFIX}"
echo "Creating AMI:  $AMI_NAME"
todaysDate=$(date '+%Y-%m-%d %T')
DESCRIPTION="Auto-generated AMI for Couchbase Server v$VERSION on $todaysDate"
if [[ "$GATEWAY" == "1" ]]; then
    DESCRIPTION="Auto-generated AMI for Couchbase Sync Gateway v$VERSION on $todaysDate"
fi
imageResponse=$(aws ec2 create-image \
  --instance-id "$INSTANCE_ID" \
  --name "$AMI_NAME" \
  --description "$DESCRIPTION" \
  --region "$REGION" \
  --output json)

AMI_ID=$(echo "$imageResponse" | jq -r '.ImageId')

#AMI is in pending.. so we cannot clean up until it is "available", then we can terminate the instance
STATUS=$(aws ec2 describe-images --image-id "$AMI_ID" --region "$REGION" | jq -r '.Images[] | .State')
echo -n "$AMI_ID created, waiting on available..."
until [[ "$STATUS" == "available" ]]; do
    sleep 10
    STATUS=$(aws ec2 describe-images --image-id "$AMI_ID" --region "$REGION" | jq -r '.Images[] | .State')
    echo -n "."
done
echo "Available!"

#Write out to the build folder the AMI details
jq -n --arg id "$AMI_ID" --arg name "$AMI_NAME" '{"id":$id, "name":$name}' > "$SCRIPT_SOURCE../../build/aws/couchbase-ami-creation/$AMI_NAME.json"
#CLEANUP!
echo "Cleaning up created resources"
echo "Deleting $KEY_NAME"
aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
rm -rf "$HOME/.ssh/aws-keypair.pem"
echo "Deleting instance: $INSTANCE_ID"
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION"