# SIM7600 LTE Setup — Raspberry Pi 5

**Module:** SIM7600NA-H (USB-connected modem / HAT)  
**System:** Ubuntu 24.04 · QMI + NetworkManager

Carrier-independent setup: use your SIM provider's APN and ensure local LTE band compatibility. This is a **4G LTE Cat 4** modem, not 5G NR.

**Bands:** FDD B2/4/5/12/13/14/25/26/66/71; TDD B41. A supported band must also be deployed by the local carrier.

**Common names:** `SIM7600_4G` (mobile connection), `SIM7600_Hotspot` (Wi-Fi profile), `SIM7600-Companion` (SSID).

## 1. Install and detect

Connect the SIM, LTE antennas and USB data cable; ensure stable power.

~~~bash
sudo apt update
sudo apt install -y network-manager modemmanager minicom curl usbutils
sudo systemctl enable --now NetworkManager ModemManager
lsusb
ls /dev/cdc-wdm* /dev/ttyUSB*
mmcli -L
mmcli -m 0
nmcli device status
~~~

Expected: `qmi_wwan`, `/dev/cdc-wdmX` and `wwan0`. USB port numbers can change.

## 2. Check SIM and LTE

The AT port is usually `/dev/ttyUSB2` (confirm with `mmcli -m 0`).

~~~bash
sudo minicom -D /dev/ttyUSB2 -b 115200
~~~

Run inside minicom:

~~~text
AT
ATI
AT+CPIN?
AT+CEREG?
AT+COPS?
AT+CPSI?
AT+CGATT?
~~~

Check for `+CPIN: READY`, LTE registration (`+CEREG: 0,1` or `0,5`) and `+CGATT: 1`. Exit: **Ctrl+A**, then **X**.

## 3. Configure mobile data (QMI)

Enter the **APN provided by your SIM carrier**. There is no universal APN. If an older GSM profile exists, rename or remove it before creating a duplicate.

~~~bash
read -r -p "Carrier APN: " APN
if [ -n "$APN" ]; then
  nmcli con show SIM7600_4G >/dev/null 2>&1 ||
    sudo nmcli con add type gsm ifname '*' con-name SIM7600_4G apn "$APN"
  sudo nmcli con mod SIM7600_4G \
    gsm.apn "$APN" connection.autoconnect yes \
    ipv4.route-metric 700 ipv6.route-metric 700
  sudo nmcli -w 90 con up SIM7600_4G
else
  echo "APN is required"
fi
unset APN
~~~

Set GSM credentials separately if required by the carrier. Verify traffic through **4G**, not Wi-Fi:

~~~bash
ip -br addr show wwan0
ping -I wwan0 -c 4 8.8.8.8
curl --interface wwan0 -4 --max-time 15 https://api.ipify.org
~~~

## 4. Wi-Fi hotspot (auto-connect)

**Warning:** Switching `wlan0` to AP mode disconnects existing Wi-Fi and may end SSH. Use local access if needed.

~~~bash
nmcli -f WIFI-PROPERTIES.AP device show wlan0
~~~

Create the hotspot once (or rename an existing hotspot profile to `SIM7600_Hotspot`):

~~~bash
if ! nmcli con show SIM7600_Hotspot >/dev/null 2>&1; then
  read -rsp "Hotspot password (8-63 chars): " PSK; echo
  sudo nmcli device wifi hotspot ifname wlan0 \
    con-name SIM7600_Hotspot ssid SIM7600-Companion \
    band bg password "$PSK"
  unset PSK
fi
sudo nmcli con mod SIM7600_Hotspot \
  802-11-wireless.ssid SIM7600-Companion \
  ipv4.method shared ipv4.addresses 192.168.50.1/24 \
  ipv6.method disabled connection.autoconnect yes \
  connection.autoconnect-priority 100
sudo nmcli con up SIM7600_Hotspot
~~~

If the old Wi-Fi client profile competes for `wlan0` on reboot, find its name with `nmcli con show` and disable **its** auto-connect; do not delete it.

## 5. Verify and troubleshoot

~~~bash
nmcli con show --active
ip -br addr
ip route
mmcli -m 0
sudo journalctl -u ModemManager -u NetworkManager -n 60 --no-pager
~~~

- **No USB/QMI:** check power, USB data cable and `lsusb -t`.
- **No LTE:** check SIM, antenna, coverage and supported bands.
- **No Internet:** check the carrier APN, data plan and `wwan0` route.
- **Slow connection setup:** use `sudo nmcli -w 30 con up SIM7600_4G` and inspect logs.
- **Hotspot without Internet:** check `wwan0` and `ipv4.method shared`.

After confirming access, reboot once to test auto-connect. Avoid publishing passwords or SIM IDs. Use a VPN for remote access if the carrier uses CGNAT.

## 6. Recover from an incorrect LTE band lock

If `mmcli -m 0` reports `current: eutran-4` and `state: searching`, the local network may not offer Band 4. Restore all supported bands using local console or hotspot access:

~~~bash
sudo nmcli con mod SIM7600_4G connection.autoconnect no
sudo nmcli con down SIM7600_4G || true
sudo mmcli -m 0 --set-current-bands=any
mmcli -m 0
~~~

Wait for LTE registration, then:

~~~bash
sudo nmcli con mod SIM7600_4G connection.autoconnect yes
sudo nmcli -w 90 con up SIM7600_4G
~~~

If band restoration fails, collect ModemManager logs first. **FDD is not inherently faster than TDD.**
