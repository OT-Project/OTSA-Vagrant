#!/bin/sh

set -e

# All configuration is supplied by the Vagrantfile via environment variables.
# Fail fast if invoked standalone without those vars set.
: "${BOOTSTRAP_SCRIPT_URL:?BOOTSTRAP_SCRIPT_URL must be set (run via Vagrant or export it manually)}"
: "${CORE_ACCOUNT:?CORE_ACCOUNT must be set}"
: "${CORE_REPOSITORY:?CORE_REPOSITORY must be set}"
: "${CORE_BRANCH:?CORE_BRANCH must be set}"
: "${OPNSENSE_RELEASE:?OPNSENSE_RELEASE must be set}"
: "${VIRTUAL_MACHINE_IP:?VIRTUAL_MACHINE_IP must be set}"

# Download the OPNsense bootstrap script from the update repo
fetch -o opnsense-bootstrap.sh "${BOOTSTRAP_SCRIPT_URL}"

# Remove reboot command from bootstrap script
sed -i '' -e '/reboot$/d' opnsense-bootstrap.sh

# Source the core repo from the NFS-mounted host copy instead of GitHub.
# Background: GitHub serves the archive tarball with chunked transfer-encoding,
# so FreeBSD's `fetch` cannot verify the final size and has been observed to
# silently truncate over slow links - tar then fails mid-extraction and the
# rest of the bootstrap runs against a half-applied state. The host already
# bind-mounts the core checkout at /var/vagrant/core, so build the tarball
# from that and patch the upstream script to copy it in place.
if [ -d /var/vagrant/core ]; then
    LOCAL_CORE_TARBALL=/tmp/otsa-core-local.tar.gz
    echo "==> Building ${CORE_REPOSITORY}.tar.gz from /var/vagrant/core (skipping GitHub fetch)"
    tar -C /var/vagrant -cf "${LOCAL_CORE_TARBALL}" \
        -s "|^core/|${CORE_REPOSITORY}-${CORE_BRANCH}/|" \
        -s "|^core\$|${CORE_REPOSITORY}-${CORE_BRANCH}|" \
        core
    tar -tf "${LOCAL_CORE_TARBALL}" >/dev/null
    # Replace both `fetch -o ${WORKDIR}/${REPOSITORY}.tar.gz ...` invocations in
    # the upstream bootstrap with a `cp` from the locally-built tarball. The
    # ${WORKDIR}/${REPOSITORY} placeholders remain shell-expanded by the
    # upstream script at run-time.
    sed -i '' \
        -e "s@fetch -o \${WORKDIR}/\${REPOSITORY}\.tar\.gz \"[^\"]*\"@cp ${LOCAL_CORE_TARBALL} \${WORKDIR}/\${REPOSITORY}.tar.gz@" \
        opnsense-bootstrap.sh
fi

# Start bootstrap with custom mirror and our core fork
#   -A <account>       = fetch core from github.com/<account>/${CORE_REPOSITORY}
#   -R ...             = core repository name
#   -B ...             = use branch instead of stable/<release>
#   -m <url>           = use custom package mirror + add otsa repo
#   -r <release>       = target OPNsense release
OPTS="-y"
if [ -n "${OTSA_MIRROR_URL}" ]; then
  OPTS="${OPTS} -m ${OTSA_MIRROR_URL}"
fi
if [ -n "${OPNSENSE_PIN_VERSION}" ]; then
  OPTS="${OPTS} -p ${OPNSENSE_PIN_VERSION}"
fi

env CORE_PHP=84 CORE_PYTHON=312 sh ./opnsense-bootstrap.sh \
  -A "${CORE_ACCOUNT}" \
  -R "${CORE_REPOSITORY}" \
  -B "${CORE_BRANCH}" \
  -r "${OPNSENSE_RELEASE}" \
  ${OPTS}

# Bail out early if the bootstrap above didn't actually install OPNsense.
# Without this, the rest of the script silently runs sed against a missing
# config.xml and the VM halts in a half-provisioned state.
if [ ! -f /usr/local/etc/config.xml ]; then
    echo "FATAL: /usr/local/etc/config.xml is missing - opnsense-bootstrap.sh failed."
    exit 1
fi

# =============================================
# Configure network interfaces
# =============================================

# Set correct interface names for libvirt/virtio.
# NIC layout (libvirt + VirtualBox both place the provider's mgmt NAT first):
#   vtnet0 = provider mgmt NAT  -> OPNsense OPT1 "MGMT" (DHCP, for `vagrant ssh`)
#   vtnet1 = LAN  static 192.168.56.56
#   vtnet2 = WAN  bridge to host's physical LAN
#   vtnet3 = OPT  dhcp playground
#   vtnet4 = OPT  dhcp playground
sed -i '' -e 's/mismatch0/vtnet1/' /usr/local/etc/config.xml
sed -i '' -e 's/mismatch1/vtnet2/' /usr/local/etc/config.xml

# Add OPNsense OPT1 ("MGMT") bound to vtnet0 so the provider's NAT lease is
# usable for `vagrant ssh` once WAN is moved off vtnet0.
sed -i '' -e '/<\/lan>/r files/opt_mgmt.xml' /usr/local/etc/config.xml

# Register a dynamic gateway on MGMT and a static route for 192.168.150.0/24
# (OTSA mirror) so it traverses the host instead of the WAN bridge.
# Replaces the trailing </opnsense> with the snippet (which itself ends in
# </opnsense>) — host_route.xml therefore must be the LAST appended file.
sed -i '' -e '/<\/opnsense>/d' /usr/local/etc/config.xml
cat files/host_route.xml >>/usr/local/etc/config.xml

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
