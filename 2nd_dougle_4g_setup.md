# Dougle 4G Module Setup

After having a SIM registered for 4G package, connect the module via USB cable.

## Check Device Connection

```bash
lsusb
```

Result: `Bus 001 Device 005: ID 1e0e:9001 Qualcomm / Option SimTech, Incorporated`

```bash
ls /dev/ttyUSB*
```

Result: ttyUSB1 2 3 4 ,...

## Setup Module (using usb2)

```bash
minicom -D /dev/ttyUSB2
```

Run command:

```
AT
```

Result: OK
=> Connected to module

```
AT+CUSBPIDSWITCH=9001,1,1
```

Then unplug and plug back to make SIM7600 use ECM/RNDIS mode.

Use `ifconfig` to check device name enx....

Now can connect to internet via USB ethernet networking, but cannot pub/sub data to broker

- Because ISP doesn't open ports 1883, 8883 (very rare)

* Switch to normal Wi-Fi network try `nc -vz broker.emqx.io 1883` to ensure broker works.
* Plug SIM7600G via Viettel, test `nc -vz` on ports 1883/8883/443.
* If nc timeout but `AT+CIPOPEN=0,"TCP","host",port` returns +CIPOPEN: 0,0, port is blocked from PC side, not ISP.
* Check modem attached to network: `AT+CGATT?` must be 1.

## Configure APN & Activate PDP

- Set Viettel common data APN:

```
AT+CGDCONT=1,"IP","v-internet"
```

- Open data according to ECM firmware:

```
AT+NETOPEN
```

Result NETOPEN: 0 THEN NOT ISP PROBLEM.

Solution: Switch to PPP (or QMI). Keep ECM only if firmware has NETCFG.

```bash
sudo apt install ppp
```

Reset PID: `AT+CUSBPIDSWITCH=9001,1,1`
(or equivalent PPP firmware). Unplug/plug USB after OK.

```bash
ls /dev/ttyUSB*
```

Must see at least ttyUSB0…ttyUSB3

## Create Dial Script

```bash
sudo mkdir -p /etc/chatscripts

sudo tee /etc/ppp/peers/sim7600 >/dev/null <<'EOF'
/dev/ttyUSB3 115200
connect "/usr/sbin/chat -v -f /etc/chatscripts/sim7600"
noauth
defaultroute
usepeerdns
persist
holdoff 5
# nodetach   # remove if want pppd run in background
EOF

sudo tee /etc/chatscripts/sim7600 >/dev/null <<'EOF'
ABORT "NO CARRIER"
ABORT "ERROR"
ABORT "NO DIALTONE"
ABORT "BUSY"
ABORT "NO ANSWER"
TIMEOUT 20
"" AT
OK ATE0
OK AT+CGDCONT=1,"IP","v-internet"
OK ATD*99#
CONNECT ""
EOF
```

Then run:

```bash
sudo pppd call sim7600
```

After ppp0 is up

Your PPP is up standard (IP 29.54.124.89, ping 8.8.8.8 ok),
so actual Internet path is working.
If web access still error then almost certainly DNS issue.

```bash
cat /etc/resolv.conf
```

See if there is any nameserver. With usepeerdns PPP should write to file, but sometimes NetworkManager overwrites.
If file empty or points to 127.0.0.53, add manually:

```bash
sudo rm /etc/resolv.conf
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

Try again: `curl --interface ppp0 https://ifconfig.me`

Or open browser (turn off other Wi-Fi/LAN to ensure using PPP).
If using NetworkManager, may need `sudo systemctl restart systemd-resolved`
then create symlink
`ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf`.

## Daily Operation

Each reboot/replug:
Check modem appears ttyUSB\*.
(If modem reset) run
`AT+CGDCONT=1,"IP","v-internet"`.

```bash
sudo pppd call sim7600 persist holdoff 5
```

Ensure /etc/resolv.conf has desired DNS.
