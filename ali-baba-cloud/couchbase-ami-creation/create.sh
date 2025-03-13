#!/bin/bash

set -eu 

###############################################################################
# Dependencies:                                                               #
# gcloud                                                                      #
# tr                                                                          #
###############################################################################

###############################################################################
#  Parameters                                                                 #
#  -i :  Instance Type                                                        #
#     usage: -i ecs.c8i.2xlarge                                               #
#     purpose: The instance type to use to generate AMI                       #     
#  -n : name                                                                  #
#     usage:  -n couchbase-server-ee-byol                                     #
#     purpose:  The name of the image (post-fixed with vYYYYMMDD)             #
#  -r : Region                                                                #
#     usage: -r us-east-1                                                     #
#     purpose: specifies the zone in which to create the image                #
###############################################################################

function __generate_random_string() {
    NEW_UUID=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 10 ; echo '')
    echo "${NEW_UUID}"
}

SCRIPT_SOURCE=${BASH_SOURCE[0]/%create.sh/}
SCRIPT_URL=$(cat "${SCRIPT_SOURCE}/../../script_url.txt")
GATEWAY=0
DEBUG=0
PACKAGE=""
SKIP_CLEANUP=0

while getopts n:r:i:v:k:cgd flag
do
    case "${flag}" in
        n) NAME=${OPTARG};;
        r) REGION=${OPTARG};;
        i) INSTANCE_TYPE=${OPTARG};;
        v) VERSION=${OPTARG};;
        g) GATEWAY=1;;
        d) DEBUG=1;;
        c) SKIP_CLEANUP=1;;
        k) PACKAGE=${OPTARG};;
        *) exit 1;;
    esac
done

DATE=$(date '+%Y%m%d%H%M')
IMAGE_NAME="$NAME-v$VERSION-$DATE"
RANDOM_STRING=$(__generate_random_string)
INSTANCE_NAME="$NAME-$RANDOM_STRING"

echo "Getting Image Id"
IMAGE_ID=$(aliyun ecs DescribeImages --RegionId "$REGION" --ImageFamily "acs:ubuntu_24_04_x64" | jq -r '.Images.Image[0].ImageId')
echo "Image id: $IMAGE_ID"

echo "Getting ZoneId Within Region"
ZONE_ID=$(aliyun ecs DescribeZones --RegionId "$REGION" | jq -r '.Zones.Zone[0].ZoneId')
echo "Selected ZoneId: $ZONE_ID"

echo "Getting VPC Id"
VPC_ID=$(aliyun vpc DescribeVpcs --RegionId "$REGION" | jq -r '.Vpcs.Vpc[]|select(.IsDefault=true).VpcId')
echo "VPC Id: $VPC_ID"

KP_NAME="$NAME-kp-$RANDOM_STRING"
echo "Creating Keypair: $KP_NAME"
aliyun ecs CreateKeyPair --RegionId "$REGION" --KeyPairName "$KP_NAME" | jq -r '.PrivateKeyBody' > "./$KP_NAME.pem"
echo "Setting Permissions on ./$KP_NAME.pem"
chmod 600 "./$KP_NAME.pem"
echo "Key Pair Name: $KP_NAME"

# TODO:  We should just check to see if a VSwitch covers our target CidrBlock and re-use it
VSWITCH_NAME="$NAME-$RANDOM_STRING-vsw"
echo "Creating VSwitch: $VSWITCH_NAME"
VSWITCH_ID=$(aliyun vpc CreateVSwitch --RegionId "$REGION" --VpcId "$VPC_ID" --CidrBlock 172.16.1.0/28 --VSwitchName "$VSWITCH_NAME" --ZoneId "$ZONE_ID" | jq -r '.VSwitchId')
echo "VSwitch Id: $VSWITCH_ID"

SECURITY_GROUP_NAME="$NAME-$RANDOM_STRING-sg"
echo "Creating Security Group: $SECURITY_GROUP_NAME"
SG_ID=$(aliyun ecs CreateSecurityGroup --region "$REGION" --RegionId "$ZONE_ID" --VpcId "$VPC_ID" --SecurityGroupName "$SECURITY_GROUP_NAME" --SecurityGroupType normal | jq -r '.SecurityGroupId')
echo "Security Group ID: $SG_ID"

