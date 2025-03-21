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

function __get_gcp_metadata_value() {
    wget -O - \
         --header="Metadata-Flavor:Google" \
         -q \
         --retry-connrefused \
         --waitretry=1 \
         --read-timeout=10 \
         --timeout=10 \
         -t 5 \
         "http://metadata/computeMetadata/v1/$1"
}

function __get_gcp_attribute_value() {
    __get_gcp_metadata_value "instance/attributes/$1"
}

echo "Retrieving Metadata"
PROJECT_ID=$(__get_gcp_metadata_value "project/project-id")
echo "GCP Project Id: $PROJECT_ID"
EXTERNAL_IP=$(__get_gcp_metadata_value "instance/network-interfaces/0/access-configs/0/external-ip")
echo "GCP External IP:  $EXTERNAL_IP"
CONFIG=$(__get_gcp_attribute_value "couchbase-server-runtime-config")
echo "GCP Config: $CONFIG"
NODE_PRIVATE_DNS=$(__get_gcp_metadata_value "instance/hostname")
echo "GCP Node Private DNS: $NODE_PRIVATE_DNS"
ZONE=$(wget -O - --header="Metadata-Flavor:Google" -q "http://metadata/computeMetadata/v1/instance/zone")
REGION=$(gcloud compute zones describe "$ZONE" --format=json | jq -r '.region')

VERSION=$(__get_gcp_attribute_value "couchbase-server-version")
SECRET=$(__get_gcp_attribute_value "couchbase-server-secret")
SERVICES=$(__get_gcp_attribute_value "couchbase-server-services")
RALLY_PARAM=$(__get_gcp_attribute_value "couchbase-server-rally-parameter")
RALLY_URL=$(__get_gcp_attribute_value "couchbase-server-rally-url")
MAKE_CLUSTER=$(__get_gcp_attribute_value "couchbase-server-make-cluster")
TAGGED_USERNAME=$(__get_gcp_attribute_value "couchbase-server-username")
TAGGED_PASSWORD=$(__get_gcp_attribute_value "couchbase-server-password")
RALLY_AUTOSCALING_GROUP=$(__get_gcp_attribute_value "created-by")
DISKNAME=$(__get_gcp_attribute_value "couchbase-server-disk")
DISK=
if [[ -n "$DISKNAME" ]]; then
    DISK=$(find /dev/disk/by-id/ -name "*$DISKNAME*" | head -n 1 | xargs ls -l | cut -d'>' -f2 | sed 's|../../|/dev/|' | xargs)
fi

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

if [[ -n "$SECRET" ]]; then
   # We'll need to figure out how to do secrets in GCP eventually
   SECRET_VALUE=$(gcloud secrets versions access latest --secret="$SECRET")
   USERNAME=$(echo "$SECRET_VALUE" | jq -r .username)
   PASSWORD=$(echo "$SECRET_VALUE" | jq -r .password)
elif [[ -n "$TAGGED_USERNAME" ]] && [[ -n "$TAGGED_PASSWORD" ]]; then
   USERNAME="$TAGGED_USERNAME"
   PASSWORD="$TAGGED_PASSWORD"
else
   USERNAME="NO-USER"
   PASSWORD="NO-PASSWORD"
fi

if [[ -n "$CONFIG" ]]; then
    USERNAME=$(gcloud beta runtime-config configs variables get-value Username --config-name="$CONFIG")
    PASSWORD=$(gcloud beta runtime-config configs variables get-value Password --config-name="$CONFIG")
    RALLY_PARAM=$(gcloud beta runtime-config configs variables get-value RallyParamName --config-name="$CONFIG")
    SECRET=$(gcloud beta runtime-config configs variables get-value SecretName --config-name="$CONFIG")

    # we need to check to see if rally and secret are created, if not, we want to create them.  
    if ! gcloud secrets describe "$RALLY_PARAM"; then
        gcloud secrets create "$RALLY_PARAM"
    fi

    if ! gcloud secrets describe "$SECRET"; then
        gcloud secrets create "$SECRET"
        printf "{ \"username\": \"%s\", \"password\": \"%s\" }" "$USERNAME" "$PASSWORD" | gcloud secrets versions add "$SECRET" --data-file=-
    else
        COUNT=0
        SECRET_VALUE=$(gcloud secrets versions access latest --secret="$SECRET")       
        while [[ -z "$SECRET_VALUE"  ]] && [[ "$COUNT" -lt "50" ]]; do
            sleep 0.1
            COUNT=$((COUNT + 1))
        done

        if [[ "$COUNT"  -lt "50" ]]; then
            USERNAME=$(echo "$SECRET_VALUE" | jq -r .username)
            PASSWORD=$(echo "$SECRET_VALUE" | jq -r .password)
        fi
    fi
