#!/bin/bash

# 打印彩色字符画
echo -e "\e[1;32m"  # 设置颜色为亮绿色
cat << "EOF"
脚本作者：
 __      __            _  _  _            _   _         _      _      _        
 \ \    / /           (_)| || |          | \ | |       | |    (_)    | |       
  \ \  / /__ _  _ __   _ | || |  __ _    |  \| |  __ _ | |__   _   __| |  __ _ 
   \ \/ // _` || '_ \ | || || | / _` |   | . ` | / _` || '_ \ | | / _` | / _` |
    \  /| (_| || | | || || || || (_| |   | |\  || (_| || | | || || (_| || (_| |
     \/  \__,_||_| |_||_||_||_| \__,_|   |_| \_| \__,_||_| |_||_| \__,_| \__,_|                                                                                                                                                                                                                               
EOF
echo -e "\e[0m"  # 重置颜色
echo -e "\e[1;36m  小智服务端全量部署一键安装脚本 V0.1 \e[0m\n"
sleep 1



# 检查并安装whiptail
check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "正在安装whiptail..."
        apt update
        apt install -y whiptail
    fi
}

check_whiptail

# 检查root权限
if [ $EUID -ne 0 ]; then
    whiptail --title "权限错误" --msgbox "请使用root权限运行本脚本" 10 50
    exit 1
fi

# 检查系统版本
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
        whiptail --title "系统错误" --msgbox "该脚本只支持Debian/Ubuntu系统执行" 10 60
        exit 1
    fi
else
    whiptail --title "系统错误" --msgbox "无法确定系统版本，该脚本只支持Debian/Ubuntu系统执行" 10 60
    exit 1
fi


# 检查curl安装
if ! command -v curl &> /dev/null; then
    whiptail --title "安装curl" --msgbox "未检测到curl，开始安装..." 10 50
    apt update
    apt install -y curl
else
    echo "curl已安装，跳过安装步骤"
fi

# 检查Docker安装
if ! command -v docker &> /dev/null; then
    whiptail --title "安装Docker" --msgbox "未检测到Docker，开始安装..." 10 50
    apt update
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt update
    apt install -y docker-ce
    systemctl start docker
    systemctl enable docker
else
    echo "Docker已安装，跳过安装步骤"
fi

# 创建安装目录
mkdir -p /opt/xiaozhi-server/data
mkdir -p /opt/xiaozhi-server/models/SenseVoiceSmall
echo "目录创建完成"

# 下载模型文件
MODEL_PATH="/opt/xiaozhi-server/models/SenseVoiceSmall/model.pt"
if [ ! -f "$MODEL_PATH" ]; then
    (
    for i in {1..20}; do
        echo $((i*5))
        sleep 0.5
    done
    ) | whiptail --title "下载中" --gauge "开始下载语音识别模型..." 10 60 0
    curl -fL --progress-bar https://modelscope.cn/models/iic/SenseVoiceSmall/resolve/master/model.pt -o "$MODEL_PATH" || {
        whiptail --title "错误" --msgbox "model.pt文件下载失败" 10 50
        exit 1
    }
else
    echo "model.pt文件已存在，跳过下载"
fi

# 下载配置文件
check_and_download() {
    local filepath=$1
    local url=$2
    if [ ! -f "$filepath" ]; then
        if ! curl -fL --progress-bar "$url" -o "$filepath"; then
            whiptail --title "错误" --msgbox "${filepath}文件下载失败" 10 50
            exit 1
        fi
    else
        echo "${filepath}文件已存在，跳过下载"
    fi
}

check_and_download "/opt/xiaozhi-server/docker-compose_all.yml" "https://ghfast.top/https://raw.githubusercontent.com/xinnan-tech/xiaozhi-esp32-server/refs/heads/main/main/xiaozhi-server/docker-compose_all.yml"
check_and_download "/opt/xiaozhi-server/data/.config.yaml" "https://ghfast.top/https://raw.githubusercontent.com/xinnan-tech/xiaozhi-esp32-server/refs/heads/main/main/xiaozhi-server/config_from_api.yaml"

# Docker镜像源配置
MIRROR_OPTIONS=(
    "1" "轩辕镜像 (推荐)"
    "2" "腾讯云镜像源"
    "3" "中科大镜像源"
    "4" "网易163镜像源"
    "5" "华为云镜像源"
    "6" "阿里云镜像源"
    "7" "自定义镜像源"
    "8" "跳过配置"
)

MIRROR_CHOICE=$(whiptail --title "选择Docker镜像源" --menu "请选择要使用的Docker镜像源" 20 60 10 \
"${MIRROR_OPTIONS[@]}" 3>&1 1>&2 2>&3) || {
    echo "用户取消选择，退出脚本"
    exit 1
}

case $MIRROR_CHOICE in
    1) MIRROR_URL="https://docker.xuanyuan.me" ;;
    2) MIRROR_URL="https://mirror.ccs.tencentyun.com" ;;
    3) MIRROR_URL="https://docker.mirrors.ustc.edu.cn" ;;
    4) MIRROR_URL="https://hub-mirror.c.163.com" ;;
    5) MIRROR_URL="https://05f073ad3c0010ea0f4bc00b7105ec20.mirror.swr.myhuaweicloud.com" ;;
    6) MIRROR_URL="https://registry.aliyuncs.com" ;;
    7) MIRROR_URL=$(whiptail --title "自定义镜像源" --inputbox "请输入完整的镜像源URL:" 10 60 3>&1 1>&2 2>&3) ;;
    8) MIRROR_URL="" ;;