echo "Adding permissions to Security Group: $SECURITY_GROUP_NAME"
aliyun ecs AuthorizeSecurityGroup --region "$REGION" --RegionId "$REGION" --SecurityGroupId "$SG_ID" \
       --Permissions.1.Policy accept --Permissions.1.IpProtocol TCP --Permissions.1.SourceCidrIp '0.0.0.0/0' --Permissions.1.PortRange '22/22' --Permissions.1.Description SSH \
       --Permissions.2.Policy accept --Permissions.2.IpProtocol TCP --Permissions.2.SourceCidrIp '0.0.0.0/0' --Permissions.2.PortRange '8091/8091' --Permissions.2.Description "CouchbaseServer" \
       --method POST --force --retry-count 3 --connect-timeout 30 --read-timeout 60




echo "Creating instance: $INSTANCE_NAME"
CREATE_INSTANCE_RESPONSE=$(aliyun ecs RunInstances --region "$REGION" --RegionId "$REGION" --ImageId "$IMAGE_ID" \
                                --InstanceType "$INSTANCE_TYPE" --InstanceName "$INSTANCE_NAME" \
                                --SystemDisk.Size 25 --SystemDisk.Category cloud_essd --SystemDisk.DiskName SystemDisk \
                                --InstanceChargeType PostPaid --KeyPairName "$KP_NAME" --HttpEndpoint enabled --InternetMaxBandwidthOut 5 \
                                --NetworkInterface.1.VSwitchId "$VSWITCH_ID" --NetworkInterface.1.NetworkInterfaceName "$INSTANCE_NAME-eid" \
                                --NetworkInterface.1.SecurityGroupId "$SG_ID" --NetworkInterface.1.NetworkInterfaceTrafficMode standard \
                                --NetworkInterface.1.InstanceType Primary --DataDisk.1.Size 100 --DataDisk.1.DiskName datadisk --DataDisk.1.Category cloud_essd \
                                --retry-count 3 --connect-timeout 30 --read-timeout 60)

echo "Create Instance Response: $CREATE_INSTANCE_RESPONSE"
INSTANCE_ID=$(echo "$CREATE_INSTANCE_RESPONSE" | jq -r '.InstanceIdSets.InstanceIdSet[0]')
echo "Instance Id: $INSTANCE_ID"

echo "Adding Public IP Address to Instance"
# This can fail as the instance isn't quite ready yet.  Need to wait a bit before and retry
sleep 20
PUBLIC_IP=$(aliyun ecs AllocatePublicIpAddress --InstanceId "$INSTANCE_ID" --RegionId "$REGION" | jq -r '.IpAddress')
while [ $? -ne 0 ]; do
    echo "Assigning Public IP Failed.  Trying again"
    PUBLIC_IP=$(aliyun ecs AllocatePublicIpAddress --InstanceId "$INSTANCE_ID" --RegionId "$REGION" | jq -r '.IpAddress' --retry-count 3 --connect-timeout 30 --read-timeout 60)
done
echo "Public Ip Address: $PUBLIC_IP"

# Waiting for SSH to start up on the instance
sleep 30
echo "Adding deb_exploder to the instance"
scp -i "./$KP_NAME.pem" -o StrictHostKeyChecking=no "${SCRIPT_SOURCE}/deb_exploder.sh" "root@$PUBLIC_IP:/root/deb_exploder.sh"
echo "Adding Appropriate Startup.sh to instance"

if [[ -n "$PACKAGE" ]]; then
    echo "Adding custom package to instance"
    FILE=$(basename "$PACKAGE")
    scp -i "./$KP_NAME.pem" -o StrictHostKeyChecking=no "$PACKAGE" "root@$PUBLIC_IP:/root/$FILE"

fi

