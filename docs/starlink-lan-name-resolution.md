# Starlink LAN name resolution notes

Starlink provides DHCP, IPv4 routing, IPv6 routing/prefixes, and DNS-like hostname answers on this LAN. Do not assume bare hostnames resolve to IPv4.

## Observed behaviour on 2026-07-03

From `picanm`:

```text
getent hosts pi5nvme
  -> IPv6 addresses only/first from Starlink/local DNS

getent ahosts pi5nvme
  -> IPv6 addresses first, IPv4 192.168.1.135 last

getent ahosts pi5nvme.local
  -> 192.168.1.135 only
```

From `pi5nvme`:

```text
getent ahosts picanm.local
  -> 192.168.1.235 only
```

The raw receiver on `pi5nvme` currently listens on IPv4:

```text
0.0.0.0:20200
```

Therefore the picanm raw forwarder should use:

```text
DEST_HOST=pi5nvme.local
```

not bare `pi5nvme`.

## Why `.local` works even with Starlink routing

`.local` is mDNS/Avahi peer-to-peer multicast on the LAN. It does not depend on Starlink's normal DNS answers. It can coexist with Starlink DHCP/IPv4/IPv6 routing.

mDNS can fail if multicast/client isolation/VLAN boundaries block it, but it is currently proven working between the two Pis.

## WSL / Windows 11 caveat

The operator workstation runs Debian in WSL2 on Windows 11. WSL name resolution is not the same as Pi-to-Pi LAN name resolution.

Consequences:

- `ssh pi5nvme.local` from WSL may behave differently from `ssh pi5nvme.local` from a Pi.
- WSL mDNS multicast can be unreliable depending on Windows/WSL networking mode.
- Do not use WSL resolution failures to conclude that Pi-to-Pi mDNS is broken.

For service configuration, test from the device that runs the service. For the raw forwarder, test from `picanm`:

```bash
getent ahosts pi5nvme.local
timeout 3 bash -c '</dev/tcp/pi5nvme.local/20200'
```

For human access from WSL, use whichever of these is reliable at the time:

```bash
ssh pi5nvme
ssh pi5nvme.local
ssh 192.168.1.135
```

If `ssh pi5nvme` hangs or times out from WSL, do not immediately treat that as host failure. On 2026-07-03, `ssh pi5nvme` timed out under short timeouts while direct IPv4 access worked immediately:

```bash
ssh -o StrictHostKeyChecking=accept-new 192.168.1.135 'date -u +%FT%TZ && hostname'
```

The address `192.168.1.135` is DHCP-provided and may change; verify from the Starlink router/DHCP lease table or another working hostname/mDNS path if it stops working.

WSL SSH aliases were added on the operator machine to bypass DNS/mDNS for urgent access:

```text
pi5nvme-ip -> 192.168.1.135
picanm-ip  -> 192.168.1.235
```

## mDNS operational checklist

For Pi-to-Pi service names, keep `.local` working deliberately rather than relying on Starlink bare-hostname DNS:

```bash
systemctl is-active avahi-daemon
getent ahosts pi5nvme.local
getent ahosts picanm.local
```

On each Pi, verify name-service switching includes mDNS before generic DNS for `.local` names. Typical Debian/Raspberry Pi OS shape:

```text
hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4
```

If `.local` resolution fails between Pis:

1. Confirm `avahi-daemon` is installed, enabled, and active on both Pis.
2. Confirm `libnss-mdns` is installed on both Pis.
3. Confirm `/etc/nsswitch.conf` has a sane `hosts:` line with `mdns4_minimal` before `dns`.
4. Confirm Starlink/router Wi-Fi client isolation, guest network isolation, VLANs, or firewall rules are not blocking multicast UDP 5353.
5. Confirm both Pis are on the same L2 LAN segment and can reach each other by IPv4.
6. Only after those checks, change application service hostnames.

Verified on 2026-07-03:

```text
pi5nvme: avahi-daemon active; hosts: files mdns4_minimal [NOTFOUND=return] dns
pi5nvme: getent ahosts picanm.local -> 192.168.1.235
pi5nvme: getent ahosts pi5nvme.local -> 192.168.1.135
picanm: avahi-daemon active; hosts: files mdns4_minimal [NOTFOUND=return] dns
picanm: getent ahosts pi5nvme.local -> 192.168.1.135
picanm: getent ahosts picanm.local -> 192.168.1.235
picanm: /dev/tcp/pi5nvme.local/20200 reachable
```

WSL/operator resolution is separate: `picanm.local` failed from WSL in the same session, while direct IPv4 SSH worked.

For WSL/operator access, `.local` may still be unreliable because WSL name resolution is not the same as Pi-to-Pi LAN resolution. Prefer direct IPv4 for urgent human/agent SSH when bare names hang.

## Future options

More robust long-term fixes would be:

- make `boat-n2k-raw-receiver` listen dual-stack on IPv6 as well as IPv4;
- create stable DHCP reservations in Starlink and document the reserved IPv4 addresses;
- run local DNS with stable A/AAAA records;
- add SSH host aliases on the operator machine for direct IPv4 access.

For now, `pi5nvme.local` is the simplest working Pi-to-Pi service name, and direct IPv4 is the most reliable WSL fallback.
