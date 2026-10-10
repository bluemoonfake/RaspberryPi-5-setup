# Hướng dẫn cấu hình 4G LTE SIM7600 trên Raspberry Pi 5

**Model:** SIM7600G-H — USB Dongle hoặc HAT sử dụng kết nối USB data.

> **Hướng dẫn không phụ thuộc nhà mạng:** Cấu hình QMI + NetworkManager, nhập APN phù hợp với SIM và nhà mạng đang sử dụng. SIM7600G-H là modem **4G LTE Cat 4**, không phải 5G NR. Kết nối chỉ thành công khi nhà mạng phủ sóng LTE ở **băng tần modem hỗ trợ**.
>
> **Kiểm chứng:** USB `1e0e:9001`, `qmi_wwan`/`wwan0` và kết nối dữ liệu qua QMI đã hoạt động trong thử nghiệm thực tế; cần tự kiểm tra ở mạng/địa điểm khác và sau reboot.
>
> **Khác với PPP/ECM trong hướng dẫn gốc:** nếu USB đã hiển thị `qmi_wwan` và `/dev/cdc-wdm*`, không cần chạy `AT+CUSBPIDSWITCH` hoặc cấu hình PPP, cũng không xóa `/etc/resolv.conf`.

## 0. Điều kiện đầu vào và đấu nối

- Raspberry Pi 5 có Ubuntu 24.04, quyền `sudo`, kết nối Internet tạm thời để cài gói.
- SIM đã kích hoạt dữ liệu; anten LTE kết nối đúng cổng theo nhãn module/HAT.
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

**Kết quả quan sát trên `Raspberry Pi thử nghiệm`:** USB `1e0e:9001`, `/dev/ttyUSB0..4`, `qmi_wwan`, `/dev/cdc-wdm0`, `wwan0`, ModemManager báo `SIMCOM_SIM7600G-H`. **Đừng hardcode `cdc-wdm0`** vì chỉ số có thể đổi.

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
- `+CEREG: 0,1` hoặc `0,5` ⇒ đăng ký LTE; `+COPS: ...,"<TEN_NHA_MANG>",7` ⇒ nhà mạng, LTE.
- `+CGATT: 1` ⇒ đã attach dữ liệu gói; **chưa đủ để kết luận Linux có Internet**.
- `AT+CPSI?` cho biết LTE band/cell khi firmware hỗ trợ. Log Pi `Raspberry Pi thử nghiệm` chưa có CPSI nên **không khẳng định đang dùng B3 hay B41**.

Thoát minicom: **Ctrl+A**, sau đó **X**. Nếu bị báo cổng bận, đóng minicom rồi mới dùng ModemManager.

## 3. Kết nối Internet qua QMI + NetworkManager (không cố định nhà mạng)

**Chọn nhà mạng tùy ý có hỗ trợ SIM7600 tại khu vực sử dụng.** Điều kiện bắt buộc: SIM còn dịch vụ dữ liệu, trạm LTE hỗ trợ **ít nhất một băng tần của đúng model modem**, và APN chính xác. Không có một APN áp dụng chung cho tất cả nhà mạng.

Kiểm tra modem và các profile đang có:

```bash
mmcli -m 0
nmcli -f NAME,TYPE,DEVICE connection show
nmcli device status
```

**Chỉ dùng một tên profile 4G thống nhất:** `SIM7600_4G` trên cả hai model. Nếu Pi đã có profile GSM từ lần cấu hình trước, **đổi tên profile hiện hữu** thành `SIM7600_4G` (thay `<TEN_PROFILE_4G_CU>` bằng tên thấy trong danh sách), không tạo profile trùng:

```bash
sudo nmcli connection modify '<TEN_PROFILE_4G_CU>' connection.id SIM7600_4G
```

Nếu **chưa có profile 4G**, đoạn lệnh sau sẽ tự tạo. **Nhập APN của nhà mạng đang dùng**, tra trong tài liệu SIM, nhà mạng hoặc cấu hình APN của điện thoại. Không nhập tên nhà mạng thay cho APN.

```bash
read -r -p 'Nhap APN cua nha mang: ' APN
if [ -n "$APN" ]; then
  if ! nmcli -g connection.id connection show SIM7600_4G >/dev/null 2>&1; then
    sudo nmcli connection add type gsm ifname '*' con-name SIM7600_4G apn "$APN"
  fi
  sudo nmcli connection modify SIM7600_4G \
    gsm.apn "$APN" \
    connection.autoconnect yes \
    ipv4.route-metric 700 \
    ipv6.route-metric 700
else
  echo 'APN rong: can nhap APN dung de ket noi.'
fi
unset APN
```

Nếu nhà mạng yêu cầu thêm thông tin xác thực APN (tên người dùng/mật khẩu/PIN), hãy cấu hình tương ứng theo hướng dẫn nhà mạng. Không công khai các thông tin này trong GitHub hoặc lịch sử lệnh.

Chỉ khi đã đặt APN, kích hoạt kết nối:

```bash
sudo nmcli -w 90 connection up SIM7600_4G
```

Kiểm tra **đúng kết nối dữ liệu 4G** thay vì vô tình kiểm tra Internet qua Wi-Fi:

```bash
nmcli connection show --active
ip -br addr show wwan0
ip route
ping -I wwan0 -c 4 8.8.8.8
curl --interface wwan0 -4 --max-time 15 https://api.ipify.org
```

Nếu modem đã `registered` nhưng không lên mạng, kiểm tra lại APN, gói dữ liệu, cấu hình xác thực và log ModemManager. Chỉ số `/dev/cdc-wdmX` có thể đổi sau reboot; không hardcode `cdc-wdm0` hay `cdc-wdm1`.

## 4. Phát Wi-Fi Hotspot qua `wlan0` và chia sẻ Internet 4G

