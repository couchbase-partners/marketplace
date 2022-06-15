#!/usr/bin/env bash
set -eou pipefail

until apt-get update > /dev/null; do
    echo "Error performing package repository update"
    sleep 1
done
# shellcheck disable=SC2034
DEBIAN_FRONTEND=noninteractive
echo "Installing Prequisites"
until apt-get install --assume-yes apt-utils dialog python-httplib2 jq net-tools wget lsb-release apt-transport-https ca-certificates gnupg libtinfo5 -qq > /dev/null; do
    echo "Error during pre-requisite installation"
    sleep 1
done

echo "deb https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl -o apt-key.gpg -q https://packages.cloud.google.com/apt/doc/apt-key.gpg 
apt-key add ./apt-key.gpg

rm -rf ./apt-key.gpg

until apt-get update > /dev/null; do
    echo "Error performing package repository update"
    sleep 1
done

until apt-get install --assume-yes google-cloud-sdk -qq > /dev/null; do
    echo "Error install gcloud"
    sleep 1
done

VERSION=$1
SYNC_GATEWAY=$2
SCRIPT_URL=$3

mkdir -p /setup/couchbase
mkdir -p /setup/control


echo "Setting Swappiness"
SWAPPINESS=0
cat << _EOF > /etc/sysctl.conf
vm.swappiness = $SWAPPINESS
_EOF

sysctl vm.swappiness=${SWAPPINESS} -q

#Disabling Transparent Huge Pages
echo "Disabling Transparent Hugepages!"
echo "Creating /etc/init.d/disable-thp"
cat << _EOF > /etc/init.d/disable-thp
### BEGIN INIT INFO
# Provides:          disable-thp
# Required-Start:    \$local_fs
# Required-Stop:
# X-Start-Before:    couchbase-server
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Disable THP
# Description:       Disables transparent huge pages (THP) on boot, to improve
#                    Couchbase performance.
### END INIT INFO

case \$1 in
  start)
    if [ -d /sys/kernel/mm/transparent_hugepage ]; then
      thp_path=/sys/kernel/mm/transparent_hugepage
    else
      return 0
    fi

    echo 'never' > \${thp_path}/enabled
    echo 'never' > \${thp_path}/defrag

    unset thp_path
    ;;
esac
_EOF
echo "Setting Permissions"
chmod 755 /etc/init.d/disable-thp
echo "Restarting service"
update-rc.d disable-thp defaults
/etc/init.d/disable-thp start

echo "Downloading install script"
# Grab installer in case we need it and the user doesn't use the pre-installed
wget -O /setup/couchbase_installer.sh "$SCRIPT_URL"


mkdir -p /third_party/

if [[ "$SYNC_GATEWAY" == "0" ]]; then
    wget -O /third_party/notices.txt "https://raw.githubusercontent.com/couchbase/product-metadata/master/couchbase-server/blackduck/${VERSION}/notices.txt"
else 
    wget -o /third_party/notices.txt "https://github.com/couchbase/product-metadata/blob/master/sync_gateway/blackduck/${VERSION}/notices.txt"
fi
# Getting Binaries
echo "Retrieving Binaries"
if [[ "$SYNC_GATEWAY" -gt 0 ]]; then
    echo "Preinstalling Gateway"
cat << _EOF > /etc/profile.d/couchbaseserver.sh
export COUCHBASE_GATEWAY_VERSION="$VERSION"
_EOF
    if [[ ! -f "/home/user/coucbhase-sync-gateway-enterprise_${VERSION}_x86_64.deb" ]]; then
        wget -O "/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb" \
          "https://packages.couchbase.com/releases/couchbase-sync-gateway/${VERSION}/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb" 
    else
        cp "./couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb" "/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb"
    fi
    DEB="/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb"
else
    echo "Preinstalling Server"
    echo "#!/usr/bin/env sh
    export COUCHBASE_SERVER_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
    if [[ ! -f "./couchbase-server-enterprise_${VERSION}-ubuntu20.04_amd64.deb" ]]; then
      wget -O "/setup/couchbase-server-enterprise_$VERSION-ubuntu20.04_amd64.deb"  \
          "http://packages.couchbase.com/releases/${VERSION}/couchbase-server-enterprise_${VERSION}-ubuntu20.04_amd64.deb"
    else
      cp "./couchbase-server-enterprise_${VERSION}-ubuntu20.04_amd64.deb" "/setup/couchbase-server-enterprise_${VERSION}-ubuntu20.04_amd64.deb"
    fi
    DEB="/setup/couchbase-server-enterprise_$VERSION-ubuntu20.04_amd64.deb"
fi

mkdir -p /setup/couchbase
mkdir -p /setup/control
dpkg-deb -x "$DEB" /setup/couchbase
dpkg-deb -e "$DEB" /setup/control
cp -r /setup/couchbase/etc/. /etc/
if [[ "$SYNC_GATEWAY" -lt 1 ]]; then
    cp -r /setup/couchbase/lib/. /lib/
fi
cp -r /setup/couchbase/opt/. /opt/
cp -r /setup/couchbase/usr/. /usr/

rm -rf "$DEB"

echo "Begining setup of startup service"

cp "./startup.sh" "/setup/couchbase-startup.sh"
chmod +x "/setup/couchbase-startup.sh"
rm -rf "./startup.sh"

cat << _EOF > /etc/systemd/system/cb-startup.service
[Unit]
Description=Couchbase intialization script
After=cloud-final.service

[Service]
ExecStart=/setup/couchbase-startup.sh
Type=oneshot
TimeoutStartSec=0

[Install]
WantedBy=default.target
_EOF
echo "Created Service File"
chmod 664 /etc/systemd/system/cb-startup.service
echo "Changed permissions on service"
systemctl daemon-reload
systemctl enable cb-startup.service
echo "DEB Exploder complete"
