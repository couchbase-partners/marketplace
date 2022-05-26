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

echo "Retrieving Metadata"
METADATA=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01")

az login --identity --allow-no-subscriptions

function __get_tag() {
    echo "$METADATA" | jq -r --arg param "$1" '.compute.tagsList[] | select(.name == $param) | .value'
}

VAULT=$(__get_tag "key-vault")
VERSION=$(__get_tag "couchbase-server-version")
SECRET=$(__get_tag "couchbase-server-secret")
SERVICES=$(__get_tag "couchbase-server-services")
RALLY_PARAM=$(__get_tag "couchbase-server-rally-parameter")
RALLY_URL=$(__get_tag "couchbase-server-rally-url")
MAKE_CLUSTER=$(__get_tag "couchbase-server-make-cluster")
TAGGED_USERNAME=$(__get_tag "couchbase-server-username")
TAGGED_PASSWORD=$(__get_tag "couchbase-server-password")
DISK_LUN=$(__get_tag "couchbase-server-disk")
RALLY_AUTOSCALING_GROUP=$(echo "$METADATA" | jq -r '.compute.vmScaleSetName')
RESOURCE_GROUP=$(echo "$METADATA" | jq -r '.compute.resourceGroupName')

if [[ -z "$DISK_LUN" ]]; then
    DISK_LUN=NA
fi

DISK=$(lsscsi --brief |  grep -G "\[[1-9]:0:0:$DISK_LUN\]" | awk -v col=2 '{print $col}')

if [[ -z "$VERSION" ]]; then
    VERSION="$COUCHBASE_SERVER_VERSION"
fi
# If no services, we should use some defaults
# TODO:  Add backup for > 7.0.0 versions
if [[ -z "$SERVICES" ]]; then
   SERVICES="data,query,index,analytics,eventing,fts"
   if [[ -n $VERSION ]] && [[ $VERSION == 7* ]]; then
      SERVICES="$SERVICES,backup"
   fi
fi

if [[ -n "$SECRET" ]] && [[ -n "$VAULT" ]]; then
   # We'll need to figure out how to do secrets in GCP eventually
   SECRET_VALUE=$(az keyvault secret show --name "$SECRET" --vault "$VAULT" | jq -r '.value | fromjson')
   USERNAME=$(echo "$SECRET_VALUE" | jq -r .username)
   PASSWORD=$(echo "$SECRET_VALUE" | jq -r .password)
elif [[ -n "$TAGGED_USERNAME" ]] && [[ -n "$TAGGED_PASSWORD" ]]; then
   USERNAME="$TAGGED_USERNAME"
   PASSWORD="$TAGGED_PASSWORD"
else
   USERNAME="NO-USER"
   PASSWORD="NO-PASSWORD"
fi

# Determine Rally DNS
rallyPublicDNS=$(echo "$METADATA" | jq -r 'first(.network.interface[]) | first(.ipv4.ipAddress[]) | .privateIpAddress') || rallyPublicDNS=$(hostname)
# Rally DNS can be a few different things beyond the default
# 1)  It can be the RALLY_PARAM's value (If we have a rally param but no RALLY_URL)
if [[ -n "$RALLY_PARAM" ]] && [[ "$MAKE_CLUSTER" != "true" ]]; then
    # Here we need to retrieve a value from a configuration and use it,  I'm sure this will be some set of curl event
    rallyPublicDNS=$(az keyvault secret show --name "$RALLY_PARAM" --vault "$VAULT" | jq -r '.value')
    # 2) It can be the rally url if they just tag with the url
elif [[ -n "$RALLY_URL" ]]; then
    rallyPublicDNS="$RALLY_URL"
    # 3) It can be the first instance of the auto scaling group that this instance belongs too.
