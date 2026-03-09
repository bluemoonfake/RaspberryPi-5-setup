# Auto Start UAV Setup

## Activate UART on Pins 8 and 10

Activate UART0 on Pin 8 (GPIO 14) and Pin 10 (GPIO 15)
```bash
sudo nano /boot/firmware/config.txt
```
```bash
dtoverlay=uart0
```

## Replace trinhsat1 with Your Pi Name

Create a file `start_uav.sh` as attached.

```bash
chmod +x /home/trinhsat1/start_uav.sh
```

## Allow Script to Run with Sudo Permissions

In a new terminal, allow scripts to run with sudo permissions.

```bash
sudo visudo
```

Add to the end (replace with your user):

```
trinhsat1 ALL=(ALL) NOPASSWD: /usr/sbin/ethtool
```

## Create Service

```bash
sudo nano /etc/systemd/system/uav-autostart.service
```

Add and save:

```ini
# /etc/systemd/system/uav-autostart.service
[Unit]
Description=Auto start UAV ROS2 stack
After=network-online.target NetworkManager.service serial-getty@ttyAMA0.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/trinhsat1
ExecStart=/home/trinhsat1/start_uav.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Quick explanation:

- User=trinhsat1 to run in correct user environment (since you're using $HOME/giam_sat_uav).
- After=network-online.target to wait for network (if you need PX4/RTPS over network).
- Restart=on-failure so if node crashes, systemd restarts it.

## Reload and Enable

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now uav-autostart.service
```
