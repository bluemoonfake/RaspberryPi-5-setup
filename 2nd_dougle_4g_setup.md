# Hướng dẫn cấu hình 4G LTE SIM7600 trên Raspberry Pi 5

**Model:** SIM7600NA-H — HAT hoặc USB data (phiên bản hỗ trợ các band Bắc Mỹ và LTE TDD B41).

> **Hướng dẫn không phụ thuộc nhà mạng:** dùng QMI + NetworkManager với **APN do chính nhà mạng của SIM cung cấp**. SIM7600NA-H là modem **4G LTE Cat 4**, không phải 5G NR. Không có bảo đảm mọi nhà mạng đều tương thích: nhà mạng bắt buộc phải triển khai ít nhất một **băng tần hỗ trợ bởi SIM7600NA-H** tại khu vực sử dụng.
>
> **Băng tần phần cứng:** LTE-FDD B2/B4/B5/B12/B13/B14/B25/B26/B66/B71; LTE-TDD B41. **B4 có trong phần cứng không đồng nghĩa nơi bạn đứng có trạm B4.** Không ép modem sang B4 chỉ vì nghĩ FDD nhanh hơn TDD.
>
> **Kiểm chứng:** QMI, `wwan0` và truy cập Internet qua LTE B41 đã hoạt động trong thử nghiệm thực tế; một lần Speedtest là 30,39 Mbps download / 5,89 Mbps upload, không bảo đảm ở vùng khác. Chưa có xác nhận tự khởi động sau reboot.
>
> Khi USB đã dùng `qmi_wwan`, không chuyển USB PID hoặc quay số PPP theo hướng dẫn cũ.

## 0. Đấu nối và cài gói

- Cắm SIM nhà mạng đã kích hoạt dữ liệu; gắn anten và cấp nguồn đúng hướng dẫn phần cứng.
- Nếu là HAT, kiểm tra jumper nguồn và **cáp USB data** kết nối với Pi; header GPIO không thay thế kênh QMI qua USB.
- Nếu đang SSH qua `wlan0`, thao tác hotspot sẽ ngắt phiên SSH. Dùng console hoặc đường truy cập khác.
- Không đưa IMEI, ICCID, mật khẩu hotspot hay log có thông tin nhạy cảm lên GitHub public.

```bash
sudo apt update
sudo apt install -y modemmanager network-manager minicom curl usbutils
sudo systemctl enable --now ModemManager NetworkManager
lsusb
lsusb -t
ls /dev/ttyUSB*
ls /dev/cdc-wdm*
ip -br link
mmcli -L
mmcli -m 0
nmcli device status
```

**Đã quan sát:** USB `1e0e:9001`; driver `option` + `qmi_wwan`; AT port `ttyUSB2`; data `wwan0`; control port có lúc `/dev/cdc-wdm1`, sau reboot thành `/dev/cdc-wdm0`. **Không hardcode `cdc-wdm1`**.

## 1. Xác nhận module, SIM và LTE B41 qua AT

```bash
sudo minicom -D /dev/ttyUSB2 -b 115200
```

Nhập **trong minicom**:

```text
AT
ATI
AT+CPIN?
AT+CSQ
AT+CEREG?
AT+COPS?
AT+CPSI?
AT+CGATT?
```

Kết quả thử nghiệm:

```text
Model: SIMCOM_SIM7600NA-H
+CPIN: READY
+CEREG: 0,1
+COPS: 0,0,"nhà mạng nhà mạng",7
+CPSI: LTE,Online,...,EUTRAN-BAND41,40590,...
+CGATT: 1
```

Một lần trước báo EARFCN `40390`, lần sau `40590`; tương ứng xấp xỉ 2570 và 2590 MHz trong LTE B41. Cùng B41 không đồng nghĩa tốc độ giống nhau; đòi hỏi đo RSRP/RSRQ/SINR, upload, packet loss và độ trễ theo vị trí. `AT+CSQ` đôi khi trả `ERROR` trong log, nhưng các chỉ số `CEREG`, `CPSI` và dữ liệu thực tế mới quyết định kết nối thành công.

Thoát minicom bằng **Ctrl+A**, rồi **X**.

## 2. Kết nối Internet qua QMI + NetworkManager (không cố định nhà mạng)

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

## 3. Phát Wi-Fi Hotspot qua `wlan0` và chia sẻ Internet 4G

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

## 4. Khôi phục khi khóa nhầm LTE Band khiến không đăng ký được mạng

Đây là tình huống từng gặp khi giới hạn modem chỉ dùng `eutran-4` tại vị trí **không phát hiện được trạm LTE B4 tương thích**:

```text
Bands | current: eutran-4
Status | state: searching
signal quality: 0%
3GPP registration: searching
packet service state: detached
ModemManager: registration in network failed: Network timeout
```

**Nguyên nhân:** Khóa band không có trạm tương thích có thể khiến modem mất dịch vụ, dù SIM có gói dữ liệu. Không có căn cứ quy lỗi cho APN nếu modem chưa đăng ký mạng.

**Khôi phục qua console hoặc Wi-Fi hotspot nội bộ** (tránh thao tác từ xa thông qua chính kết nối 4G đang lỗi):

```bash
sudo nmcli connection modify SIM7600_4G connection.autoconnect no
nmcli device status
# Chỉ ngắt thiết bị GSM đúng tên hiển thị ở trên; ví dụ:
sudo nmcli device disconnect cdc-wdm0
sudo mmcli -m 0 --set-current-bands=any
mmcli -m 0
```

Chờ modem đăng ký lại mạng; nếu thấy `registered` và `packet service state: attached`, kết nối trở lại:

```bash
sudo nmcli connection modify SIM7600_4G connection.autoconnect yes
sudo nmcli -w 90 connection up SIM7600_4G
ping -I wwan0 -c 4 8.8.8.8
```

Nếu `--set-current-bands=any` báo lỗi, dừng và lấy log, không thay đổi USB PID hoặc reset GPIO tùy tiện:

```bash
sudo journalctl -u NetworkManager -u ModemManager -n 80 --no-pager
mmcli -m 0
```

FDD không mặc định nhanh hơn TDD. Hãy đánh giá **upload liên tục, độ trễ, jitter, mất gói và khả năng chuyển cell** ở địa điểm triển khai.

## 5. Danh sách kiểm tra hoàn tất

- [ ] Modem xuất hiện qua USB; driver `qmi_wwan`, cổng AT và `wwan0` hoạt động.
- [ ] SIM hợp lệ, đã đăng ký mạng và band LTE tương thích với nhà mạng ở vị trí sử dụng.
- [ ] Đã nhập đúng APN của SIM; không khóa nhầm band không có sóng.
- [ ] `SIM7600_4G` kết nối thành công; ping/curl qua `wwan0` hoạt động.
- [ ] `SIM7600_Hotspot` phát Wi-Fi và máy khách có Internet.
- [ ] Hai profile có `connection.autoconnect yes`; Wi-Fi client cũ không giành `wlan0`.
- [ ] Đã kiểm chứng cả Internet và hotspot sau reboot.

**Lưu ý:** Không dùng script reset cứng qua GPIO nếu chưa xác định sơ đồ chân PWRKEY/RESET của board. Mạng di động có thể triển khai CGNAT; muốn quản trị từ xa nên dùng VPN hoặc kết nối chủ động đến server.
