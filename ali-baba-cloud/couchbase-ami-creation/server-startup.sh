#!/usr/bin/env bash

set -x
echo "Beginning"
# There is a race condition based on when the env vars are set by profile.d and when cloud-init executes
# this just removes that race condition
if [[ -r /etc/profile.d/couchbaseserver.sh ]]; then
   # Disabling lint for unreachable source file
   # shellcheck disable=SC1091
   source /etc/profile.d/couchbaseserver.sh
fi

function __get_aliyun_metadata_value() {
    wget -O - \
         -q \
         --retry-connrefused \
         --waitretry=1 \
         --read-timeout=10 \
         --timeout=10 \
         -t 5 \
         "http://100.100.100.200/latest/meta-data/$1"
}



function __get_tag_data() {
    local TAGS="$2"
    if [ -z "$TAGS" ]; then
    # Populate Tags Data.  Otherwise assume it's a json value with the appropriate values
        ROLE=$(__get_aliyun_metadata_value "ram/security-credentials/")
        REGION=$(__get_aliyun_metadata_value "region-id")
        aliyun configure set --profile EcsRamRoleProfile --mode EcsRamRole --ram-role-name "$ROLE" --region "$REGION"
        INSTANCE_ID=$(__get_aliyun_metadata_value "instance-id")
        TAGS=$(aliyun ecs ListTagResources --RegionId "$REGION" --ResourceId "$INSTANCE_ID" --ResourceType instance | jq -r '.TagResources')
    fi
    TARGET_TAG="$1"
    echo "$TAGS" | jq -r --arg t "$TARGET_TAG" '.TagResource[] | select (.TagKey == $t) | .TagValue'
}

