# 4G Reset Script Installation Guide (Hardware Reset)

This document describes how to install the GPIO control library and create a script that automatically resets the 4G module when network connectivity is lost.

---

# 1. Install the GPIO Library (`gpiod`)

To allow the script to control GPIO pins (power on/off), the `gpiod` package must be installed.

Run the following commands in the terminal:

```bash
sudo apt update
sudo apt install gpiod -y
```

Verify that the installation was successful:

```bash
gpioset --version
```

---

# 2. Create the 4G Reset Script

## Step 1: Create the Script File

Use the `nano` editor to create the script in the system binary directory:

```bash
sudo nano /usr/local/bin/reset_4g_final.sh
```

---

## Step 2: Add the Script Content

Copy and paste the following script into the file.

> **Note:** Verify the `CHIP` and `LINE` parameters if your hardware configuration differs from the default values (in this example: **Chip 4, Line 6**).

```bash
#!/bin/bash

# --- CONFIGURATION ---
CHIP=4
LINE=6
LOGFILE="/var/log/4g_reset.log"
LOCKFILE="/tmp/4g_booting.lock"

# 1. Check if the system is currently in the boot waiting period
if [ -f "$LOCKFILE" ]; then
    # If the lock file was created less than 2 minutes ago (120 seconds), exit immediately
    if [ $(($(date +%s) - $(date +%s -r $LOCKFILE))) -lt 120 ]; then
        exit 0
    else
        rm "$LOCKFILE"
    fi
fi

# 2. Check network connectivity (Ping with 4s timeout)
if ping -c 1 -W 4 8.8.8.8 > /dev/null 2>&1; then
    exit 0
fi

echo "$(date): [NETWORK LOST] Ping failed." >> $LOGFILE

# 3. CHECK HARDWARE STATUS (using lsusb)
USB_STATUS=$(lsusb | grep -E "Qualcomm|Simcom|05c6")

if [ -z "$USB_STATUS" ]; then
    # CASE A: USB device not detected → module is powered OFF
    echo "-> Module is OFF. Performing POWER ON..." >> $LOGFILE
    
    gpioset $CHIP $LINE=1
    sleep 3
    gpioset $CHIP $LINE=0
    
else
    # CASE B: USB detected → module is frozen (powered but no network)
    echo "-> Module is UNRESPONSIVE. Performing HARD RESET (Power Cycle)..." >> $LOGFILE
        
    gpioset $CHIP $LINE=1
    sleep 3
    gpioset $CHIP $LINE=0
    
    sleep 20
    
    gpioset $CHIP $LINE=1
    sleep 3
    gpioset $CHIP $LINE=0
fi

# 4. CREATE LOCK FILE
touch "$LOCKFILE"
echo "$(date): Reset triggered. Waiting for module boot (2-minute lock)..." >> $LOGFILE
```

---

# 3. Grant Execute Permission

To allow the script to run, assign execute permission:

```bash
sudo chmod +x /usr/local/bin/reset_4g_final.sh
```

---

# 4. Verify Script Operation

### Method 1: Dry Run

If the network is working normally, the script will run and exit immediately without any output.

```bash
sudo /usr/local/bin/reset_4g_final.sh
```

### Method 2: Check Logs

Review the script execution history:

```bash
cat /var/log/4g_reset.log
```
