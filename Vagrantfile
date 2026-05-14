# OT-SA Vagrantfile — provider chooser
#
# This is a thin loader. It picks the provider-specific Vagrantfile based on the
# OTSA_PROVIDER environment variable (default: libvirt) and delegates to it.
#
# Available targets:
#   OTSA_PROVIDER=libvirt     vagrant up        (default)
#   OTSA_PROVIDER=virtualbox  vagrant up
#
# Equivalently, bypass this chooser entirely:
#   VAGRANT_VAGRANTFILE=Vagrantfile.libvirt    vagrant up --provider=libvirt
#   VAGRANT_VAGRANTFILE=Vagrantfile.virtualbox vagrant up --provider=virtualbox

provider = ENV.fetch('OTSA_PROVIDER', 'libvirt').downcase

case provider
when 'libvirt', 'kvm'
  target = File.expand_path('Vagrantfile.libvirt', __dir__)
when 'virtualbox', 'vbox'
  target = File.expand_path('Vagrantfile.virtualbox', __dir__)
else
  abort "==> Unknown OTSA_PROVIDER=#{provider.inspect}. Expected: libvirt | virtualbox"
end

unless File.exist?(target)
  abort "==> Provider Vagrantfile not found: #{target}"
end

puts "==> OT-SA chooser: loading #{File.basename(target)} (OTSA_PROVIDER=#{provider})"
load target
