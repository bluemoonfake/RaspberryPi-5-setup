# SIM7600NA-H — Raspberry Pi 5 + Viettel LTE B41 (QMI) + Wi-Fi Hotspot

> **Phạm vi:** SIMCOM SIM7600NA-H (bản North America), HAT hoặc USB data trên Raspberry Pi 5, Ubuntu 24.04. Đây là **modem 4G LTE Cat 4, không phải 5G NR**.
>
> **Đã kiểm chứng tại `ctuav10`:** kết nối Viettel **LTE TDD B41**, QMI/NetworkManager, ping qua `wwan0` thành công và `curl` trả public IP. Tốc độ một lần đo: download **30.39 Mbps**, upload **5.89 Mbps** tới server Singapore, không đại diện cho mọi nơi. Profile hotspot `CTUAV_Hotspot` đã active trong log. **Chưa có kết quả reboot xác nhận tự khởi động.**
>
> **Cảnh báo băng tần:** SIM7600NA-H hỗ trợ các band FDD Bắc Mỹ (B2/4/5/12/13/14/25/26/66/71) và TDD B41. Không hỗ trợ LTE FDD B1/B3/B8 phổ biến tại Việt Nam. Nó hoạt động ở vị trí thử nghiệm nhờ **LTE B41 của Viettel**; không suy ra phủ sóng B41 toàn quốc. **Không ép sang FDD B4 chỉ để tăng tốc**: đã thử và modem bị `searching`, `detached`, `Network timeout`.
>
> Hướng dẫn gốc PPP/ECM tham khảo tại [main](https://github.com/bluemoonfake/RaspberryPi-5-setup/blob/main/2nd_dougle_4g_setup.md). Nếu USB có driver `qmi_wwan`, **không** chuyển `AT+CUSBPIDSWITCH`, quay số PPP hay xóa `/etc/resolv.conf`.

## 0. Đấu nối và cài gói

- Cắm SIM Viettel đã kích hoạt dữ liệu; gắn anten và cấp nguồn đúng hướng dẫn phần cứng.
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
+COPS: 0,0,"Viettel Viettel",7
+CPSI: LTE,Online,...,EUTRAN-BAND41,40590,...
+CGATT: 1
```

Một lần trước báo EARFCN `40390`, lần sau `40590`; tương ứng xấp xỉ 2570 và 2590 MHz trong LTE B41. Cùng B41 không đồng nghĩa tốc độ giống nhau; đòi hỏi đo RSRP/RSRQ/SINR, upload, packet loss và độ trễ theo vị trí. `AT+CSQ` đôi khi trả `ERROR` trong log, nhưng các chỉ số `CEREG`, `CPSI` và dữ liệu thực tế mới quyết định kết nối thành công.

Thoát minicom bằng **Ctrl+A**, rồi **X**.

## 2. Kết nối Internet qua QMI + Viettel APN

Xác nhận ModemManager có trạng thái `registered`, `lte`, `packet service state: attached`:

```bash
mmcli -m 0
nmcli device status
```

Trong ví dụ `ctuav10`, profile được đặt tên `CTUAV_companion_computer_1`. **Chỉ tạo nếu chưa có**:

```bash
nmcli connection show CTUAV_companion_computer_1
# Nếu báo "unknown connection" thì mới tạo:
sudo nmcli connection add type gsm ifname '*' \
  con-name CTUAV_companion_computer_1 apn v-internet
```

```bash
sudo nmcli connection modify CTUAV_companion_computer_1 \
  gsm.apn v-internet \
  connection.autoconnect yes \
  ipv4.route-metric 700 \
  ipv6.route-metric 700
sudo nmcli -w 90 connection up CTUAV_companion_computer_1
```

Kiểm tra Internet **theo interface 4G** (không dùng Wi-Fi khi đo):

```bash
ip -br addr show wwan0
nmcli connection show --active
ip route
ping -I wwan0 -c 4 8.8.8.8
curl --interface wwan0 -4 --max-time 15 https://api.ipify.org
```

Trên Pi thử nghiệm, `wwan0` đã nhận địa chỉ private từ modem; 4/4 ping thành công và có IP public ở phía nhà mạng. IP này có thể thay đổi; IP nội bộ kiểu `10.x.x.x` có thể cho thấy NAT phía nhà mạng, **không dùng nó làm địa chỉ SSH trực tiếp từ Internet**.

## 3. Tạo Hotspot trên `wlan0`, tự bật sau khởi động

**Cảnh báo:** `wlan0` sẽ ngắt kết nối Wi-Fi cũ `CTGROUP-F5` để chuyển sang AP. Nếu đang SSH qua Wi-Fi đó, sẽ mất phiên SSH.

```bash
nmcli -f WIFI-PROPERTIES.AP device show wlan0
# Phải là "yes"
```

Chỉ tạo profile nếu chưa có `CTUAV_Hotspot`. Để không ghi mật khẩu vào shell history:

```bash
read -rsp 'Nhap mat khau hotspot (8-63 ky tu): ' HOTSPOT_PSK; echo
sudo nmcli device wifi hotspot \
  ifname wlan0 \
  con-name CTUAV_Hotspot \
  ssid CTUAV-companion-computer-1 \
  band bg \
  password "$HOTSPOT_PSK"
unset HOTSPOT_PSK
```

Nếu profile đã có, không tạo lại. Có thể đổi mật khẩu mà không lưu nó trong shell history:

```bash
read -rsp 'Mat khau hotspot moi: ' HOTSPOT_PSK; echo
sudo nmcli connection modify CTUAV_Hotspot wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PSK"
unset HOTSPOT_PSK
sudo nmcli connection up CTUAV_Hotspot
```

```bash
sudo nmcli connection modify CTUAV_Hotspot \
  ipv4.method shared \
  ipv4.addresses 192.168.50.1/24 \
  ipv6.method disabled \
  connection.autoconnect yes \
  connection.autoconnect-priority 100
```

Nếu muốn Pi **luôn phát hotspot** sau reboot, tắt autoconnect của profile Wi-Fi cũ và bật 4G:

```bash
sudo nmcli connection modify 'CTGROUP-F5' connection.autoconnect no
sudo nmcli connection modify CTUAV_companion_computer_1 connection.autoconnect yes
sudo nmcli connection up CTUAV_Hotspot
```

Xác nhận:

```bash
nmcli connection show --active
ip -br addr show wlan0
ip route
nmcli -f connection.id,connection.autoconnect connection show CTUAV_Hotspot
nmcli -f connection.id,connection.autoconnect connection show CTUAV_companion_computer_1
```

Dự kiến: `wlan0=192.168.50.1/24`, `CTUAV_Hotspot` ở `wlan0`, `CTUAV_companion_computer_1` ở `cdc-wdmX`, default route qua `wwan0` khi Wi-Fi không còn kết nối ngoài. Từ laptop nối hotspot, thử `ssh ctuav10@192.168.50.1` và truy cập Internet.

Kiểm thử sau khi bảo đảm có đường truy cập lại:

```bash
sudo reboot
```

Sau reboot xác nhận cả hotspot và modem tự kết nối. Chỉ thấy `autoconnect=yes` **không tự chứng minh** quá trình reboot thành công.

## 4. Lỗi đã gặp: khóa LTE FDD B4 làm `nmcli` chờ mãi

**Triệu chứng đã quan sát khi chạy** `sudo mmcli -m 0 --set-current-bands=eutran-4`:

```text
Bands | current: eutran-4
Status | state: searching
signal quality: 0%
3GPP registration: searching
packet service state: detached
ModemManager: registration in network failed: Network timeout
nmcli -w 20 connection up ... => Error: Timeout expired
```

**Nguyên nhân:** B4 có trong phần cứng SIM7600NA-H nhưng không có bằng chứng Viettel phát LTE B4 ở vị trí thử; hạn chế chỉ B4 khiến modem không đăng ký được. Không phải lỗi hotspot, APN hay QMI.

**Phục hồi an toàn:** Trên console hoặc SSH qua hotspot (không phụ thuộc đường Internet 4G bị lỗi), tắt tự kết nối, ngắt yêu cầu đang treo, bỏ giới hạn băng tần:

```bash
sudo nmcli connection modify CTUAV_companion_computer_1 connection.autoconnect no
nmcli device status    # xem cdc-wdm0 / cdc-wdm1 hiện tại
# Chọn tên thiết bị GSM đúng theo kết quả ở trên; ví dụ:
sudo nmcli device disconnect cdc-wdm0
sudo mmcli -m 0 --set-current-bands=any
mmcli -m 0 | sed -n '/Bands/,/IP/p'
```

Chờ 30–90 giây rồi kiểm tra `state: registered`, `registration: home`, `packet service state: attached`:

```bash
mmcli -m 0
sudo nmcli connection modify CTUAV_companion_computer_1 connection.autoconnect yes
sudo nmcli -w 90 connection up CTUAV_companion_computer_1
ping -I wwan0 -c 4 8.8.8.8
```

Nếu `--set-current-bands=any` báo lỗi hoặc chưa thoát `searching`, **dừng và lấy log**, đừng thử thay đổi USB PID hay reset GPIO khi chưa biết tình trạng phần cứng:

```bash
sudo journalctl -u NetworkManager -u ModemManager -n 80 --no-pager
mmcli -m 0
```

**Ghi nhớ:** FDD không mặc định nhanh hơn TDD. Chỉ thay band khi thật sự có trạm phục vụ band đó. Để đánh giá UAV, cần đo **uplink liên tục**, mất gói, jitter và khả năng chuyển cell theo địa điểm. SIM7600G-H là lựa chọn phù hợp hơn nếu phải di chuyển qua nhiều vùng có B1/B3/B8.

## 5. Checklist kiểm tra cuối

- [ ] Modem SIM7600NA-H xuất hiện qua USB, `qmi_wwan` hoạt động và ModemManager nhận được.
- [ ] SIM sẵn sàng, `CEREG` đăng ký Viettel, `CPSI` thấy một LTE band tương thích.
- [ ] `Bands/current` **không** bị khóa nhầm sang `eutran-4`.
- [ ] `wwan0` nhận IPv4; `ping -I wwan0` và `curl --interface wwan0` thành công.
- [ ] Hotspot phát SSID mong muốn, client nhận gateway `192.168.50.1` và vào được Internet.
- [ ] Profile 4G và AP đều `connection.autoconnect yes`; Wi-Fi cũ không giành `wlan0`.
- [ ] Sau `sudo reboot`, cả 4G và hotspot hoạt động lại (cần **kiểm chứng thực tế**).

Không sử dụng bất kỳ file/script reset cứng modem qua GPIO nào khi chưa biết chính xác sơ đồ chân PWRKEY/RESET và phiên bản HAT. LTE qua mạng di động có thể không cho phép SSH trực tiếp từ Internet; dùng VPN nếu cần truy cập từ xa.