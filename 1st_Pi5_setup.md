# Setup Raspberry Pi First Time

## Install Modem Manager and Dependencies

```bash
sudo apt install modemmanager usb-modeswitch
sudo systemctl enable ModemManager.service
sudo systemctl start ModemManager.service
sudo nmcli connection modify "Mobile Internet" connection.autoconnect yes
sudo mmcli -m 0 --enable
```

## Install Python Libraries

```bash
sudo apt install python3-paho-mqtt
sudo apt install python3-opencv
```

## Install and Enable SSH

```bash
sudo apt install openssh-server -y
sudo systemctl enable ssh
sudo systemctl start ssh
sudo ufw allow ssh
```

## Update System

```bash
sudo apt update
sudo apt upgrade
```

## Setup UTF-8 Locale

```bash
sudo apt update && sudo apt install locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
```

## Add ROS2 Repository

```bash
sudo apt install software-properties-common
sudo add-apt-repository universe
sudo apt update && sudo apt install curl -y
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
```

## Install ROS2 Base

```bash
sudo apt update
sudo apt upgrade
sudo apt install ros-jazzy-ros-base
sudo apt install ros-dev-tools
```

## Setup Environment

```bash
echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

## Install Python Dependencies

```bash
sudo apt update
sudo apt install python3-empy python3-setuptools python3-lark python3-numpy -y
```

## Install Colcon

```bash
sudo apt install git python3-colcon-common-extensions -y
```

## Setup Hosts for Local Server

Edit `/etc/hosts`:

```
# Host Database
#
# localhost is used to configure the loopback interface
# when the system is booting. Do not change this entry.
##
127.0.0.1 localhost
255.255.255.255 broadcasthost
::1 localhost

14.161.17.92 rdm.tdt15.internal.local
14.161.17.92 internal.mapping.ctuav.vn
127.0.0.1 ct-universe.internal.local
14.161.17.92 emqx.dashboard.ctuav.vn
14.161.17.92 emqx.mqtt.ctuav.vn
```