if [[ "$GATEWAY" == "1" ]]; then
    echo "Adding Gateway Startup"
    scp -i "./$KP_NAME.pem" -o StrictHostKeyChecking=no "${SCRIPT_SOURCE}/gateway-startup.sh" "root@$PUBLIC_IP:/root/startup.sh"
else
    echo "Adding Server Startup"
    scp -i "./$KP_NAME.pem" -o StrictHostKeyChecking=no "${SCRIPT_SOURCE}/server-startup.sh" "root@$PUBLIC_IP:/root/startup.sh"
fi


echo "Executing the deb_exploder"
ssh -i "./$KP_NAME.pem" -o StrictHostKeyChecking=no "root@$PUBLIC_IP" "sudo chmod +x ~/deb_exploder.sh && sudo ~/deb_exploder.sh ${VERSION} ${GATEWAY} ${SCRIPT_URL} && echo 'Removing Exploder' && rm -rf ~/deb_exploder.sh && exit"


sleep 30
echo "Creating Image from instance: $INSTANCE_ID"
# don't add a license if we're in debug.
IMAGE_FAMILY="CouchbaseServer"
DESCRIPTION="Couchbase Server Enterprise Edition Marketplace Image - Preinstalled Version: $VERSION"
if [[ "$GATEWAY" == "1" ]]; then
    IMAGE_FAMILY="CouchbaseSyncGateway"
    DESCRIPTION="Couchbase Sync Gateway Marketplace Image - Preinstalled Version: $VERSION"
fi
CREATE_IMAGE_RESPONSE=$(aliyun ecs CreateImage --region "$REGION" --RegionId "$REGION" --ImageVersion "$VERSION" --Description "$DESCRIPTION" --Platform "Ubuntu" \
                            --BootMode "UEFI-Preferred" --Architecture "x86_64" --ImageName "$IMAGE_NAME" --InstanceId "$INSTANCE_ID" --ImageFamily "$IMAGE_FAMILY" \
                            --retry-count 3 --connect-timeout 30 --read-timeout 60)
echo "Create Image Response: $CREATE_IMAGE_RESPONSE"

echo "*** ---- Cleaning Up Resources ---- ***"
if [[ "$SKIP_CLEANUP" == "1" ]]; then
    echo "Exiting without Cleanup, per request"
    exit 0
fi
echo "*** --- Deleting Instance --- ***"
DELETE_INSTANCE_RESPONSE=$(aliyun ecs DeleteInstance --region "$REGION" --RegionId "$REGION" --InstanceId "$INSTANCE_ID" --TerminateSubscription true --Force true --retry-count 10 --connect-timeout 30 --read-timeout 60)
echo "Delete Instance Response: $DELETE_INSTANCE_RESPONSE"

echo "*** ---- Deleting key pair ---- ***"
DELETE_KP_RESPONSE=$(aliyun ecs DeleteKeyPairs --RegionId "$REGION" --KeyPairNames "['$KP_NAME']" --retry-count 10 --connect-timeout 30 --read-timeout 60)
if [ ! -z "$KP_NAME" ]; then
    rm -rf "./$KP_NAME.pem"
fi
echo "Delete KP Response: $DELETE_KP_RESPONSE"

echo "*** ---- Deleting Security Group ---- ***"
# need to wait a bit and let the instance fully get deleted before we can delete the security group
sleep 60
DELETE_SG_RESPONSE=$(aliyun ecs DeleteSecurityGroup --region "$REGION" --RegionId "$REGION" --SecurityGroupId "$SG_ID" --retry-count 10 --connect-timeout 30 --read-timeout 60)
echo "Delete Security Group Response: $DELETE_SG_RESPONSE"

echo "*** ---- Deleting VSwitch ---- ***"
# same as instance,  we have to wait to delete the vswitch
DELETE_VSWITCH_RESPONSE=$(aliyun vpc DeleteVSwitch --RegionId "$REGION" --VSwitchId "$VSWITCH_ID" --retry-count 10 --connect-timeout 30 --read-timeout 60)
echo "Delete VSwitch Response: $DELETE_VSWITCH_RESPONSE"



