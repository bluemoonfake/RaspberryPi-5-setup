# SIM7600G-H — Raspberry Pi 5 + Viettel 4G (QMI) + Wi-Fi Hotspot

> **Phạm vi:** SIMCOM SIM7600G-H dùng qua USB dongle hoặc HAT có kết nối USB data với Raspberry Pi 5 (Ubuntu 24.04, NetworkManager, ModemManager). SIM7600G-H là modem **4G LTE Cat 4, không phải 5G NR**, dù board mở rộng có thể được quảng cáo là "4G/5G HAT".
>
> **Trạng thái kiểm chứng:** Quy trình QMI và chia sẻ hotspot đã chạy thành công trên Pi `ctuav9`, mạng Viettel. **Chưa xác nhận reboot thực tế từ log đã cung cấp.**
>
> **Khác với hướng dẫn PPP/ECM gốc:** Nếu USB đang hiển thị `1e0e:9001`, driver `qmi_wwan` và `/dev/cdc-wdm*`, **không** dùng `AT+CUSBPIDSWITCH`, PPP, hay sửa/xóa `/etc/resolv.conf`. Hãy dùng NetworkManager như bên dưới. Bản gốc tham khảo ở nhánh `main` hoặc [KoiN251/rpi5_setup](https://github.com/KoiN251/rpi5_setup/blob/main/2nd_dougle_4g_setup.md).

## 0. Điều kiện đầu vào và đấu nối

- Raspberry Pi 5 có Ubuntu 24.04, quyền `sudo`, kết nối Internet tạm thời để cài gói.
- SIM Viettel đã kích hoạt dữ liệu; anten LTE kết nối đúng cổng theo nhãn module/HAT.
- Module/HAT được cấp nguồn đúng yêu cầu phần cứng; nếu là HAT, kiểm tra **cáp USB data**, jumper PWR và dòng cấp nguồn theo đúng phiên bản board. Chỉ gắn HAT vào GPIO chưa chắc đã tạo ra thiết bị USB/QMI.
- Không chia sẻ ICCID, IMEI, mật khẩu hotspot, token hoặc địa chỉ dịch vụ nội bộ lên repository public.
- **Nếu đang SSH qua `wlan0`:** bật hotspot sẽ ngắt Wi-Fi đang dùng; thực hiện trên console hoặc chuẩn bị đường truy cập khác.

## 1. Cài các công cụ cần thiết

```bash
sudo apt update
sudo apt install -y modemmanager network-manager minicom curl usbutils
sudo systemctl enable --now ModemManager NetworkManager
```

Kiểm tra USB và giao diện:

```bash
lsusb
lsusb -t
ls /dev/ttyUSB*              # thường có ttyUSB0 ... ttyUSB4
ls /dev/cdc-wdm*             # số có thể là 0, 1... tùy lần khởi động
ip -br link
mmcli -L
nmcli device status
```

**Kết quả quan sát trên `ctuav9`:** USB `1e0e:9001`, `/dev/ttyUSB0..4`, `qmi_wwan`, `/dev/cdc-wdm0`, `wwan0`, ModemManager báo `SIMCOM_SIM7600G-H`. **Đừng hardcode `cdc-wdm0`** vì chỉ số có thể đổi.

## 2. Kiểm tra AT, SIM và đăng ký mạng LTE

```bash
sudo minicom -D /dev/ttyUSB2 -b 115200
```

Nhập lần lượt trong minicom (đây là lệnh gửi **bên trong minicom**, không phải lệnh Bash):

```text
AT
ATI
AT+CPIN?
AT+CSQ
AT+CEREG?
AT+COPS?
AT+CGATT?
AT+CPSI?
```

- `AT` trả `OK` và `ATI` trả `SIMCOM_SIM7600G-H` ⇒ UART USB giao tiếp được.
- `+CPIN: READY` ⇒ SIM sẵn sàng.
- `+CEREG: 0,1` hoặc `0,5` ⇒ đăng ký LTE; `+COPS: ...,"Viettel Viettel",7` ⇒ nhà mạng Viettel, LTE.
- `+CGATT: 1` ⇒ đã attach dữ liệu gói; **chưa đủ để kết luận Linux có Internet**.
- `AT+CPSI?` cho biết LTE band/cell khi firmware hỗ trợ. Log Pi `ctuav9` chưa có CPSI nên **không khẳng định đang dùng B3 hay B41**.

Thoát minicom: **Ctrl+A**, sau đó **X**. Nếu bị báo cổng bận, đóng minicom rồi mới dùng ModemManager.

## 3. Tạo kết nối Internet Viettel bằng QMI

Kiểm tra modem đã được quản lý:

```bash
mmcli -m 0
nmcli device status
```

Trong ví dụ này, profile được đặt tên đúng theo Pi đã sử dụng: `CTUAV_computer`. Chỉ **tạo mới nếu chưa tồn tại**, tránh tạo profile trùng:

```bash
nmcli connection show CTUAV_computer
# Nếu báo "unknown connection" thì mới tạo:
sudo nmcli connection add type gsm ifname '*' con-name CTUAV_computer apn v-internet
```

Cấu hình APN/đường đi ưu tiên và tự kết nối:

```bash
sudo nmcli connection modify CTUAV_computer \
  gsm.apn v-internet \
  connection.autoconnect yes \
  ipv4.route-metric 700 \
  ipv6.route-metric 700
sudo nmcli -w 90 connection up CTUAV_computer
```

Kết quả thực tế đã kiểm chứng: `wwan0` có IPv4, `nmcli connection show --active` ghi `CTUAV_computer` trên `cdc-wdm0`; khi Wi-Fi còn hoạt động, default route Wi-Fi metric 600 và 4G metric 700.

Kiểm tra **riêng 4G**, không nhầm với Wi-Fi:

```bash
ip -br addr show wwan0
ip route
ping -I wwan0 -c 4 8.8.8.8
curl --interface wwan0 -4 --max-time 15 https://api.ipify.org
```

Trên `ctuav9`, `ping -I wwan0` trả 4/4 gói và truy vấn IP public thành công. Địa chỉ IP có thể thay đổi theo phiên; không ghi cố định vào script.

## 4. Phát Wi-Fi Hotspot bằng `wlan0` và chia sẻ Internet 4G

> **Cẩn thận:** `wlan0` đang kết nối Wi-Fi khác sẽ bị chuyển sang chế độ AP, khiến SSH qua Wi-Fi cũ bị ngắt. Mạng Wi-Fi mới có thể phát **trước khi** kết nối 4G có Internet.

```bash
nmcli -f WIFI-PROPERTIES.AP device show wlan0
# Phải là: WIFI-PROPERTIES.AP: yes
```

Tạo hotspot một lần nếu chưa có profile `CTUAV_Hotspot`. Lấy mật khẩu từ terminal (không ghi mật khẩu vào lịch sử Bash):

```bash
read -rsp 'Nhap mat khau hotspot (8-63 ky tu): ' HOTSPOT_PSK; echo
sudo nmcli device wifi hotspot \
  ifname wlan0 \
  con-name CTUAV_Hotspot \
  ssid CTUAV-companion-computer \
  band bg \
  password "$HOTSPOT_PSK"
unset HOTSPOT_PSK
```

Nếu profile **đã có**, không tạo lại. Để thay mật khẩu mà không ghi vào lịch sử shell:

```bash
read -rsp 'Mat khau hotspot moi: ' HOTSPOT_PSK; echo
sudo nmcli connection modify CTUAV_Hotspot wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PSK"
unset HOTSPOT_PSK
sudo nmcli connection up CTUAV_Hotspot
```

Đặt IP/gateway cố định và chế độ NAT/DHCP của NetworkManager:

```bash
sudo nmcli connection modify CTUAV_Hotspot \
  ipv4.method shared \
  ipv4.addresses 192.168.50.1/24 \
  ipv6.method disabled \
  connection.autoconnect yes \
  connection.autoconnect-priority 100
sudo nmcli connection up CTUAV_Hotspot
```

Nếu muốn **luôn** bật AP sau reboot, tắt autoconnect của profile Wi-Fi cũ (thay đúng tên hiển thị trên Pi; ví dụ trước đó là `Nam dep trai`):

```bash
nmcli -f NAME,TYPE,AUTOCONNECT connection show
sudo nmcli connection modify 'Nam dep trai' connection.autoconnect no
```

Không xóa profile Wi-Fi cũ. Nếu Pi không có profile cũ, bỏ qua lệnh trên.

## 5. Kiểm tra sau bật hotspot và sau reboot

```bash
nmcli connection show --active
ip -br addr show wlan0
ip -br addr show wwan0
ip route
nmcli -f connection.id,connection.autoconnect connection show CTUAV_computer
nmcli -f connection.id,connection.autoconnect connection show CTUAV_Hotspot
```

Dự kiến: `CTUAV_Hotspot` ở `wlan0` với `192.168.50.1/24`; `CTUAV_computer` ở thiết bị GSM (`cdc-wdmX`); route mặc định qua `wwan0` khi Wi-Fi chỉ phát AP. Từ laptop kết nối hotspot, thử `ssh <user-pi>@192.168.50.1`, ping Internet và kiểm tra DNS.

Chỉ reboot khi có khả năng truy cập lại Pi qua hotspot hoặc màn hình:

```bash
sudo reboot
```

Sau reboot xác nhận cả hotspot **và** dữ liệu 4G tự bật; `autoconnect=yes` là cấu hình dự kiến, không thay thế cho kiểm chứng reboot thực tế.

## 6. Khắc phục sự cố

| Dấu hiệu | Kiểm tra / xử lý an toàn |
|---|---|
| Không có `/dev/ttyUSB*` hoặc `/dev/cdc-wdm*` | Kiểm tra nguồn, USB data, `lsusb -t`, `dmesg`; không đổi USB PID khi QMI đã hiện. |
| `AT` không phản hồi | Xác nhận `/dev/ttyUSB2` đúng AT port bằng `mmcli -m 0`, 115200 baud, đóng chương trình đang giữ cổng. |
| SIM không đăng ký LTE | `AT+CPIN?`, `AT+CEREG?`, `AT+CPSI?`, anten, sóng Viettel, gói SIM. |
| `wwan0` có IP nhưng không vào mạng | `ping -I wwan0`, `curl --interface wwan0`, `ip route`, `resolvectl status`; không xóa `/etc/resolv.conf`. |
| `nmcli connection up` chờ lâu | `sudo nmcli -w 30 connection up CTUAV_computer`; đọc `mmcli -m 0`, `sudo journalctl -u ModemManager -u NetworkManager -n 80 --no-pager`. |
| Có hotspot nhưng laptop không có Internet | Kiểm tra 4G còn `connected`, default route qua `wwan0`, `ipv4.method shared`, DHCP của client. |

**Lưu ý bảo mật/vận hành:** LTE qua nhà mạng có thể ở sau CGNAT; SSH trực tiếp từ Internet không bảo đảm dùng được. Khi cần truy cập UAV từ xa nên dùng VPN (ví dụ WireGuard/NetBird) hoặc đường truyền tới server chủ động; không công khai dịch vụ điều khiển bay.