fi

# Determine Rally DNS
rallyPublicDNS=$(__get_gcp_metadata_value "/instance/hostname") || rallyPublicDNS=$(hostname)
# Rally DNS can be a few different things beyond the default
# 1) It can be the rally url if they just tag with the url
if [[ -n "$RALLY_URL" ]]; then
    rallyPublicDNS="$RALLY_URL"
# 2)  It can be the RALLY_PARAM's value (If we have a rally param but no RALLY_URL)
elif [[ -n "$RALLY_PARAM" ]] && [[ "$MAKE_CLUSTER" != "true" ]]; then
# Here we need to retrieve a value from a configuration and use it,  I'm sure this will be some set of curl event
    rallyPublicDNS=$(gcloud secrets versions access latest --secret="$RALLY_PARAM")
# 3) It can be the first instance of the auto scaling group that this instance belongs too.
elif [[ -n "$RALLY_AUTOSCALING_GROUP" ]]; then
    # This is going to occur when we are part of a auto scaling unit and we need to "identify" what is the rally.  I think in GCP this is 
    # easier as we can "know" the rally before deploying.  Not 100% though
    echo "Managed Instance Group?"
    RALLY_IP=$(gcloud compute instances list \
                    --filter="metadata.items.key['created-by']['value']='$RALLY_AUTOSCALING_GROUP'" \
                    --sort-by=creationTimestamp \
                    --format=json | jq -r '.[0].networkInterfaces[0].networkIP')
    while [[ -z "$RALLY_IP" ]]; do
        sleep 0.1
        RALLY_IP=$(gcloud compute instances list --filter="metadata.items.key['created-by']['value']='$RALLY_AUTOSCALING_GROUP'" --sort-by=creationTimestamp --format=json | jq -r '.[0].networkInterfaces[0].networkIP')
    done
    rallyPublicDNS=$(dig +short -x "$RALLY_IP")
    rallyPublicDNS=${rallyPublicDNS%.}
fi

nodePublicDNS=$(__get_gcp_metadata_value "/instance/hostname") || nodePublicDNS=$(hostname)
echo "Using the settings:"
echo "rallyPublicDNS $rallyPublicDNS"
echo "nodePublicDNS $nodePublicDNS"

externalIp=$(__get_gcp_metadata_value "instance/network-interfaces/0/access-configs/0/external-ip")

if [[ -z "$externalIp" ]]; then
    externalIp=$(hostname)
fi

if [[ "$rallyPublicDNS" == "$nodePublicDNS" ]] && [[ "$MAKE_CLUSTER" == "true" ]] && [[ -n "$RALLY_PARAM" ]]; then
    echo "Updating rally secret with rally url"
    printf "%s" "$rallyPublicDNS" | gcloud secrets versions add "$RALLY_PARAM" --data-file=-
fi

CLUSTER_HOST=$rallyPublicDNS
SUCCESS=1
args=( -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os UBUNTU -e GCP -s -c -d -sv "$SERVICES")
if [ -n "$DISK" ]; then
   args+=( --format-disk "$DISK" )
fi
if [ -n "$externalIp" ]; then
   args+=( -aa "$externalIp")
fi
if [[ -z "$VERSION" ]] || [[ "$COUCHBASE_SERVER_VERSION" == "$VERSION" ]]; then
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

echo "Success(0 is good, other numbers bad)? $SUCCESS"
