# OT-Project: OPNsense Development Environment

Welcome to the **OT-Project** Vagrant-based OPNsense development environment. This environment automates the bootstrapping, networking, and configuration required to locally test and develop features for the OT-Project's OPNsense ecosystem.

<details>
<summary><strong>Table of Contents</strong></summary>

- [Overview](#overview)
- [Vagrant Primer](#vagrant-primer)
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

## Vagrant Primer

New to Vagrant? It is a command-line tool that builds a virtual machine from a text file. Instead of clicking through a hypervisor GUI and writing down the steps afterwards, you describe the machine once — in the `Vagrantfile` — and everyone runs `vagrant up` to get an identical VM.

Five terms cover almost everything used here:

| Term | What it means in this project |
| --- | --- |
| **Box** | The base image Vagrant starts from: `BKCS-OT/FreeBSD-14.3`, a plain FreeBSD install. OPNsense is layered on top afterwards. |
| **Provider** | The hypervisor that actually runs the VM — Libvirt/KVM or VirtualBox (see below). |
| **Provisioner** | A script Vagrant executes *inside* the guest after boot. Here it is [`bootstrap.sh`](bootstrap.sh), which converts the FreeBSD box into an OPNsense appliance. |
| **Synced folder** | A host directory mounted into the guest. This repository is mounted at `/var/vagrant`, so edits made on your host are visible in the VM immediately. |
| **`.vagrant/`** | Local, gitignored state: which VM belongs to this directory, which provider created it, the generated SSH key. It is managed for you — remove it through `vagrant destroy`, not by hand. |

Day-to-day lifecycle:

```bash
vagrant up          # create the VM the first time, or boot an existing one
vagrant ssh         # shell into the guest as the `vagrant` user
vagrant halt        # graceful shutdown
vagrant reload      # halt + up, picking up Vagrantfile changes
vagrant provision   # re-run bootstrap.sh on a machine that is already running
vagrant status      # is it running, and under which provider?
vagrant destroy -f  # delete the VM; the next `vagrant up` rebuilds from scratch
```

Every command is scoped to the directory holding the `Vagrantfile`, so run them from the repository root. All tuning happens through environment variables rather than CLI flags — see [Environment Configuration](#environment-configuration).

### Libvirt or VirtualBox?

A **provider** is the hypervisor Vagrant drives. The VM description is identical either way; only the plumbing differs, which is why provider-specific settings are isolated in [`vagrant/libvirt.rb`](vagrant/libvirt.rb) and [`vagrant/virtualbox.rb`](vagrant/virtualbox.rb).

| | Libvirt / KVM (default) | VirtualBox |
| --- | --- | --- |
| Host OS | Linux only | Linux, Windows, macOS (Intel) |
| Nature | Virtualization built into the Linux kernel | Standalone application installed on top of the OS |
| Performance | Faster; near-native I/O through virtio | Slower and heavier on the host |
| Required plugin | `vagrant-libvirt` | `vagrant-disksize` (otherwise the disk stays at the box default instead of 64 GB) |
| Bridged WAN | Picks an interface automatically, or set `OTSA_WAN_BRIDGE` | Prompts you to choose one unless `OTSA_WAN_BRIDGE` is set |
| Management network | Dedicated network, kept separate from WAN traffic | NAT adapter attached as the first NIC |

Choose Libvirt on Linux: it is the default and the better-tested path here. Choose VirtualBox on Windows or macOS, or wherever KVM is unavailable — for instance inside a VM that does not expose nested virtualization. Select it per command with `PROVIDER=virtualbox vagrant up`.

The two cannot share state: `.vagrant/` records which provider built the machine, so switching providers requires `vagrant destroy -f` first.

## Architecture & Bootstrapping Mechanism

This environment utilizes a layered deployment architecture:
1. **Base OS:** Provisions a plain `BKCS-OT/FreeBSD-14.3` Vagrant box.
2. **Bootstrapping Script:** Vagrant provisions this repository's `bootstrap.sh` inside the guest. That script downloads `opnsense-bootstrap.sh.in` from `$bootstrap_script_url` — upstream `opnsense/update` in `official` mode, the `OT-Project/OTSA-Update` fork in `custom` mode — and runs it.
3. **Core Sync:** The script targets the `stable/<release>` branch of `opnsense/core` by default (`stable/26.1`; `OTSA_MODE=custom` switches this to the `dev` branch of `OT-Project/OTSA-Core`). The host checkout is NFS-mounted at `/var/vagrant/core` and repacked locally instead of fetched from GitHub, so the tarball top-level directory mirrors GitHub naming: slashes in the branch become dashes (`stable/26.1` -> `core-stable-26.1`).
4. **Mirror Configurations:** By default, packages and dependencies are fetched from upstream `https://pkg.opnsense.org`; in `custom` mode they come from the internal mirror at `http://192.168.150.49`.

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

Shared configuration lives in a single file, [`vagrant/common.rb`](vagrant/common.rb). Provider-specific settings live in [`vagrant/libvirt.rb`](vagrant/libvirt.rb) and [`vagrant/virtualbox.rb`](vagrant/virtualbox.rb); the root `Vagrantfile` only dispatches between them and holds no settings.

### Deployment mode

`OTSA_MODE` selects a **set of defaults** for the repositories and package mirror. Individual variables can still be overridden one by one — the mode only decides what they fall back to.

**`official` — a stock upstream appliance.** Core sources come from the public `opnsense/core` repository, the bootstrap script from `opnsense/update`, and packages from `pkg.opnsense.org`. Nothing internal is involved, so it works from any network. Use it as a clean reference point: reproducing a bug against unmodified OPNsense, or checking how a stock install behaves before the OT-Project changes are applied.

**`custom` — the OT-Project appliance.** Core sources come from the internal fork `OT-Project/OTSA-Core` (branch `dev`), the bootstrap script from `OT-Project/OTSA-Update` (branch `main`), and packages from the internal mirror at `192.168.150.49`. This mode also injects a static route so that mirror subnet is reached through the host rather than the bridged WAN (see *Host-routed subnet* below). It is the mode for day-to-day work on the project's own code, and it requires reachability to the mirror — directly on the office LAN, or from home through the host's `bkcs` Wireguard tunnel.

Which to pick: `custom` if you are developing OT-Project features, `official` if you need a vanilla OPNsense to compare against. The mode is only a bundle of defaults, so a single value can still be overridden on top of it, e.g. `OTSA_MODE=custom CORE_BRANCH=feature/xyz vagrant up`.

| Variable | `official` (default) | `custom` |
| --- | --- | --- |
| `OTSA_MIRROR_URL` | `https://pkg.opnsense.org` | `http://192.168.150.49` |
| `CORE_ACCOUNT` | `opnsense` | `OT-Project` |
| `CORE_REPOSITORY` | `core` | `OTSA-Core` |
| `CORE_BRANCH` | `stable/<release>` (`stable/26.1`) | `dev` |
| `UPDATE_REPOSITORY` | `update` | `OTSA-Update` |
| `UPDATE_BRANCH` | `master` | `main` |

```bash
vagrant up                      # official — upstream OPNsense
OTSA_MODE=custom vagrant up     # internal OTSA repositories + mirror
```

`custom` mode additionally injects the host-routed mirror subnet described below.

> **Known limitation — bootstrap flags in `official` mode.** `bootstrap.sh` calls `opnsense-bootstrap.sh` with `-B <branch>`, `-m <mirror>` and `-p <pin>`. Those three options exist **only** in the OT-Project fork (`OT-Project/OTSA-Update`, getopts `A:a:bB:fim:p:qr:R:t:U:vVyz`); upstream `opnsense/update` has no `-m`/`-p` and parses `-B` as a no-argument *bare* flag (getopts `A:a:Bbfiqr:R:t:vVyz`). Since `official` mode downloads the upstream script, `getopts` stops at the operand following `-B` and silently discards `-r`, `-y`, `-m` and `-p`: `RELEASE` keeps its `%%RELEASE%%` placeholder and bare mode is switched on by accident.
>
> Practical consequence: `CORE_BRANCH`, `OTSA_MIRROR_URL` and `OPNSENSE_PIN_VERSION` take effect in `custom` mode only. Upstream already targets `stable/${RELEASE}` on its own, so the smallest fix is to stop passing `-B`/`-m`/`-p` when `OTSA_MODE=official`.

### Individual variables

| Variable | Description | Default Value |
| --- | --- | --- |
| `PROVIDER` | Virtualization provider, read by the entry-point `Vagrantfile`: `libvirt` (alias `kvm`) or `virtualbox` (alias `vbox`). Any other value aborts `vagrant up`. | `libvirt` |
| `$otsa_mode` | Deployment mode, `official` or `custom` (see table above). Override via `OTSA_MODE=...`. | `official` |
| `$opnsense_release` | The target OPNsense version, passed to `opnsense-bootstrap -r`. Override via `OPNSENSE_RELEASE=...`. | `26.1` |
| `$virtual_machine_ip` | The fixed IP address assigned to the LAN interface. | `192.168.56.56` |
| `$otsa_mirror_url` | Base URL of the package mirror (override via `OTSA_MIRROR_URL=...`). Passed to `opnsense-bootstrap -m` so the appliance writes it into `/usr/local/etc/pkg/repos/OPNsense.conf` during provisioning. The bootstrap script appends `/${ABI}/${RELEASE}/latest` (or `…/MINT/${PIN}/latest` when pinned), so set this to the **root** of the mirror, not the full repo path. Leave empty to keep upstream defaults. ⚠️ `custom` mode only — see the note above. | mode-dependent |
| `$opnsense_pin_version` | Option to lock the installation to a specific release version (e.g., `26.1`), preventing automatic bootstrapping to newer rolling patches (`26.1.x`). Override via `OPNSENSE_PIN_VERSION=...`; set it empty to drop the `-p` flag entirely. ⚠️ `custom` mode only — see the note above. | `26.1` |
| `$core_account` | GitHub organization that owns the core repository. Used to build `$core_clone_url` and passed to `opnsense-bootstrap -A`. Override via `CORE_ACCOUNT=...`. | mode-dependent |
| `$core_repository` | Name of the GitHub repository containing the core code under `$core_account`. Override via `CORE_REPOSITORY=...`. | mode-dependent |
| `$core_branch` | Explicit branch or tag name of the core code repository to fetch, passed to `opnsense-bootstrap -B`. In `official` mode it tracks `stable/$opnsense_release`. Override via `CORE_BRANCH=...`. ⚠️ `custom` mode only — see the note above. | mode-dependent |
| `$core_clone_url` | Explicit URL to clone the core repository if not present on the host. Defaults to `https://github.com/$core_account/$core_repository.git`. Override via `CORE_CLONE_URL=...`. | derived |
| `$update_repository` | GitHub repository under `$core_account` that contains `src/bootstrap/opnsense-bootstrap.sh.in`. Override via `UPDATE_REPOSITORY=...`. | mode-dependent |
| `$update_branch` | Branch of `$update_repository` to fetch the bootstrap script from. Override via `UPDATE_BRANCH=...`. | mode-dependent |
| `$bootstrap_script_url` | Absolute URL of `opnsense-bootstrap.sh.in`. Defaults to the `raw.githubusercontent.com` URL derived from `$core_account`, `$update_repository`, and `$update_branch`. Set this when you want to mirror the bootstrap script on an internal HTTP server. Override via `BOOTSTRAP_SCRIPT_URL=...`. | derived |
| `$vagrant_mount_path` | Absolute path inside the VM mapped to the host directory. | `/var/vagrant` |
| `$wan_bridge_dev` | Host interface that the WAN NIC bridges onto (e.g. `eth0`, `wlan0`, `br0`). Override via `OTSA_WAN_BRIDGE=...`. Leave empty to let libvirt auto-select / VirtualBox prompt at `vagrant up`. | empty |

### Network Topology

The virtual machine is provisioned with 5 `virtio` network interfaces. Guest interface order is the same for both providers (provider-managed NAT first, then Vagrantfile declarations in order):

| Guest NIC | Role     | Provided by                                                 |
| --------- | -------- | ----------------------------------------------------------- |
| `vtnet0`  | **MGMT** | Provider-managed NAT (libvirt `vagrant-libvirt` / VBox NAT) — `vagrant ssh` lands here; wired into OPNsense as OPT1 "MGMT" (DHCP). |
| `vtnet1`  | **LAN**  | Host-only/private network, static `192.168.56.56`. Web UI lives here. |
| `vtnet2`  | **WAN**  | Bridge to the host's physical LAN (`public_network`). Override the bridge device with `OTSA_WAN_BRIDGE=<iface>`. Receives DHCP from the upstream LAN — reachable from other machines on that LAN. |
| `vtnet3`  | OPT      | Private DHCP. Reserved for custom internal routing and testing. |
| `vtnet4`  | OPT      | Private DHCP. Reserved for custom internal routing and testing. |

* **VirtualBox:** LAN relies on the host-only IP range `192.168.56.0/21`. Avoid using `.1`, as it is reserved. If `OTSA_WAN_BRIDGE` is unset, VirtualBox will prompt interactively for the bridge interface.
* **Libvirt:** Keeps the dedicated management network (`vagrant-libvirt`) separate from WAN traffic — `vagrant ssh` always uses the management NAT, never the bridged WAN.

#### Host-routed subnet (OTSA mirror at `192.168.150.0/24`) — `custom` mode only

The OTSA package mirror lives at `192.168.150.49`, reachable two different ways depending on where the host is:

- **At the office:** directly on the host's physical LAN.
- **At home:** only through the host's Wireguard `bkcs` tunnel.

In both cases the host has a working route; the VM does not. To make the VM use the host as next hop regardless of location, `bootstrap.sh` injects a static route `192.168.150.0/24 → MGMT_GW` from [`files/mirror_route.xml`](files/mirror_route.xml). Default Internet traffic still egresses via the bridged WAN; only the mirror subnet is forced through the management NAT. Swap the subnet by editing that file if your mirror moves.

This route is only injected when `OTSA_MODE=custom`. In `official` mode packages come from `pkg.opnsense.org` over the WAN, so no host-routed subnet is needed. The `MGMT_GW` gateway itself ([`files/mgmt_gw.xml`](files/mgmt_gw.xml)) is registered in **both** modes, since it backs the management NAT that `vagrant ssh` uses.

## Deployment (Getting Started)

The repository layout:

| File                      | Role                                                          |
| ------------------------- | ------------------------------------------------------------- |
| `Vagrantfile`             | Entry point. Dispatch only — selects the provider, no settings. |
| `vagrant/common.rb`       | All configuration shared by every provider.                     |
| `vagrant/libvirt.rb`      | Libvirt/KVM provider block and bridged-WAN syntax.              |
| `vagrant/virtualbox.rb`   | VirtualBox provider block, virtio NICs, disk resizing.          |

`Vagrantfile` picks the provider from the `PROVIDER` environment variable (default: `libvirt`; `kvm` and `vbox` are accepted aliases) and sets `VAGRANT_DEFAULT_PROVIDER` accordingly, so no `--provider=` flag is needed.

**Deploy via Libvirt (KVM) — default:**
```bash
vagrant up
# or, equivalently:
PROVIDER=libvirt vagrant up
```

**Deploy via VirtualBox:**
```bash
PROVIDER=virtualbox vagrant up
```

> **Note**: During the initial deployment, the virtual machine will gracefully halt itself after the bootstrap completes. **You must issue a second `vagrant up`** immediately afterward to bring the instance back online.
>
> **Switching providers on an existing checkout:** Vagrant stores per-machine state under `.vagrant/`. If you previously ran `vagrant up` with one provider and switch to the other, run `vagrant destroy -f` first or you will see provider-mismatch errors.
>
> **Upgrading an existing checkout:** the default mode is now `official`, so the auto-clone and NFS synced folder target `../core` (upstream OPNsense) instead of `../OTSA-Core`. If you work on the internal fork, export `OTSA_MODE=custom` or you will end up with a second, unrelated clone beside this repository.

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

Additionally, if an adjacent `../$core_repository` directory does not exist on the host (`../core` in `official` mode, `../OTSA-Core` in `custom` mode), `vagrant/common.rb` will automatically clone it over via `$core_clone_url` (which can be overridden with the `CORE_CLONE_URL` environment variable). The system then sets up an NFS synced folder bridging that directory to `${vagrant_mount_path}/core` (default `/var/vagrant/core`) within the VM, ensuring seamless cross-environment software development.

## Troubleshooting & Maintenance

**Changing the LAN IP Configuration**
If `192.168.56.56` collides with your local infrastructure:
1. Turn off the active instance: `vagrant halt`.
2. Modify `$virtual_machine_ip` in [`vagrant/common.rb`](vagrant/common.rb) — one place, both providers.
3. Restart the environment: `vagrant up`.
4. Access the web interface using the newly assigned IP address.

**System Rebuilds**
To completely destroy the environment and re-sync from scratch, execute:
```bash
vagrant destroy -f
PROVIDER=<libvirt|virtualbox> vagrant up
```

---
*Maintained by the OT-Project Development Team.*