> **Cảnh báo:** Khi chuyển `wlan0` từ Wi-Fi client sang Access Point, phiên SSH qua Wi-Fi trước đó có thể bị ngắt. Nên thao tác tại console hoặc có đường truy cập dự phòng.

Kiểm tra card Wi-Fi có chế độ AP:

```bash
nmcli -f WIFI-PROPERTIES.AP device show wlan0
# Cần hiển thị: yes
```

**Một bộ tên dùng chung cho hai model:** profile 4G `SIM7600_4G`, profile hotspot `SIM7600_Hotspot`, SSID mặc định `SIM7600-Companion`. Nếu sử dụng nhiều Raspberry Pi cạnh nhau, cần đổi SSID để dễ phân biệt thiết bị.

Kiểm tra các profile hiện có, **đổi tên hotspot cũ nếu cần** (thay tên trong ngoặc nhọn bằng tên profile thực tế):

```bash
nmcli -f NAME,TYPE,AUTOCONNECT connection show
sudo nmcli connection modify '<TEN_HOTSPOT_CU>' connection.id SIM7600_Hotspot
```

Nếu **chưa có** profile `SIM7600_Hotspot`, tạo với mật khẩu tự chọn (ít nhất 8 ký tự, không ghi vào lịch sử Bash):

```bash
if ! nmcli -g connection.id connection show SIM7600_Hotspot >/dev/null 2>&1; then
  read -rsp 'Nhap mat khau hotspot (8-63 ky tu): ' HOTSPOT_PSK; echo
  sudo nmcli device wifi hotspot \
    ifname wlan0 \
    con-name SIM7600_Hotspot \
    ssid SIM7600-Companion \
    band bg \
    password "$HOTSPOT_PSK"
  unset HOTSPOT_PSK
fi
```

Đặt IP gateway, bật NAT/DHCP và tự kết nối khi khởi động:

```bash
sudo nmcli connection modify SIM7600_Hotspot \
  ipv4.method shared \
  ipv4.addresses 192.168.50.1/24 \
  ipv6.method disabled \
  connection.autoconnect yes \
  connection.autoconnect-priority 100
sudo nmcli connection modify SIM7600_4G connection.autoconnect yes
sudo nmcli connection up SIM7600_Hotspot
```

Để hotspot ưu tiên sau reboot, **tắt autoconnect của profile Wi-Fi client trước đây** trên `wlan0` nếu có; không xóa Wi-Fi đó. Lấy tên từ `nmcli connection show` và thay `<TEN_WIFI_CU>` bằng tên thật:

```bash
nmcli -f NAME,TYPE,AUTOCONNECT connection show
sudo nmcli connection modify '<TEN_WIFI_CU>' connection.autoconnect no
```

Kiểm tra:

```bash
nmcli connection show --active
ip -br addr show wlan0
ip -br addr show wwan0
ip route
nmcli -f connection.id,connection.autoconnect connection show SIM7600_Hotspot
nmcli -f connection.id,connection.autoconnect connection show SIM7600_4G
```

Dự kiến `wlan0` nhận IP `192.168.50.1/24`; thiết bị kết nối hotspot có thể truy cập Pi tại `192.168.50.1`. Internet chỉ có khi `SIM7600_4G` đã kết nối và được định tuyến/NAT đúng.

Chỉ kiểm tra reboot khi có cách truy cập lại Raspberry Pi:

```bash
sudo reboot
```

Sau khởi động, kiểm tra cả `SIM7600_4G` và `SIM7600_Hotspot` hoạt động. `autoconnect=yes` là cấu hình dự kiến, **không thay thế việc kiểm thử reboot thực tế**.

## 5. Kiểm tra sau khởi động

```bash
nmcli connection show --active
nmcli device status
mmcli -m 0
ip -br addr show wlan0
ip -br addr show wwan0
ip route
ping -I wwan0 -c 4 8.8.8.8
```

Xác nhận `SIM7600_Hotspot` ở `wlan0` với gateway `192.168.50.1`, `SIM7600_4G` kết nối modem QMI và máy khách truy cập được Internet. Khi dùng nhiều Pi, đặt SSID khác nhau để tránh nhầm thiết bị.

## 6. Khắc phục sự cố

| Triệu chứng | Hướng xử lý |
|---|---|
| Không thấy `/dev/ttyUSB*` hoặc `/dev/cdc-wdm*` | Kiểm tra nguồn, cáp USB data, `lsusb -t`, `dmesg`; không đổi USB PID khi QMI hoạt động. |
| Modem chưa đăng ký LTE | Xem `AT+CPIN?`, `AT+CEREG?`, `AT+CPSI?`; kiểm tra anten, độ phủ LTE và các band modem hỗ trợ. |
| Đã đăng ký mạng nhưng không có dữ liệu | Kiểm tra APN của SIM, gói dữ liệu, `AT+CGATT?`, cấu hình xác thực và log. |
| `nmcli connection up` chờ quá lâu | `sudo nmcli -w 30 connection up SIM7600_4G`, `mmcli -m 0`, `journalctl -u ModemManager -u NetworkManager -n 80 --no-pager`. |
| `wwan0` có IP nhưng không có Internet | Kiểm tra `ping -I wwan0`, `ip route`, `resolvectl status`; không tùy tiện xóa `/etc/resolv.conf`. |
| Hotspot có Wi-Fi nhưng không chia sẻ Internet | Kiểm tra 4G connected, NAT qua `ipv4.method shared`, gateway và DHCP client. |

**Bảo mật:** Mạng di động có thể triển khai CGNAT; truy cập SSH trực tiếp từ Internet thường không bảo đảm. Để quản trị thiết bị từ xa, dùng VPN hoặc kết nối chủ động đến server bảo mật.