# Check if we have a RAM account for tags
CODE=$(curl -IL -X GET http://100.100.100.200/latest/meta-data/ram/ 2>/dev/null | head -n 1 | cut -d$' ' -f2)
sleep 2
CB_STARTED=$(curl -IL -X GET http://localhost:8091/ui/index.html 2>/dev/null | head -n 1 | cut -d$' ' -f2)
if [[ "$CODE" == "404" && "$CB_STARTED" != "200" ]]; then
      /root/setup/control/preinst "install"
      /root/setup/control/postinst "configure"
      systemctl unmask couchbase-server.service
      systemctl enable couchbase-server.service
      systemctl restart couchbase-server.service
      exit 0
fi

ROLE=$(__get_aliyun_metadata_value "ram/security-credentials/")
REGION=$(__get_aliyun_metadata_value "region-id")
aliyun configure set --profile EcsRamRoleProfile --mode EcsRamRole --ram-role-name "$ROLE" --region "$REGION"
INSTANCE_ID=$(__get_aliyun_metadata_value "instance-id")
TAGS=$(aliyun ecs ListTagResources --RegionId "$REGION" --ResourceId "$INSTANCE_ID" --ResourceType instance | jq -r '.TagResources')

echo "Retrieving Metadata"
EXTERNAL_IP=$(__get_aliyun_metadata_value eipv4)
echo "Aliyun External IP:  $EXTERNAL_IP"
NODE_PRIVATE_DNS=$(__get_aliyun_metadata_value "hostname")
echo "Aliyun Node Private DNS: $NODE_PRIVATE_DNS"
REGION=$(__get_aliyun_metadata_value "region-id")

VERSION=$(__get_tag_data "couchbase-server-version" "$TAGS")
SERVICES=$(__get_tag_data "couchbase-server-services" "$TAGS")
RALLY_URL=$(__get_tag_data "couchbase-server-rally-url" "$TAGS")
MAKE_CLUSTER=$(__get_tag_data "couchbase-server-make-cluster" "$TAGS")
TAGGED_USERNAME=$(__get_tag_data "couchbase-server-username" "$TAGS")
TAGGED_PASSWORD=$(__get_tag_data "couchbase-server-password" "$TAGS")

# this is a hoop to jump through to go from the given disk name to the actual mount point on the disk controller
DISKNAME=$(__get_tag_data "couchbase-server-disk" "$TAGS")
if [ -z "$DISKNAME" ]; then
    if lsblk | grep -q "nvme1n1"; then 
        DISKNAME="/dev/nvme1n1"
    fi
fi

DISK="$DISKNAME"

if [[ -z "$VERSION" ]]; then
    VERSION="$COUCHBASE_SERVER_VERSION"
fi
# If no services, we should use some defaults
if [[ -z "$SERVICES" ]]; then
   SERVICES="data,query,index,analytics,eventing,fts,backup"
fi

# TODO:  Eventually we need to figure out secrets 
if [[ -n "$TAGGED_USERNAME" ]] && [[ -n "$TAGGED_PASSWORD" ]]; then
   USERNAME="$TAGGED_USERNAME"
   PASSWORD="$TAGGED_PASSWORD"
else
   USERNAME="NO-USER"
   PASSWORD="NO-PASSWORD"
fi

# Determine Rally DNS
rallyPublicDNS=$NODE_PRIVATE_DNS
# Rally DNS can be a few different things beyond the default
# 1) It can be the rally url if they just tag with the url
if [[ -n "$RALLY_URL" ]]; then
    rallyPublicDNS="$RALLY_URL"
fi

nodePublicDNS=$(__get_aliyun_metadata_value "hostname") || nodePublicDNS=$(hostname)
echo "Using the settings:"
echo "rallyPublicDNS $rallyPublicDNS"
echo "nodePublicDNS $nodePublicDNS"

if [[ -z "$EXTERNAL_IP" ]]; then
    EXTERNAL_IP=$(hostname)
fi

CLUSTER_HOST=$rallyPublicDNS
SUCCESS=1
args=( -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os UBUNTU -e GCP -s -c -d -sv "$SERVICES")
if [ -n "$DISK" ]; then
   args+=( --format-disk "$DISK" )
fi
if [ -n "$EXTERNAL_IP" ]; then
   args+=( -aa "$EXTERNAL_IP")
fi
if [[ -z "$VERSION" ]] || [[ "$COUCHBASE_SERVER_VERSION" == "$VERSION" ]]; then
   CLUSTER_MEMBERSHIP=$(curl -q -u "$CB_USERNAME:$CB_PASSWORD" http://127.0.0.1:8091/pools/default | jq -r '') || CLUSTER_MEMBERSHIP="unknown pool"
   if [[ "$CLUSTER_MEMBERSHIP" != "unknown pool" ]] && curl -q -u "$CB_USERNAME:$CB_PASSWORD" http://127.0.0.1:8091/pools/default; then
      SUCCESS=0
   else
      export CLI_INSTALL_LOCATION=${COUCHBASE_HOME:-/opt/couchbase/bin/}
      /root/setup/control/preinst "install"
      /root/setup/control/postinst "configure"
      systemctl unmask couchbase-server.service
      systemctl enable couchbase-server.service
      systemctl restart couchbase-server.service
      if [[ "$MAKE_CLUSTER" == "true" ]] || [[ -n "$RALLY_PARAM" ]] || [[ -n "$RALLY_URL" ]]; then 
        args+=( --cluster-only ) 
        bash /root/setup/couchbase_installer.sh "${args[@]}"
      fi
      SUCCESS=$?
   fi
else
   rm -rf /opt/couchbase/
   # Update /etc/profile.d/couchbaseserver.sh
   echo "#!/usr/bin/env sh
export COUCHBASE_SERVER_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
if [[ "$MAKE_CLUSTER" == "true" ]] || [[ -n "$RALLY_PARAM" ]] || [[ -n "$RALLY_URL" ]]; then
      bash /root/setup/couchbase_installer.sh "${args[@]}"
   else
      args+=( --no-cluster )
      bash /root/setup/couchbase_installer.sh "${args[@]}"
   fi
fi
