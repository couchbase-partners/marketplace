#!/usr/bin/env bash
set -eou pipefail

function __compareVersions() {
    if [[ $1 == "$2" ]]
    then
        echo 0
        return
    fi
    local IFS=.

    local i ver1 ver2
    read -r -a ver1 <<< "$1"
    read -r -a ver2 <<< "$2"
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            echo 1
            return
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            echo -1
            return
        fi
    done
    echo 0
    return
}

until apt-get update > /dev/null; do
    echo "Error performing package repository update"
    sleep 1
done
# shellcheck disable=SC2034
DEBIAN_FRONTEND=noninteractive
echo "Installing Prequisites"
until apt-get install --assume-yes apt-utils dialog jq net-tools wget lsb-release apt-transport-https ca-certificates gnupg -qq > /dev/null; do
    echo "Error during pre-requisite installation"
    sleep 1
done

until apt-get update > /dev/null; do
    echo "Error performing package repository update"
    sleep 1
done

#Install ALiyun SDK
CURR_DIR=$(pwd)
mkdir "$HOME/aliyun"
cd "$HOME/aliyun"
curl -O "https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz"
tar xzvf "aliyun-cli-linux-latest-amd64.tgz"
cp aliyun /usr/local/bin
cd $CURR_DIR

# Setup Aliyun

VERSION=$1
SYNC_GATEWAY=$2
SCRIPT_URL=$3

mkdir -p "$HOME/setup/couchbase"
mkdir -p "$HOME/setup/control"


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
wget -q -O "$HOME/setup/couchbase_installer.sh" "$SCRIPT_URL"

echo "Downloading third party notices"

mkdir -p /third_party/

if [[ "$SYNC_GATEWAY" == "0" ]]; then
    wget -q -O /third_party/notices.txt "https://raw.githubusercontent.com/couchbase/product-metadata/master/couchbase-server/blackduck/${VERSION}/notices.txt"
else 
    wget -q -o /third_party/notices.txt "https://github.com/couchbase/product-metadata/blob/master/sync_gateway/blackduck/${VERSION}/notices.txt"
fi
# Getting Binaries
echo "Retrieving Binaries"
if [[ "$SYNC_GATEWAY" -gt 0 ]]; then
    echo "Preinstalling Gateway"
cat << _EOF > /etc/profile.d/couchbaseserver.sh
export COUCHBASE_GATEWAY_VERSION="$VERSION"
_EOF
    if [[ ! -f "/home/user/coucbhase-sync-gateway-enterprise_${VERSION}_x86_64.deb" ]]; then
        wget -q -O "$HOME/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb" \
          "https://packages.couchbase.com/releases/couchbase-sync-gateway/${VERSION}/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb" 
    else
        cp "./couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb" "$HOME/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb"
    fi
    DEB="/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.deb"
else
    echo "Preinstalling Server"
    ARCH=$(uname -m)
    OS_VERSION="24.04"
    if [[ "$ARCH" == "aarch64" ]]; then
        ARCH=arm64
    fi
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH=amd64
    fi
    download_url="http://packages.couchbase.com/releases/${VERSION}/couchbase-server-enterprise_${VERSION}-ubuntu${OS_VERSION}_${ARCH}.deb"
    file_path="$HOME/setup/couchbase-server-enterprise_${VERSION}-ubuntu${OS_VERSION}_${ARCH}.deb"
    echo "#!/usr/bin/env sh
    export COUCHBASE_SERVER_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
    greaterThan722=$(__compareVersions "7.2.2" "$VERSION")
    if [[ "$greaterThan722" -le "0" ]]; then
        download_url="https://packages.couchbase.com/releases/${VERSION}/couchbase-server-enterprise_${VERSION}-linux_${ARCH}.deb"
        file_path="$HOME/setup/couchbase-server-enterprise-${VERSION}-linux_${ARCH}.deb"
    fi
    if [[ ! -f "./couchbase-server-enterprise_${VERSION}-ubuntu20.04_amd64.deb" ]]; then
      wget -q -O "$file_path" "$download_url"
    else
      cp "./couchbase-server-enterprise_${VERSION}-ubuntu20.04_amd64.deb" "$file_path"
    fi
    DEB="$file_path"
fi

dpkg-deb -x "$DEB" "$HOME/setup/couchbase"
dpkg-deb -e "$DEB" "$HOME/setup/control"
cp -r "$HOME/setup/couchbase/etc/." /etc/
if [[ "$SYNC_GATEWAY" -lt 1 ]]; then
    cp -r "$HOME/setup/couchbase/lib/." /lib/
fi
cp -r "$HOME/setup/couchbase/opt/." /opt/
cp -r "$HOME/setup/couchbase/usr/." /usr/

rm -rf "$DEB"

echo "Begining setup of startup service"

cp "./startup.sh" "$HOME/setup/couchbase-startup.sh"
chmod +x "$HOME/setup/couchbase-startup.sh"
#rm -rf "./startup.sh"
cat "$HOME/setup/couchbase-startup.sh"

cat << _EOF > "$HOME/setup/cb-startup.service"
[Unit]
Description=Couchbase intialization script
After=cloud-final.service

[Service]
ExecStart=$HOME/setup/couchbase-startup.sh
Type=oneshot
TimeoutStartSec=0

[Install]
WantedBy=default.target
_EOF
echo "Created Service File"
cat "$HOME/setup/cb-startup.service"
chmod 664 "$HOME/setup/cb-startup.service"
echo "Changed permissions on service"
echo "Copying Service To etc"
ln -sf "$HOME/setup/cb-startup.service" "/etc/systemd/system/cb-startup.service"
systemctl daemon-reload
systemctl enable cb-startup.service
echo "DEB Exploder complete"
