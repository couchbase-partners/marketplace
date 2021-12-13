#!/usr/bin/env bash
set -eou pipefail

GATEWAY=0

while getopts gr:i: flag
do
    case "${flag}" in
        r) REGION=${OPTARG};;
        i) AMI_ID=${OPTARG};;
        g) GATEWAY=1;;
        *) exit 1;;
    esac
done
TAB="    "
REGIONS=("ap-northeast-1" "ap-northeast-2" "ap-south-1" "ap-southeast-1" "ap-southeast-2" "ca-central-1" "eu-central-1" "eu-west-1" "eu-west-2" "eu-west-3" "sa-east-1" "us-east-1" "us-east-2" "us-west-1" "us-west-2")
REGION_COUNT="${#REGIONS[@]}"
COUNT=0
NAME=$(aws ec2 describe-images --image-ids "$AMI_ID" --region "$REGION" | jq -r '.Images[0].Name')
DESCRIPTION=$(aws ec2 describe-images --image-ids "$AMI_ID" --region "$REGION" | jq -r '.Images[0].Description')

echo "{"
if [[ "$GATEWAY" == "1" ]]; then
    echo "$TAB\"CouchbaseSyncGateway\": {"
else
    echo "$TAB\"CouchbaseServer\": {"
fi

for i in "${REGIONS[@]}" 
do
    echo "$TAB$TAB\"$i\": {"
    if [[ "$i" == "$REGION" ]]; then
        echo "$TAB$TAB$TAB\"AMI\": \"$AMI_ID\""
    else
        NEW_AMI=$(aws ec2 copy-image --name "$NAME" --description "$DESCRIPTION" --source-image-id "$AMI_ID" --source-region "$REGION" --region "$i" | jq -r '.ImageId')
        echo "$TAB$TAB$TAB\"AMI\": \"$NEW_AMI\""
    fi
    COUNT=$((COUNT + 1))
    if [[ $COUNT -ge $REGION_COUNT ]]; then
        echo "$TAB$TAB}"
    else
        echo "$TAB$TAB},"
    fi
done

echo "$TAB}"
echo "}"