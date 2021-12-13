#!/bin/bash

set -eu 

###############################################################################
# Dependencies:                                                               #
# gcloud                                                                      #
# tr                                                                          #
###############################################################################

###############################################################################
#  Parameters                                                                 #
#  -l :  license                                                              #
#     usage: -l couchbase-server-ee-hourly-pricing                            #
#     purpose: license to be added to the image                               #     
#  -n : name                                                                  #
#     usage:  -n couchbase-server-ee-byol                                     #
#     purpose:  The name of the image (post-fixed with vYYYYMMDD)             #
#  -z : zone                                                                  #
#     usage: -z us-east1-b                                                    #
#     purpose: specifies the zone in which to create the image                #
#  -p : GCP Project                                                           #
#     usage: -p couchbase-public                                              #
#     purposes: The project to create the images in                           #
#  -f : Image Family                                                          #
#     usage: -v ubuntu-1804-lts                                               #
#     purposes: this is the family name to use to create the base instance    #
#  -i : Image Project                                                         #
#     usage: -i ubuntu-os-cloud                                               #
#     purposes: The project name in which the base OS resides                 #
###############################################################################

function __generate_random_string() {
    NEW_UUID=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 10 ; echo '')
    echo "${NEW_UUID}"
}

SCRIPT_SOURCE=${BASH_SOURCE[0]/%create.sh/}
SCRIPT_URL=$(cat "${SCRIPT_SOURCE}/../../script_url.txt")
gateway=0
debug=0

while getopts l:n:z:p:f:i:v:c:gd flag
do
    case "${flag}" in
        l) license=${OPTARG};;
        n) name=${OPTARG};;
        z) zone=${OPTARG};;
        p) project=${OPTARG};;
        f) family=${OPTARG};;
        i) image_project=${OPTARG};;
        v) version=${OPTARG};;
        g) gateway=1;;
        d) debug=1;;
        c) image_family=${OPTARG};;
        *) exit 1;;
    esac
done

date=$(date '+%Y%m%d')
image_name="$name-v$date"
random_string=$(__generate_random_string)
instance_name="$name-$random_string"
echo "Creating instance: $instance_name"
createInstanceResponse=$(gcloud compute instances create "$instance_name" \
                                                 --zone="$zone" \
                                                 --image-family="$family" \
                                                 --image-project="$image_project" \
                                                 --project="$project" \
                                                 --scopes "https://www.googleapis.com/auth/cloud-platform")

echo "Create Instance Response: $createInstanceResponse"
sleep 40
echo "Adding deb_exploder to the instance"
gcloud compute scp "${SCRIPT_SOURCE}/deb_exploder.sh" "$instance_name:~/deb_exploder.sh" --zone="$zone"
echo "Adding Appropriate Startup.sh to instance"

if [[ "$gateway" == "1" ]]; then 
    gcloud compute scp "${SCRIPT_SOURCE}/gateway-startup.sh" "$instance_name:~/startup.sh" --zone="$zone"
else
    gcloud compute scp "${SCRIPT_SOURCE}/server-startup.sh" "$instance_name:~/startup.sh" --zone="$zone"
fi


echo "Executing the deb_exploder"
gcloud compute ssh "$instance_name" --command="sudo chmod +x ~/deb_exploder.sh && sudo ~/deb_exploder.sh $version $gateway $SCRIPT_URL" --zone="$zone"
echo "Deleting Instance but preserving boot disk"
gcloud compute instances delete "$instance_name" --zone="$zone" --project="$project" --keep-disks=boot -q
echo "Creating Image from boot disk"
# don't add a license if we're in debug.
description="Couchbase Server Enterprise Edition Marketplace Image - Preinstalled Version: $version"
if [[ "$gateway" == "1" ]]; then
    description="Couchbase Sync Gateway Marketplace Image - Preinstalled Version: $version"
fi
if [[ "$debug" == "0" ]]; then
    createImageResponse=$(gcloud compute images create "$image_name" \
                            --project "$project" \
                            --source-disk "projects/$project/zones/$zone/disks/$instance_name" \
                            --licenses "projects/$project/global/licenses/$license" \
                            --family="$image_family" \
                            --description="$description")
else 
    createImageResponse=$(gcloud compute images create "$image_name" \
                            --project "$project" \
                            --source-disk "projects/$project/zones/$zone/disks/$instance_name" \
                            --family="$image_family" \
                            --description="$description")
fi
echo "Create Image Response: $createImageResponse"                        