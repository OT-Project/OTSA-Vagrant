# OT-SA — configuration shared by every provider.
#
# Provider-specific pieces (the config.vm.provider block, the bridged-WAN
# syntax, disk resizing) live in vagrant/<provider>.rb and are reached through
# otsa_provider_config / otsa_wan_network, which the entry-point Vagrantfile
# has already loaded by the time this runs.
#
# All relative paths below resolve against the directory holding the
# Vagrantfile (the repository root), not this file.

def otsa_common(config)
  #
  # General settings
  #

  # Mode: 'official' => repo chuẩn của OPNsense, 'custom' => repo nội bộ của bạn
  $otsa_mode = ENV.fetch('OTSA_MODE', 'official').downcase
  unless %w[official custom].include?($otsa_mode)
    raise "OTSA_MODE phải là 'official' hoặc 'custom' (nhận được: '#{$otsa_mode}')"
  end
  puts "==> OTSA_MODE = #{$otsa_mode}"

  # Release đích của OPNsense. Khai báo trước $mode_defaults vì nhánh core mặc
  # định ở mode official bám theo nó (stable/<release>).
  $opnsense_release = ENV.fetch('OPNSENSE_RELEASE', '26.1')

  $mode_defaults = {
    'official' => {
      'OTSA_MIRROR_URL'   => 'https://pkg.opnsense.org',
      'CORE_ACCOUNT'      => 'opnsense',
      'CORE_REPOSITORY'   => 'core',
      'CORE_BRANCH'       => "stable/#{$opnsense_release}",
      'UPDATE_REPOSITORY' => 'update',
      'UPDATE_BRANCH'     => 'master'
    },
    'custom' => {
      'OTSA_MIRROR_URL'   => 'http://192.168.150.49',
      'CORE_ACCOUNT'      => 'OT-Project',
      'CORE_REPOSITORY'   => 'OTSA-Core',
      'CORE_BRANCH'       => 'dev',
      'UPDATE_REPOSITORY' => 'OTSA-Update',
      'UPDATE_BRANCH'     => 'main'
    }
  }[$otsa_mode]

  # ENV vẫn override được từng giá trị riêng lẻ, mode chỉ quyết định mặc định
  otsa_env = ->(key) { ENV.fetch(key, $mode_defaults[key]) }

  $virtual_machine_ip     = '192.168.56.56'
  $vagrant_mount_path     = '/var/vagrant'
  $otsa_mirror_url        = otsa_env.call('OTSA_MIRROR_URL')
  $core_account           = otsa_env.call('CORE_ACCOUNT')
  $core_repository        = otsa_env.call('CORE_REPOSITORY')
  $core_branch            = otsa_env.call('CORE_BRANCH')
  $update_repository      = otsa_env.call('UPDATE_REPOSITORY')
  $update_branch          = otsa_env.call('UPDATE_BRANCH')
  $opnsense_pin_version   = ENV.fetch('OPNSENSE_PIN_VERSION', '26.1')
  $wan_bridge_dev         = ENV.fetch('OTSA_WAN_BRIDGE', '')

  # URL to clone the core repository from (defaults derived from $core_account/$core_repository)
  $core_clone_url = ENV.fetch(
    'CORE_CLONE_URL',
    "https://github.com/#{$core_account}/#{$core_repository}.git"
  )

  # URL to fetch the opnsense-bootstrap.sh.in script from (defaults derived from update repo)
  $bootstrap_script_url = ENV.fetch(
    'BOOTSTRAP_SCRIPT_URL',
    "https://raw.githubusercontent.com/#{$core_account}/#{$update_repository}/#{$update_branch}/src/bootstrap/opnsense-bootstrap.sh.in"
  )

  # Auto-clone core repository if it doesn't exist on the host.
  # __dir__ is vagrant/, so the sibling of the repository root is two levels up.
  core_dir = File.expand_path("../../#{$core_repository}", __dir__)
  if File.directory?(core_dir)
    puts "==> Found existing #{$core_repository} repository at #{core_dir}"
  else
    puts "==> #{$core_repository} directory not found. Cloning from #{$core_clone_url} to #{core_dir}..."
    system("git clone #{$core_clone_url} #{core_dir}")
  end

  #
  # Box configuration
  #
  config.vm.box = "BKCS-OT/FreeBSD-14.3"

  # Disable the default /vagrant share; mount our own via NFS.
  # (vboxsf doesn't work on FreeBSD; rsync wouldn't reflect host edits live.)
  # NFS over VirtualBox requires a host NFS server and may prompt for sudo on
  # `vagrant up`.
  config.vm.synced_folder '.', '/vagrant', id: 'vagrant-root', disabled: true
  config.vm.synced_folder '.', "#{$vagrant_mount_path}", type: 'nfs', nfs_udp: false
  config.vm.synced_folder "../#{$core_repository}", "#{$vagrant_mount_path}/core", type: 'nfs', nfs_udp: false

  config.ssh.shell      = '/bin/sh'
  config.ssh.keep_alive = true
  config.vm.boot_timeout = 6000

  # Hide .git directories inside NFS mounts (overmount with empty tmpfs)
  config.vm.provision "shell", run: "always", inline: <<-SHELL
    for gitdir in #{$vagrant_mount_path}/.git #{$vagrant_mount_path}/core/.git; do
      if [ -d "$gitdir" ]; then
        mount -t tmpfs tmpfs "$gitdir"
      fi
    done
  SHELL

  #
  # Network — LAN (static), WAN (bridge), OPT (dhcp), OPT (dhcp)
  #
  # Declaration order IS the guest interface order, and bootstrap.sh hardcodes
  # that mapping (vtnet1=LAN, vtnet2=WAN, vtnet3/4=OPT). Do not reorder.
  # Both providers attach their own management NAT ahead of these as vtnet0;
  # bootstrap.sh wires it into OPNsense as OPT1 "MGMT".
  #
  config.vm.network 'private_network', ip: $virtual_machine_ip, auto_config: false
  otsa_wan_network(config, $wan_bridge_dev)
  config.vm.network 'private_network', type: 'dhcp'
  config.vm.network 'private_network', type: 'dhcp'

  #
  # Provider-specific configuration (vagrant/<provider>.rb)
  #
  otsa_provider_config(config)

  #
  # Bootstrap OPNsense
  #
  config.vm.provision "file",  source: "files", destination: "files"

  config.vm.provision "shell", env: {
    "OTSA_MODE"            => $otsa_mode,
    "OTSA_MIRROR_URL"      => $otsa_mirror_url,
    "OPNSENSE_RELEASE"     => $opnsense_release,
    "VIRTUAL_MACHINE_IP"   => $virtual_machine_ip,
    "CORE_ACCOUNT"         => $core_account,
    "CORE_REPOSITORY"      => $core_repository,
    "CORE_BRANCH"          => $core_branch,
    "BOOTSTRAP_SCRIPT_URL" => $bootstrap_script_url,
    "OPNSENSE_PIN_VERSION" => $opnsense_pin_version
  }, path: "bootstrap.sh"
end
