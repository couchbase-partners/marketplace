#!/usr/bin/env bash
set -eou pipefail

VERSION=$1
SYNC_GATEWAY=$2
SCRIPT_URL=$3
mkdir /setup

# Setting swappiness to 0
SWAPPINESS=0
echo "
# Required for Couchbase
vm.swappiness = ${SWAPPINESS}
" >> /etc/sysctl.conf

sysctl vm.swappiness=${SWAPPINESS} -q

# Disable Transparent Huge Pages

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


# Grab installer in case we need it and the user doesn't use the pre-installed
wget -O /setup/couchbase_installer.sh "$SCRIPT_URL"

if [[ "$SYNC_GATEWAY" -gt 0 ]]; then
    echo "Preinstalling Gateway"
    echo "#!/usr/bin/env sh
    export COUCHBASE_GATEWAY_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
    if [[ ! -f "/home/ec2-user/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.rpm" ]]; then
      wget -O "/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.rpm" \
          "https://packages.couchbase.com/releases/couchbase-sync-gateway/${VERSION}/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.rpm" --quiet
    else
      cp "/home/ec2-user/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.rpm" "/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.rpm"
    fi
    RPM="/setup/couchbase-sync-gateway-enterprise_${VERSION}_x86_64.rpm"
else 
    echo "Preinstalling Server"
    echo "#!/usr/bin/env sh
    export COUCHBASE_SERVER_VERSION=$VERSION" > /etc/profile.d/couchbaseserver.sh
    if [[ ! -f "/home/ec2-user/couchbase-server-enterprise-${VERSION}-amzn2.x86_64.rpm" ]]; then
      wget -O "/setup/couchbase-server-enterprise-$VERSION-amzn2.x86_64.rpm"  \
          "https://packages.couchbase.com/releases/$VERSION/couchbase-server-enterprise-$VERSION-amzn2.x86_64.rpm" --quiet
    else
      cp "/home/ec2-user/couchbase-server-enterprise-${VERSION}-amzn2.x86_64.rpm" "/setup/couchbase-server-enterprise-${VERSION}-amzn2.x86_64.rpm"
    fi
    RPM="/setup/couchbase-server-enterprise-$VERSION-amzn2.x86_64.rpm"
fi

# Install prerequistites
sudo yum deplist "$RPM" | awk '/provider:/ {print $2}' | sort -u | xargs sudo yum -y install

# Extract Pre-Install
START=$(rpm -qp --scripts "$RPM" | grep -n 'preinstall scriptlet (using /bin/sh):' | cut -d ":" -f 1)
START=$((START + 1))
STOP=$(rpm -qp --scripts "$RPM" | grep -n 'postinstall scriptlet (using /bin/sh):' | cut -d ":" -f 1)
STOP=$((STOP - 1))
SED="${START},${STOP}p"
rpm -qp --scripts "$RPM" | sed -n "$SED" > /setup/preinstall.sh

# execute pre-install
/usr/bin/env sh /setup/preinstall.sh

# extract and maneuver files without scripts
rpm -i --noscripts "$RPM"

# Extract POST-Install
START=$(rpm -qp --scripts $RPM | grep -n 'postinstall scriptlet (using /bin/sh):' | cut -d ":" -f 1)
START=$((START + 1))
STOP=$(rpm -qp --scripts "$RPM" | grep -n 'preuninstall scriptlet (using /bin/sh):' | cut -d ":" -f 1)
STOP=$((STOP - 1))
SED="${START},${STOP}p"
rpm -qp --scripts "$RPM" | sed -n "$SED" > /setup/postinstall.sh

# Extract POST-Transaction Script
START=$(rpm -qp --scripts "$RPM" | grep -n 'posttrans scriptlet (using /bin/sh):' | cut -d ":" -f 1)
START=$((START + 1))
SED="${START},\$p"
rpm -qp --scripts "$RPM" | sed -n "$SED" > /setup/posttransaction.sh

rm -rf "$RPM"

cp "/home/ec2-user/startup.sh" "/setup/couchbase-startup.sh"
rm -rf "/home/ec2-user/startup.sh"

chmod +x /setup/couchbase-startup.sh

# https://serverfault.com/questions/871328/start-service-after-aws-user-data-has-run
# seeing a reboot in the middle of run by cloud-init.  So this is an attempt to run
# after cloud-init
cat << _EOF > /etc/systemd/system/cb-server-startup.service
[Unit]
Description=Couchbase Server intialization script
After=cloud-final.service

[Service]
ExecStart=/setup/couchbase-startup.sh
Type=oneshot
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
_EOF

chmod 664 /etc/systemd/system/cb-server-startup.service
systemctl daemon-reload
systemctl enable cb-server-startup.service
