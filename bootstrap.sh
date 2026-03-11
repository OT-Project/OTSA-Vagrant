#!/bin/sh

# Download the OPNsense bootstrap script from our fork
fetch -o opnsense-bootstrap.sh https://raw.githubusercontent.com/OT-Project/OT-SA-Update/main/src/bootstrap/opnsense-bootstrap.sh.in

# Remove reboot command from bootstrap script
sed -i '' -e '/reboot$/d' opnsense-bootstrap.sh

# Start bootstrap with custom mirror and our core fork
#   -A OT-Project      = fetch core from github.com/OT-Project/${CORE_REPOSITORY}
#   -R ...             = core repository name
#   -B ...             = use branch instead of stable/<release>
#   -m <url>           = use custom package mirror + add otsa repo
#   -r <release>       = target OPNsense release
OPTS="-y"

env CORE_PHP=84 CORE_PYTHON=312 sh ./opnsense-bootstrap.sh \
  -A OT-Project \
  -R ${CORE_REPOSITORY:-OT-SA-Core} \
  -B ${CORE_BRANCH:-main} \
  -m ${REPO_BASE_URL} \
  -r ${OPNSENSE_RELEASE} \
  ${OPTS}

# =============================================
# Configure network interfaces
# =============================================

# Set correct interface names for libvirt/virtio
# libvirt uses vtnet0 (management), vtnet1 (LAN)
sed -i '' -e 's/mismatch0/vtnet1/' /usr/local/etc/config.xml
sed -i '' -e 's/mismatch1/vtnet0/' /usr/local/etc/config.xml

# Remove IPv6 configuration from WAN
sed -i '' -e '/<ipaddrv6>dhcp6<\/ipaddrv6>/d' /usr/local/etc/config.xml

# Remove IPv6 configuration from LAN
sed -i '' -e '/<ipaddrv6>track6<\/ipaddrv6>/d' /usr/local/etc/config.xml
sed -i '' -e '/<subnetv6>64<\/subnetv6>/d' /usr/local/etc/config.xml
sed -i '' -e '/<track6-interface>wan<\/track6-interface>/d' /usr/local/etc/config.xml
sed -i '' -e '/<track6-prefix-id>0<\/track6-prefix-id>/d' /usr/local/etc/config.xml

# Change OPNsense LAN IP addresses
sed -i '' -e "s/192\.168\.1\.1</${VIRTUAL_MACHINE_IP}</" /usr/local/etc/config.xml

# Change DHCP range to match LAN IP address
lan_net=$(echo "${VIRTUAL_MACHINE_IP}" | sed 's/\.[0-9]*$//')
sed -i '' -e "s/192\.168\.1\./${lan_net}./" /usr/local/etc/config.xml

# =============================================
# Configure SSH and user access
# =============================================

# Enable SSH by default
sed -i '' -e '/<group>admins<\/group>/r files/ssh.xml' /usr/local/etc/config.xml

# Allow SSH on all interfaces
sed -i '' -e '/<filter>/r files/filter.xml' /usr/local/etc/config.xml

# Do not block private networks on WAN
sed -i '' -e '/<blockpriv>1<\/blockpriv>/d' /usr/local/etc/config.xml

# Reset shell of Vagrant user
/usr/sbin/pw usermod vagrant -s /bin/sh

# Create XML config for Vagrant user
key=$(b64encode -r dummy <.ssh/authorized_keys | tr -d '\n')
echo "      <authorizedkeys>${key}</authorizedkeys>" >files/vagrant2.xml
cat files/vagrant[123].xml >files/vagrant.xml

# Add Vagrant user - OPNsense style
sed -i '' -e '/<\/member>/r files/admins.xml' /usr/local/etc/config.xml
sed -i '' -e '/<\/user>/r files/vagrant.xml' /usr/local/etc/config.xml

# Change home directory to group nobody
# chgrp -R nobody /usr/home/vagrant

# Change sudoers file to reference user instead of group
sed -i '' -e 's/^%//' /usr/local/etc/sudoers.d/vagrant

# Display helpful message for the user
echo '#####################################################'
echo '#                                                   #'
echo '#  OPNsense provisioning finished - shutting down.  #'
echo '#  Use `vagrant up` to start your OPNsense.         #'
echo '#                                                   #'
echo '#####################################################'

# Shutdown the system
shutdown -p now
