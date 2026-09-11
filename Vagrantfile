# OT-SA entry point — dispatch only. Do NOT put settings here.
#
#   Shared configuration     -> vagrant/common.rb
#   Provider-specific config -> vagrant/<provider>.rb
#
# Use:  vagrant up                             # libvirt/KVM (default)
#       OTSA_PROVIDER=virtualbox vagrant up

provider = ENV.fetch('OTSA_PROVIDER', 'libvirt').downcase
provider = 'libvirt'    if provider == 'kvm'
provider = 'virtualbox' if provider == 'vbox'
unless %w[libvirt virtualbox].include?(provider)
  abort "==> Unknown OTSA_PROVIDER=#{provider.inspect}. Expected: libvirt | virtualbox"
end

# The provider file must load first: it defines otsa_wan_network and
# otsa_provider_config, which otsa_common calls.
require_relative "vagrant/#{provider}"
require_relative 'vagrant/common'

# Make `OTSA_PROVIDER=virtualbox vagrant up` select VirtualBox without also
# having to pass --provider=.
ENV['VAGRANT_DEFAULT_PROVIDER'] ||= provider

Vagrant.configure(2) { |config| otsa_common(config) }
