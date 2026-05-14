# OT-Project: OPNsense Development Environment

Welcome to the **OT-Project** Vagrant-based OPNsense development environment. This environment automates the bootstrapping, networking, and configuration required to locally test and develop features for the OT-Project's OPNsense ecosystem.

<details>
<summary><strong>Table of Contents</strong></summary>

- [Overview](#overview)
- [Architecture & Bootstrapping Mechanism](#architecture--bootstrapping-mechanism)
- [Prerequisites](#prerequisites)
- [Environment Configuration](#environment-configuration)
- [Deployment (Getting Started)](#deployment-getting-started)
- [Access and Workflow](#access-and-workflow)
- [Troubleshooting & Maintenance](#troubleshooting--maintenance)
</details>

---

## Overview

The primary goal of this Vagrant environment is to abstract away the complexity of configuring a reliable, isolated FreeBSD-based OPNsense instance for software development. By using either VirtualBox or Libvirt (KVM) as the provider, developers receive a uniform testing environment regardless of their host system OS.

## Architecture & Bootstrapping Mechanism

This environment utilizes a layered deployment architecture:
1. **Base OS:** Provisions a plain `BKCS-OT/FreeBSD-14.3` Vagrant box.
2. **Bootstrapping Script:** The `Vagrantfile` automatically downloads and executes `bootstrap.sh`.
3. **Core Sync:** The script targets the `main` branch of `OT-Project/OT-SA-Core`.
4. **Mirror Configurations:** By default, packages and dependencies are fetched from `repo.kamiyuri.dev`.

Upon completion of the bootstrap script, the VM configures necessary network interfaces, enables SSH by default, and reboots into a fully functional OPNsense gateway.

## Prerequisites

Before beginning, ensure the following tools are installed on your host machine:

### Universal Requirements
- [Vagrant](https://www.vagrantup.com) (>= `2.3.4`)

### Provider-Specific Requirements

**For VirtualBox Users:**
- [VirtualBox](https://www.virtualbox.org) (>= `7.0.4`)
- The `vagrant-disksize` plugin:
  ```bash
  vagrant plugin install vagrant-disksize
  ```

**For Libvirt (KVM) Users:**
- The `vagrant-libvirt` plugin:
  ```bash
  vagrant plugin install vagrant-libvirt
  ```

## Environment Configuration

Environment variables modifying the behavior of the Vagrant deployment are defined at the top of each provider-specific Vagrantfile (`Vagrantfile.libvirt` and `Vagrantfile.virtualbox` — they share the same set of variables). Keep both files in sync when adding or renaming a variable.

| Variable | Description | Default Value |
| --- | --- | --- |
| `$opnsense_release` | The target OPNsense version. | `26.1` |
| `$virtual_machine_ip` | The fixed IP address assigned to the LAN interface. | `192.168.56.56` |
| `$otsa_mirror_url` | Base URL of the OTSA package mirror (override via `OTSA_MIRROR_URL=...`). Passed to `opnsense-bootstrap -m` so the appliance writes it into `/usr/local/etc/pkg/repos/OPNsense.conf` during provisioning. Leave empty to keep upstream defaults. | `https://repo.kamiyuri.dev` |
| `$opnsense_pin_version` | Option to lock the installation to a specific release version (e.g., `26.1`), preventing automatic bootstrapping to newer rolling patches (`26.1.x`). | `26.1` |
| `$core_repository` | Name of the GitHub repository containing the core code under the OT-Project org. | `OT-SA-Core` |
| `$core_branch` | Explicit branch or tag name of the core code repository to fetch. | `dev` |
| `$core_clone_url` | Explicit URL to clone the `OT-SA-Core` repository if not presented in the host. | `https://github.com/OT-Project/OT-SA-Core.git` |
| `$vagrant_mount_path` | Absolute path inside the VM mapped to the host directory. | `/var/vagrant` |

### Network Topology

The virtual machine is provisioned with 4 network interfaces (`virtio`) to simulate a robust firewall setup:
1. **WAN (NAT/Management):** Bound to Vagrant's default connection to fetch external packages.
2. **LAN (Host-Only/Private):** Fixed IP (`192.168.56.56`) used for accessing the Web UI.
3. **OPT1 (Private DHCP):** Reserved for custom internal routing and testing.
4. **OPT2 (Private DHCP):** Reserved for custom internal routing and testing.

* **VirtualBox:** LAN relies on the host-only IP range `192.168.56.0/21`. Avoid using `.1`, as it is reserved. 
* **Libvirt:** Provisions a dedicated management network (`vagrant-libvirt`) separate from the LAN traffic payload.

## Deployment (Getting Started)

The repository now ships **two provider-specific Vagrantfiles**:

| File                       | Provider     |
| -------------------------- | ------------ |
| `Vagrantfile.libvirt`      | Libvirt/KVM  |
| `Vagrantfile.virtualbox`   | VirtualBox   |

A thin `Vagrantfile` chooser sits on top and picks one of the two based on the `OTSA_PROVIDER` environment variable (default: `libvirt`).

**Deploy via Libvirt (KVM) — default:**
```bash
vagrant up
# or, equivalently:
OTSA_PROVIDER=libvirt vagrant up
```

**Deploy via VirtualBox:**
```bash
OTSA_PROVIDER=virtualbox vagrant up
```

**Bypass the chooser entirely** (useful if you want CI scripts to be explicit):
```bash
VAGRANT_VAGRANTFILE=Vagrantfile.libvirt    vagrant up --provider=libvirt
VAGRANT_VAGRANTFILE=Vagrantfile.virtualbox vagrant up --provider=virtualbox
```

> **Note**: During the initial deployment, the virtual machine will gracefully halt itself after the bootstrap completes. **You must issue a second `vagrant up`** immediately afterward to bring the instance back online.
>
> **Switching providers on an existing checkout:** Vagrant stores per-machine state under `.vagrant/`. If you previously ran `vagrant up` with one provider and switch to the other, run `vagrant destroy -f` first or you will see provider-mismatch errors.

## Access and Workflow

Once the deployment sequence is finalized and the VM is running, you can access the instance locally.

### Web Administration UI
- **URL**: [https://192.168.56.56](https://192.168.56.56)
- **Default Username**: `root`
- **Default Password**: `opnsense`

### SSH Access
To securely gain terminal access to the appliance:

```bash
vagrant ssh
```

Root-level access (`sudo`) via the `vagrant` user requires no password prompt by default.

### Development Workflow
The root of this project folder is actively mirrored into the OPNsense VM at `/var/vagrant`. This allows developers to edit scripts, repositories, and configurations comfortably on their host machine and instantly evaluate changes inside the VM's active environment.

Additionally, if an adjacent `../OT-SA-Core` repository directory does not exist on the host, the `Vagrantfile` will automatically clone it over via `$core_clone_url` (which can be overridden with the `CORE_CLONE_URL` environment variable). The system then sets up an NFS synced folder bridging `../OT-SA-Core` to `/usr/core` within the VM, ensuring seamless cross-environment software development.

## Troubleshooting & Maintenance

**Changing the LAN IP Configuration**
If `192.168.56.56` collides with your local infrastructure:
1. Turn off the active instance: `vagrant halt`.
2. Modify `$virtual_machine_ip` in `Vagrantfile.libvirt` **and** `Vagrantfile.virtualbox` (they must stay in sync).
3. Restart the environment: `vagrant up`.
4. Access the web interface using the newly assigned IP address.

**System Rebuilds**
To completely destroy the environment and re-sync from scratch, execute:
```bash
vagrant destroy -f
OTSA_PROVIDER=<libvirt|virtualbox> vagrant up
```

---
*Maintained by the OT-Project Development Team.*
