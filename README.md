# gamebridge
LAN Game Server Rebroadcaster over VLANs

Created by Travis Kreikemeier @ NETWAR (http://www.netwar.org)

Gamebridge allows you to carve up your LAN party network into many VLANs.  Usually, this is a no-no for LAN parties due to the broadcasts needed to find local LAN game servers.  Gamebridge rebroadcasts those game server finding beacons across many VLANs without passing anything else (ARP, BPDU, other non-game server broadcasts, etc.).

# REQUIREMENTS
* Tested at large LAN events with Debian 12 as a guest on VMWare ESX 8
* Any other distros may require modifications
* Python 3 with PyYAML (`apt-get install python3-yaml`)
* Two NICS: One connected to a single VLAN for management
* The other NIC connected to a trunk port on your switch with all VLANs tagged
* If using VMWare vSwitch, the trunk port group needs to have VLAN 4095 set so that it passes all VLANs tagged to the guest vNIC.

# INSTALL

1. Copy the example config and edit it for your network:
   ```
   cp gamebridge.conf.example.yaml gamebridge.conf.yaml
   vi gamebridge.conf.yaml
   ```

2. Preview what the installer will do:
   ```
   ./install.sh -c gamebridge.conf.yaml --dry-run
   ```

3. Run the installer:
   ```
   sudo ./install.sh -c gamebridge.conf.yaml
   ```

4. Reboot to apply:
   ```
   sudo reboot
   ```

5. Verify after reboot:
   ```
   sudo ./install.sh --status
   ```

# CONFIGURATION

Edit `gamebridge.conf.yaml` to match your environment:

| Field | Description |
|---|---|
| `management.interface` | Management NIC name (e.g. `ens192`) |
| `management.address` | Management IP address |
| `management.netmask` | Management subnet mask |
| `management.gateway` | Management gateway |
| `trunk_interface` | Trunk NIC connected to tagged VLANs (e.g. `ens224`) |
| `bridge` | Bridge interface name (default: `br0`) |
| `vlans` | List of VLAN IDs to bridge |
| `game_ports` | List of UDP port ranges to allow (e.g. `"27014:27025"`) |

See `gamebridge.conf.example.yaml` for a full working example.
