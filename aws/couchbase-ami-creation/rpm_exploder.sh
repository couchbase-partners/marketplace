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

yum install jq aws-cfn-bootstrap -y -q

VERSION=$1
SYNC_GATEWAY=$2
SCRIPT_URL=$3
mkdir /setup

ARCHITECTURE=$(uname -m)

echo "Setting Swappiness"
# Setting swappiness to 0
SWAPPINESS=0
echo "
# Required for Couchbase
vm.swappiness = ${SWAPPINESS}
" >> /etc/sysctl.conf

sysctl vm.swappiness=${SWAPPINESS} -q

# Disable Transparent Huge Pages
echo "Disabling Transparent Hugepages"
echo "#!/bin/bash
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
    elif [ -d /sys/kernel/mm/redhat_transparent_hugepage ]; then
      thp_path=/sys/kernel/mm/redhat_transparent_hugepage
    else
      return 0
    fi

    echo 'never' > \${thp_path}/enabled
    echo 'never' > \${thp_path}/defrag

    re='^[0-1]+$'
    if [[ \$(cat \${thp_path}/khugepaged/defrag) =~ \$re ]]
    then
      # RHEL 7
      echo 0  > \${thp_path}/khugepaged/defrag
    else
      # RHEL 6
      echo 'no' > \${thp_path}/khugepaged/defrag
    fi

    unset re
    unset thp_path
    ;;
esac
    " > /etc/init.d/disable-thp
chmod 755 /etc/init.d/disable-thp
chkconfig --add disable-thp
service disable-thp start

echo "Downloading install script"
# Grab installer in case we need it and the user doesn't use the pre-installed
wget -O /setup/couchbase_installer.sh "$SCRIPT_URL"

echo "Retrieving Binaries"
if [[ "$SYNC_GATEWAY" -gt 0 ]]; then
    echo "Preinstalling Gateway"
    echo "#!/usr/bin/env sh
    export COUCHBASE_GATEWAY_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
    if [[ ! -f "/home/ec2-user/couchbase-sync-gateway-enterprise_${VERSION}_${ARCHITECTURE}.rpm" ]]; then
      wget -O "/setup/couchbase-sync-gateway-enterprise_${VERSION}_${ARCHITECTURE}.rpm" \
          "https://packages.couchbase.com/releases/couchbase-sync-gateway/${VERSION}/couchbase-sync-gateway-enterprise_${VERSION}_${ARCHITECTURE}.rpm" --quiet
    else
      cp "/home/ec2-user/couchbase-sync-gateway-enterprise_${VERSION}_${ARCHITECTURE}.rpm" "/setup/couchbase-sync-gateway-enterprise_${VERSION}_${ARCHITECTURE}.rpm"
    fi
    RPM="/setup/couchbase-sync-gateway-enterprise_${VERSION}_${ARCHITECTURE}.rpm"
else 
    echo "Preinstalling Server"
    echo "#!/usr/bin/env sh
    export COUCHBASE_SERVER_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
    DOWNLOAD_URL="https://packages.couchbase.com/releases/$VERSION/couchbase-server-enterprise-$VERSION-amzn2.${ARCHITECTURE}.rpm"
    FILE_NAME="couchbase-server-enterprise-$VERSION-amzn2.${ARCHITECTURE}.rpm"
    greaterThan722=$(__compareVersions "7.2.2" "$VERSION")
    if [[ "$greaterThan722" -le "0" ]]; then
      DOWNLOAD_URL="https://packages.couchbase.com/releases/${VERSION}/couchbase-server-enterprise-${VERSION}-linux.${ARCHITECTURE}.rpm"
      FILE_NAME="couchbase-server-enterprise-${VERSION}-linux.${ARCHITECTURE}.rpm"
    fi
    echo "File Name: $FILE_NAME"
    echo $(test -f "/home/ec2-user/$FILE_NAME")
    echo $(ls -l /home/ec2-user)

    if [[ ! -f "/home/ec2-user/$FILE_NAME" ]]; then
      wget -O "/setup/$FILE_NAME" "$DOWNLOAD_URL" --quiet
    else
      cp "/home/ec2-user/$FILE_NAME" "/setup/$FILE_NAME"
    fi
    RPM="/setup/$FILE_NAME"
fi

echo "Installing prerequisites"
# Install prerequistites
sudo yum deplist "$RPM" | awk '/provider:/ {print $2}' | sort -u | xargs sudo yum -y install

echo "Extracting Preinstall scripts"
# Extract Pre-Install
START=$(rpm -qp --scripts "$RPM" | grep -n 'preinstall scriptlet (using /bin/sh):' | cut -d ":" -f 1)
START=$((START + 1))
STOP=$(rpm -qp --scripts "$RPM" | grep -n 'postinstall scriptlet (using /bin/sh):' | cut -d ":" -f 1)
STOP=$((STOP - 1))
SED="${START},${STOP}p"
rpm -qp --scripts "$RPM" | sed -n "$SED" > /setup/preinstall.sh

echo "Execute Preinstall"
# execute pre-install
/usr/bin/env sh /setup/preinstall.sh

echo "Extract without executing scripts"
# extract and maneuver files without scripts
rpm -i --noscripts "$RPM"

# Extract POST-Install
echo "Extracting Postinstall scripts"
START=$(rpm -qp --scripts $RPM | grep -n 'postinstall scriptlet (using /bin/sh):' | cut -d ":" -f 1)
START=$((START + 1))
STOP=$(rpm -qp --scripts "$RPM" | grep -n 'preuninstall scriptlet (using /bin/sh):' | cut -d ":" -f 1)
STOP=$((STOP - 1))
SED="${START},${STOP}p"
rpm -qp --scripts "$RPM" | sed -n "$SED" > /setup/postinstall.sh

# Extract POST-Transaction Script
echo "Extracting Post Transaction Script"
START=$(rpm -qp --scripts "$RPM" | grep -n 'posttrans scriptlet (using /bin/sh):' | cut -d ":" -f 1)
START=$((START + 1))
SED="${START},\$p"
rpm -qp --scripts "$RPM" | sed -n "$SED" > /setup/posttransaction.sh

rm -rf "$RPM"

echo "Beginning setup of Startup Service"

cp "/home/ec2-user/startup.sh" "/setup/couchbase-startup.sh"
rm -rf "/home/ec2-user/startup.sh"

echo "Copied startup file.  Created Systemctl unit"
chmod +x /setup/couchbase-startup.sh
echo "Modified Permissions"
cat << _EOF > /etc/systemd/system/cb-startup.service
[Unit]
Description=Couchbase intialization script
After=cloud-final.service

[Service]
ExecStart=/setup/couchbase-startup.sh
Type=oneshot
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
_EOF
echo "Created Service File"
chmod 664 /etc/systemd/system/cb-startup.service
echo "Changed permissions on service"
systemctl daemon-reload
systemctl enable cb-startup.service
echo "RPM Exploder complete"