elif [[ -n "$RALLY_AUTOSCALING_GROUP" ]]; then
    # This is going to occur when we are part of a auto scaling unit and we need to "identify" what is the rally.  I think in GCP this is 
    # easier as we can "know" the rally before deploying.  Not 100% though
    echo "Managed Instance Group?"
    THISPUBLIC=$(echo "$METADATA" | jq -r 'first(.network.interface[]) | .ipv4 | first(.ipAddress[]) | .publicIpAddress')
    THISPRIVATE=$(echo "$METADATA" | jq -r 'first(.network.interface[]) | .ipv4 | first(.ipAddress[]) | .privateIpAddress')
    PUBLICIP=$(az vmss list-instance-public-ips --name "$RALLY_AUTOSCALING_GROUP" -g "$RESOURCE_GROUP" | jq -r 'first(.[]) | .ipAddress')
    PRIVATEIP=$(az vmss nic list --vmss-name "$RALLY_AUTOSCALING_GROUP" -g "$RESOURCE_GROUP" | jq -r 'first(.[]) | first(.ipConfigurations[]) | .privateIpAddress')
    if [[ -n "$PUBLICIP" && "$PUBLICIP" != "null" ]]; then
        echo "VMSS has public IP's, we'll use them for cluster host"
        if [[ "$PUBLICIP" == "$THISPUBLIC" ]]; then
            rallyPublicDNS=$(hostname)
        else
            rallyPublicDNS="$PUBLICIP"
        fi
    elif [[ -n "$PRIVATEIP" && "$PRIVATEIP" != "null" ]]; then
        echo "No public ip, so we'll use private IP"
        if [[ "$PRIVATEIP" == "$THISPRIVATE" ]]; then
            rallyPublicDNS=$(hostname)
        else
            rallyPublicDNS="$PRIVATEIP"
        fi
    else
        echo "We can't access info necessary.. default to hostname"
    fi
fi

nodePublicDNS=$(echo "$METADATA" | jq -r '.network.interface[0].ipv4.ipAddress[0].publicIpAddress') || nodePublicDNS=$(hostname)
alternateAddress="$nodePublicDNS"
if [[ -z "$alternateAddress" ]]; then
    alternateAddress=$(hostname)
fi
echo "Using the settings:"
echo "rallyPublicDNS $rallyPublicDNS"
echo "nodePublicDNS $nodePublicDNS"


if [[ "$rallyPublicDNS" == "$nodePublicDNS" ]] && [[ "$MAKE_CLUSTER" == "true" ]] && [[ -n "$RALLY_PARAM" ]]; then
    echo "Updating rally secret with rally url"
    printf "%s" "$rallyPublicDNS" | gcloud secrets versions add "$RALLY_PARAM" --data-file=-
fi

CLUSTER_HOST=$rallyPublicDNS
SUCCESS=1
args=( -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os UBUNTU -e AZURE -s -c -d -sv "$SERVICES")
if [ -n "$DISK" ]; then
   args+=( --format-disk "$DISK" )
fi
if [ -n "$alternateAddress" ]; then
   args+=( -aa "$alternateAddress")
fi
if [[ -z "$VERSION" ]] || [[ "$COUCHBASE_SERVER_VERSION" == "$VERSION" ]]; then
   VERSION="$COUCHBASE_SERVER_VERSION"
   CLUSTER_MEMBERSHIP=$(curl -q -u "$CB_USERNAME:$CB_PASSWORD" http://127.0.0.1:8091/pools/default | jq -r '') || CLUSTER_MEMBERSHIP="unknown pool"
   if [[ "$CLUSTER_MEMBERSHIP" != "unknown pool" ]] && curl -q -u "$CB_USERNAME:$CB_PASSWORD" http://127.0.0.1:8091/pools/default; then
      SUCCESS=0
   else
      export CLI_INSTALL_LOCATION=${COUCHBASE_HOME:-/opt/couchbase/bin/}
      /setup/control/preinst "install"
      /setup/control/postinst "configure"
      systemctl unmask couchbase-server.service
      systemctl enable couchbase-server.service
      systemctl restart couchbase-server.service
      if [[ "$MAKE_CLUSTER" == "true" ]] || [[ -n "$RALLY_PARAM" ]] || [[ -n "$RALLY_URL" ]]; then
        args+=( --cluster-only ) 
        bash /setup/couchbase_installer.sh "${args[@]}"
      fi
      SUCCESS=$?
   fi
else
   rm -rf /opt/couchbase/
   # Update /etc/profile.d/couchbaseserver.sh
   echo "#!/usr/bin/env sh
export COUCHBASE_SERVER_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
if [[ "$MAKE_CLUSTER" == "true" ]] || [[ -n "$RALLY_PARAM" ]] || [[ -n "$RALLY_URL" ]]; then
      bash /setup/couchbase_installer.sh "${args[@]}"
   else
      args+=( --no-cluster )
      bash /setup/couchbase_installer.sh "${args[@]}"
   fi
   SUCCESS=$?
fi

if [[ "$SUCCESS" == 0 && -n "$CONFIG" ]]; then
    # Callback for success?
    echo "Success initialization"
elif [[ -n "$CONFIG" ]]; then
    echo "Failed Initialization"
fi
