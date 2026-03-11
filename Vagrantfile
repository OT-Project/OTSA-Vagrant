Vagrant.configure(2) do |config|

  #
  # General settings
  #

  $opnsense_release = '26.1'                    # Which OPNsense release to install
  $virtual_machine_ip = '192.168.56.56'
  $vagrant_mount_path = '/var/vagrant'          # Shared path for development environment
  $repo_base_url = 'https://repo.kamiyuri.dev'  # Custom package repository

  #
  # Box configuration - using local box file
  #
  config.vm.box = "BKCS-OT/FreeBSD-14.3"

  config.vm.synced_folder '.', '/vagrant', id: 'vagrant-root', disabled: true
  config.vm.synced_folder '.', "#{$vagrant_mount_path}", type: 'nfs', nfs_udp: false

  config.ssh.shell = '/bin/sh'
  config.ssh.keep_alive = true

  config.vm.boot_timeout = 6000

  # Configure private network - this creates the LAN interface
  config.vm.network 'private_network', ip: $virtual_machine_ip, auto_config: false
  config.vm.network "private_network", type: "dhcp"
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
    "VIRTUAL_MACHINE_IP" => $virtual_machine_ip
  }, path: "bootstrap.sh"
end
