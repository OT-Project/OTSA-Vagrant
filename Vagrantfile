# Repository URL to clone OT-SA-Core from (can be overridden via environment variable)
$core_clone_url = ENV.fetch('CORE_CLONE_URL', 'https://github.com/OT-Project/OT-Security-Appliance.git')

# Auto-clone OT-SA-Core repository if it doesn't exist on the host
core_dir = File.expand_path('../OT-SA-Core', __dir__)
if File.directory?(core_dir)
  puts "==> Found existing OT-SA-Core repository at #{core_dir}"
else
  puts "==> OT-SA-Core directory not found. Cloning from #{$core_clone_url} to #{core_dir}..."
  system("git clone #{$core_clone_url} #{core_dir}")
end

Vagrant.configure(2) do |config|

  #
  # General settings
  #

  $opnsense_release = '26.1'                    # Which OPNsense release to install
  $virtual_machine_ip = '192.168.56.56'
  $vagrant_mount_path = '/var/vagrant'          # Shared path for development environment
  $repo_base_url = ENV.fetch('REPO_BASE_URL', 'https://repo.kamiyuri.dev')  # Custom package repository
  $core_repository = ENV.fetch('CORE_REPOSITORY', 'OT-SA-Core') # GitHub repository name for Core code
  $core_branch = ENV.fetch('CORE_BRANCH', 'dev') # Branch to pull down for Core code
  $opnsense_pin_version = ENV.fetch('OPNSENSE_PIN_VERSION', '26.1') # Lock to a specific version instead of updating

  #
  # Box configuration - using local box file
  #
  config.vm.box = "BKCS-OT/FreeBSD-14.3"

  config.vm.synced_folder '.', '/vagrant', id: 'vagrant-root', disabled: true
  config.vm.synced_folder '.', "#{$vagrant_mount_path}", type: 'nfs', nfs_udp: false
  config.vm.synced_folder '../OT-SA-Core', '/usr/core', type: 'nfs', nfs_udp: false

  config.ssh.shell = '/bin/sh'
  config.ssh.keep_alive = true

  config.vm.boot_timeout = 6000

  # Configure private networks - LAN (static), OPT1 (dhcp), OPT2 (dhcp)
  config.vm.network 'private_network', ip: $virtual_machine_ip, auto_config: false
  config.vm.network "private_network", type: "dhcp"
  config.vm.network "private_network", type: "dhcp"

  #
  # Libvirt provider configuration
  #
  config.vm.provider :libvirt do |lv|
    lv.memory = 8192
    lv.cpus = 16
    lv.disk_bus = 'virtio'
    lv.nic_model_type = 'virtio'
    lv.machine_virtual_size = 64  # Disk size in GB
    
    # Increase connection timeout
    lv.connect_via_ssh = false
  end

  #
  # VirtualBox provider configuration
  #
  config.vm.provider :virtualbox do |vb|
    vb.memory = 8192
    vb.cpus = 16
    vb.customize ['modifyvm', :id, '--nictype1', 'virtio']
    vb.customize ['modifyvm', :id, '--nictype2', 'virtio']
    vb.customize ['modifyvm', :id, '--nictype3', 'virtio']
    vb.customize ['modifyvm', :id, '--nictype4', 'virtio']
    
    # Disk size (requires vagrant-disksize plugin)
    # vagrant plugin install vagrant-disksize
    config.disksize.size = '64GB'
  end

  #
  # Install rsync first for VirtualBox (runs only if virtualbox is selected)
  #
  config.vm.provider :virtualbox do |vb, override|
    override.vm.provision 'shell', inline: <<-SHELL
      pkg install -y rsync
    SHELL
  end

  #
  # Bootstrap OPNsense
  #

  config.vm.provision "file", source: "files", destination: "files"

  config.vm.provision "shell", env: {
    "REPO_BASE_URL" => $repo_base_url,
    "OPNSENSE_RELEASE" => $opnsense_release,
    "VIRTUAL_MACHINE_IP" => $virtual_machine_ip,
    "CORE_REPOSITORY" => $core_repository,
    "CORE_BRANCH" => $core_branch,
    "OPNSENSE_PIN_VERSION" => $opnsense_pin_version
  }, path: "bootstrap.sh"
end
