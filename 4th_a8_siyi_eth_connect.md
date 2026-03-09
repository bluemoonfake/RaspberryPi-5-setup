# A8 SIYI Ethernet Connection Setup

## Install ethtool

```bash
sudo apt update
sudo apt install ethtool -y
```

## Set Ethernet Speed to 10Mb/s

Note: If reboot Pi5, it will reset to 100Mb/s. To set 10Mb/s permanently, create a service file.

```bash
sudo ethtool -s eth0 speed 10 duplex full autoneg off
```

- Check if laptop has eth0:

  ```bash
  ip addr
  ```

- Check if speed is down to 10Mb/s and link detect = yes:
  ```bash
  sudo ethtool eth0 | egrep 'Speed|Duplex|Auto|Link'
  ```

## Install Software for Video Stream

```bash
sudo apt update
sudo apt install ffmpeg -y
```

## Run on Pi5 to Forward RTSP on Pi5

```bash
ffmpeg -hide_banner -nostdin -loglevel warning \
  -rtsp_transport tcp -use_wallclock_as_timestamps 1 \
  -i rtsp://192.168.144.25:8554/main.264 \
  -fflags +genpts -c copy \
  -f rtsp -rtsp_transport tcp \
  rtsp://34.56.241.85:8554/a8_node2
```

## Run on Laptop to View Video Stream

```bash
ffplay -rtsp_transport tcp rtsp://34.56.241.85:8554/a8_node2
```

## Alternative FFmpeg Command

```bash
ffmpeg -hide_banner -nostdin -loglevel warning \
  -f v4l2 -i /dev/video0 \
  -fflags +genpts -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -f rtsp -rtsp_transport tcp \
  rtsp://34.56.241.85:8554/a8
```