esac

if [ -n "$MIRROR_URL" ]; then
    mkdir -p /etc/docker
    if [ -f /etc/docker/daemon.json ]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
    fi
    cat > /etc/docker/daemon.json <<EOF
{
    "dns": ["8.8.8.8", "114.114.114.114"],
    "registry-mirrors": ["$MIRROR_URL"]
}
EOF
    whiptail --title "配置成功" --msgbox "已成功添加镜像源: $MIRROR_URL\n正在重启Docker服务...\n(按Enter键继续...)" 12 60
    echo "------------------------------------------------------------
"
    systemctl restart docker.service
fi

# 启动Docker服务
(
echo "20"
echo "# 正在拉取Docker镜像..."
echo "这可能需要几分钟时间，请耐心等待"
docker compose -f /opt/xiaozhi-server/docker-compose_all.yml up -d

if [ $? -ne 0 ]; then
    whiptail --title "错误" --msgbox "Docker服务启动失败，请尝试更换镜像源后重新执行本脚本" 10 60
    exit 1
fi

echo "50"
echo "# 正在检查服务启动状态..."
TIMEOUT=300
START_TIME=$(date +%s)
while true; do
    CURRENT_TIME=$(date +%s)
    if [ $((CURRENT_TIME - START_TIME)) -gt $TIMEOUT ]; then
        whiptail --title "错误" --msgbox "服务启动超时，未在指定时间内找到预期日志内容" 10 60
        exit 1
    fi
    
    if docker logs xiaozhi-esp32-server-web 2>&1 | grep -q "Started AdminApplication in"; then
        break
    fi
    sleep 1
done

echo "90"
echo "# 服务端启动成功！正在完成配置..."
) | whiptail --title "服务启动中" --gauge "正在启动服务..." 10 60 0

# 密钥配置
whiptail --title "设置服务器密钥" --msgbox "请使用浏览器，打开智控台并注册账号，链接：http://127.0.0.1:8002/\n如果是公网部署，请更换为 http://你的服务器公网IP地址:8002/ (记得在服务器安全组放行端口)。\n第一个用户即是超级管理员，以后的用户都是普通用户。普通用户只能绑定设备和配置智能体; 超级管理员可以进行模型管理、用户管理、参数配置等功能。\n注册好后请按Enter键继续" 15 70

SECRET_KEY=$(whiptail --title "服务器密钥配置" --inputbox "请使用超级管理员账号登录智控台 (http://127.0.0.1:8002)\n在顶部菜单 参数字典 → 参数管理 找到参数编码: server.secret (服务器密钥) \n复制该参数值并输入到下面输入框\n\n请输入密钥(留空则跳过配置):" 15 60 3>&1 1>&2 2>&3)

if [ -n "$SECRET_KEY" ]; then
    python3 -c "
import sys, yaml; 
config_path = '/opt/xiaozhi-server/data/.config.yaml'; 
with open(config_path, 'r') as f: 
    config = yaml.safe_load(f) or {}; 
config['manager-api'] = {'url': 'http://xiaozhi-esp32-server-web:8002/xiaozhi', 'secret': '$SECRET_KEY'}; 
with open(config_path, 'w') as f: 
    yaml.dump(config, f); 
"
    docker restart xiaozhi-esp32-server
fi

# 获取并显示地址信息
LOCAL_IP=$(hostname -I | awk '{print $1}')
WEBSOCKET_ADDR=$(docker logs xiaozhi-esp32-server 2>&1 | tac | grep -m 1 -E -o "ws://[^ ]+")
VISION_ADDR=$(docker logs xiaozhi-esp32-server 2>&1 | tac | grep -m 1 "视觉" | grep -m 1 -E -o "http://[^ ]+")

whiptail --title "安装完成！" --msgbox "\
管理后台访问地址: http://$LOCAL_IP:8002\n\
OTA 地址: http://$LOCAL_IP:8002/xiaozhi/ota/\n\
视觉分析接口地址: $VISION_ADDR\n\
WebSocket 地址: $WEBSOCKET_ADDR\n\
\n安装完毕！\n按Enter键退出..." 16 70