#!/bin/bash
# --- Cấu hình ---
# User sẽ chạy các node ROS 2
USERNAME="trinhsat1"

# Phiên bản ROS 2
ROS_DISTRO="jazzy"

# Cấu hình FFmpeg Stream
FFMPEG_RTSP_INPUT="rtsp://192.168.144.25:8554/main.264"
FFMPEG_RTSP_OUTPUT="rtsp://14.161.17.92:8554/node_cam1"
# --- Hết cấu hình ---

WORKSPACE_DIR="/home/$USERNAME/Fire-Shield"

echo "--- Bắt đầu dịch vụ UAV (Chế độ phân quyền Root/User) ---"

# ==========================================================
# == PHẦN 1: CÁC LỆNH CHẠY VỚI QUYỀN ROOT ==
# ==========================================================

# 1. Chạy microRTPS agent (bằng root)
echo "Starting RTPS Agent (as root)..."
MicroXRCEAgent serial --dev /dev/ttyAMA10 -b 921600 &
RTPS_PID=$!

sleep 1 # Đợi agent khởi động

# 2. Cấu hình camera A8mini (bằng root)
echo "Configuring eth0 (as root)..."
/usr/sbin/ethtool -s eth0 speed 10 duplex full autoneg off
sleep 1

# ==========================================================
# == PHẦN 2: CÁC LỆNH CHẠY VỚI QUYỀN USER ($USERNAME) VÀ LOG ==
# ==========================================================

# KHẮC PHỤC LỖI LOG: Đảm bảo thư mục log tồn tại và có quyền chính xác
LOG_DIR="/home/$USERNAME/logs_uav_service" # Đặt logs vào thư mục con chuyên biệt
mkdir -p "$LOG_DIR"
chown $USERNAME:$USERNAME "$LOG_DIR" || true
chmod 755 "$LOG_DIR" || true # Cấp quyền 755 cho thư mục

LOG_FILE="$LOG_DIR/uav_log_$(date +%Y%m%d_%H%M%S).txt"
# Tạo file và đặt quyền chính xác
touch "$LOG_FILE"
chown $USERNAME:$USERNAME "$LOG_FILE" || true
chmod 664 "$LOG_FILE" || true

# Chuẩn bị chuỗi lệnh source môi trường cho user
USER_SETUP_CMD="source /opt/ros/$ROS_DISTRO/setup.bash; source $WORKSPACE_DIR/install/setup.bash"

# Prepend ISO8601-UTC (micro-giây thật) cho MỌI dòng log và ghi vào file + console
exec > >(
  while IFS= read -r line; do
    printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%S.%6NZ')" "$line"
  done | tee -a "$LOG_FILE"
) 2>&1
echo "=== UAV startup log ==="
echo "Time: $(date)"
echo "----------------------"


# ==========================================================
# == PHẦN 3: NODE MQTT BRIDGE (Vòng lặp tự khởi động lại) ==
# ==========================================================

# 3. Chạy node MQTT bridge (bằng user $USERNAME)
MQTT_CMD="ros2 run fire_shield_mqtt_bridge mqtt_bridge"

# Hàm chạy MQTT Bridge tự khởi động lại
run_mqtt_bridge() {
    while true
    do
        echo "--- Khởi động MQTT Bridge (as $USERNAME) vào $(date) ---"
        
        # Chạy node với quyền của $USERNAME
        sudo -H -u $USERNAME bash -c "$USER_SETUP_CMD; $MQTT_CMD"
        
        EXIT_CODE=$?
        
        if [ $EXIT_CODE -ne 0 ]; then
            echo "MQTT Bridge bị lỗi (Mã thoát: $EXIT_CODE). Chờ 5 giây trước khi thử lại..."
        else
            echo "MQTT Bridge kết thúc. Chờ 5 giây trước khi thử lại..."
        fi
        
        sleep 5
    done
}

# Chạy vòng lặp MQTT Bridge ở chế độ nền (Background)
run_mqtt_bridge &
MQTT_LOOP_PID=$!


# ==========================================================
# == PHẦN 4: NODE GPS SETPOINT (Chạy một lần) ==
# ==========================================================

# 4. Chạy node GPS Setpoint (bằng user $USERNAME)
echo "Starting GPS Setpoint Controller (as $USERNAME)..."
GPS_CMD="ros2 run uav_controller no_payload_uav_controller"
# Node này chạy 1 lần. Nếu crash, nó không tự restart.
sudo -H -u $USERNAME bash -c "$USER_SETUP_CMD; $GPS_CMD" &


# ==========================================================
# == PHẦN 5: CAMERA STREAM (Vòng lặp FFmpeg) ==
# ==========================================================

# Cấu hình lệnh FFmpeg (Bitrate 1500k, 15 FPS để tiết kiệm 4G)
FFMPEG_CMD="ffmpeg -hide_banner -loglevel warning\
    -rtsp_transport tcp     -fflags nobuffer+genpts+flush_packets \
    -probesize 300k -analyzeduration 300k    \
    -i $FFMPEG_RTSP_INPUT  \
    -c copy     -map 0     -f rtsp -rtsp_transport tcp \
    -muxdelay 0.1 $FFMPEG_RTSP_OUTPUT"

# Hàm chạy FFmpeg tự khởi động lại
run_ffmpeg() {
    while true
    do
        echo "--- Khởi động luồng FFmpeg (as $USERNAME) vào $(date) ---"
        
        # Chạy FFmpeg với quyền của $USERNAME
        sudo -H -u $USERNAME bash -c "$FFMPEG_CMD"
        
        EXIT_CODE=$?
        
        if [ $EXIT_CODE -ne 0 ]; then
            echo "FFmpeg bị lỗi (Mã thoát: $EXIT_CODE). Chờ 5 giây trước khi thử lại..."
        else
            echo "FFmpeg kết thúc. Chờ 5 giây trước khi thử lại..."
        fi
        
        sleep 5
    done
}

# Chạy vòng lặp FFmpeg ở chế độ nền (Background)
run_ffmpeg &
FFMPEG_LOOP_PID=$!


# ==========================================================
# == PHẦN 6: CLEANUP VÀ GIÁM SÁT ==
# ==========================================================

# Hàm cleanup khi service bị stop
cleanup() {
    echo "Shutting down nodes..."
    
    # 1. Giết vòng lặp MQTT Bridge
    kill $MQTT_LOOP_PID 2>/dev/null
    
    # 2. Giết vòng lặp FFmpeg
    kill $FFMPEG_LOOP_PID 2>/dev/null
    
    # 3. Giết tiến trình RTPS Agent (chạy bằng root)
    kill $RTPS_PID 2>/dev/null
    
    # 4. Giết các tiến trình ROS 2 còn lại (tìm qua tên lệnh)
    # Cần giết node GPS Setpoint vì nó chạy 1 lần không có vòng lặp
    sudo -u $USERNAME pkill -f 'no_payload_uav_controller'
    
    echo "Cleanup hoàn tất."
    exit 0
}

# Bắt các tín hiệu dừng
trap cleanup SIGINT SIGTERM SIGHUP

echo "--- Tất cả các node đã chạy. Service đang hoạt động. ---"

# Đợi tiến trình root (RTPS Agent) kết thúc
wait $RTPS_PID

# Trường hợp wait $RTPS_PID kết thúc:
echo "RTPS Agent (chạy bằng root) đã dừng. Thực hiện cleanup."
cleanup
