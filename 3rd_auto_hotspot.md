# Auto Hotspot Setup (with 4G Module)

## Create Systemd Service

```bash
sudo nano /etc/systemd/system/hotspot-autostart.service
```

Add the following content:

```ini
[Unit]
Description=Auto start WiFi Hotspot (Direct NMCLI)
After=network-online.target NetworkManager.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nmcli radio wifi on
ExecStart=/usr/bin/nmcli device wifi hotspot ifname wlan0 ssid **<SSID_CỦA_BẠN>** password **<MẬT_KHẨU_CỦA_BẠN>**
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

## Save and Enable Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hotspot-autostart.service
```

## Test

```bash
systemctl status hotspot-autostart.service
nmcli connection show --active
```

## Reboot and Check

```bash
nmcli connection show --active
```
