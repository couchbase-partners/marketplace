#!/usr/bin/env bash

set -ex

USERNAME=__USERNAME__
PASSWORD=__PASSWORD__
INSTALL_SCRIPT=__INSTALL_SCRIPT__
VERSION=__VERSION__

until apt-get update > /dev/null; do
    echo "Error getting lock"
    sleep 2
done

until apt-get install jq -y -qq > /dev/null; do
    echo "Error getting lock"
    sleep 2
done

CLUSTER_HOST=$(hostname)

mkdir -p "/setup/"

if [[ ! -e "/setup/couchbase_installer.sh" ]]; then
    curl -L --output "/setup/couchbase_installer.sh" "$INSTALL_SCRIPT"
fi

CLUSTER_MEMBERSHIP=$(curl -q -u "$USERNAME:$PASSWORD" http://127.0.0.1:8091/pools/default | jq -r '') || CLUSTER_MEMBERSHIP="unknown pool"
if [[ "$CLUSTER_MEMBERSHIP" != "unknown pool" ]] && curl -q -u "$USERNAME:$PASSWORD" http://127.0.0.1:8091/pools/default; then
    exit
else
    echo "In the Create Process Step: $CLUSTER_HOST"
    bash /setup/couchbase_installer.sh -u "$USERNAME" -p "$PASSWORD" -ch "$CLUSTER_HOST" -v "$VERSION" -os UBUNTU -e OTHER -c -d
    /opt/couchbase/bin/couchbase-cli bucket-create --cluster http://127.0.0.1:8091 --username $USERNAME --password $PASSWORD --bucket default --bucket-type couchbase --bucket-ramsize 1024
fi 