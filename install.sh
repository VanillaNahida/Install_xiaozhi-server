#!/bin/bash

# 检查系统版本是否为Debian/Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
        echo "该脚本只支持Debian/Ubuntu系统执行" >&2
        exit 1
    fi
else
    echo "无法确定系统版本，该脚本只支持Debian/Ubuntu系统执行" >&2
    exit 1
fi

# 检查是否以root权限运行
if [ $EUID -ne 0 ]; then
    echo "请使用root权限运行本脚本" >&2
    exit 1
fi

# 检查curl是否已安装
if ! command -v curl &> /dev/null; then
    echo "未检测到curl，开始安装..."
    # 更新软件包列表
    apt update
    # 安装curl
    apt install -y curl
else
    echo "curl已安装，跳过安装步骤"
fi

# 检查Docker是否已安装
if ! command -v docker &> /dev/null; then
    echo "未检测到Docker，开始安装..."
    # 安装Docker
    echo "开始安装Docker..."
    
    # 更新软件包列表
    apt update
    
    # 安装依赖包
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    
    # 添加Docker官方GPG密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    
    # 添加Docker稳定版仓库
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    
    # 再次更新软件包列表
    apt update
    
    # 安装Docker CE
    apt install -y docker-ce
    
    # 启动Docker服务并设置开机自启
    systemctl start docker
    systemctl enable docker
else
    echo "Docker已安装，跳过安装步骤"
fi

# 创建安装目录
echo "创建安装目录"
mkdir -p /opt/xiaozhi-server/data
mkdir -p /opt/xiaozhi-server/models/SenseVoiceSmall

echo "目录创建完成"

# 检查并下载model.pt文件
MODEL_PATH="/opt/xiaozhi-server/models/SenseVoiceSmall/model.pt"
if [ ! -f "$MODEL_PATH" ]; then
    echo "开始下载语音识别模型..."
    curl -fL --progress-bar https://modelscope.cn/models/iic/SenseVoiceSmall/resolve/master/model.pt -o "$MODEL_PATH"
    if [ $? -eq 0 ]; then
        echo "model.pt文件下载成功"
      else
          echo "model.pt文件下载失败" >&2
          exit 1
      fi
  else
      echo "model.pt文件已存在，跳过下载"

      # 检查docker-compose_all.yml文件是否存在
      if [ ! -f /opt/xiaozhi-server/docker-compose_all.yml ]; then
          echo "开始下载docker-compose_all.yml文件..."
          curl -fL --progress-bar https://ghfast.top/https://raw.githubusercontent.com/xinnan-tech/xiaozhi-esp32-server/refs/heads/main/main/xiaozhi-server/docker-compose_all.yml -o /opt/xiaozhi-server/docker-compose_all.yml
          if [ $? -eq 0 ]; then
              echo "docker-compose_all.yml文件下载成功"
          else
              echo "docker-compose_all.yml文件下载失败" >&2
              exit 1
          fi
      else
          echo "docker-compose_all.yml文件已存在，跳过下载"
      fi

      # 检查.config.yaml文件是否存在
      if [ ! -f /opt/xiaozhi-server/data/.config.yaml ]; then
          echo "开始下载config_from_api.yaml文件..."
          curl -fL --progress-bar https://ghfast.top/https://raw.githubusercontent.com/xinnan-tech/xiaozhi-esp32-server/refs/heads/main/main/xiaozhi-server/config_from_api.yaml -o /opt/xiaozhi-server/data/.config.yaml
          if [ $? -eq 0 ]; then
              echo ".config.yaml文件下载并重命名成功"
          else
              echo "config_from_api.yaml文件下载失败" >&2
              exit 1
          fi
      else
          echo ".config.yaml文件已存在，跳过下载"
      fi
  fi

# 启动Docker服务
cd /opt/xiaozhi-server

# 配置Docker国内镜像源
# Docker镜像源配置脚本
# 支持国内主流镜像源，包括新添加的轩辕镜像
# 执行需要root权限

if [[ $EUID -ne 0 ]]; then
    echo "请使用root权限执行此脚本"
    exit 1
fi

# 配置镜像源选项
cat << EOF
请选择要使用的Docker镜像源：
1) 轩辕镜像 (推荐)
2) 腾讯云镜像源
3) 中科大镜像源
4) 网易163镜像源
5) 华为云镜像源
6) 阿里云镜像源
7) 自定义镜像源
8) 跳过配置Docker镜像源
EOF

read -p "输入选项编号 (默认为1): " choice
choice=${choice:-1}  # 默认选择轩辕镜像

case $choice in
    1) MIRROR_URL="https://docker.xuanyuan.me" ;; 
    2) MIRROR_URL="https://mirror.ccs.tencentyun.com" ;; 
    3) MIRROR_URL="https://docker.mirrors.ustc.edu.cn" ;; 
    4) MIRROR_URL="https://hub-mirror.c.163.com" ;; 
    5) MIRROR_URL="https://05f073ad3c0010ea0f4bc00b7105ec20.mirror.swr.myhuaweicloud.com" ;; 
    6) MIRROR_URL="https://registry.aliyuncs.com" ;; 
    7) read -p "请输入完整的镜像源URL: " MIRROR_URL ;; 
    8) MIRROR_URL="" ;; 
    *) echo "无效选择，使用默认镜像源"
       MIRROR_URL="https://docker.xuanyuan.me" ;; 
esac

# 如果选择跳过配置，则不执行后续步骤
if [ -n "$MIRROR_URL" ]; then
    # 创建配置文件目录
    mkdir -p /etc/docker

    # 检查并备份现有配置
    if [ -f /etc/docker/daemon.json ]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
        echo "已备份原配置文件 -> /etc/docker/daemon.json.bak"
    fi

    # 创建或修改配置
    cat > /etc/docker/daemon.json << EOF
{
    "dns": ["8.8.8.8", "114.114.114.114"],
    "registry-mirrors": ["$MIRROR_URL"]
}
EOF

    echo "------------------------------------------------------------------"
    echo "已成功添加镜像源: $MIRROR_URL"
    echo "配置文件路径: /etc/docker/daemon.json"
    echo "新配置内容:"
    cat /etc/docker/daemon.json
    echo "------------------------------------------------------------------"

    # 重启Docker服务
    echo "正在重启Docker服务应用更改..."
    systemctl restart docker.service
    echo "Docker服务已重启，新配置生效"

else
    echo "------------------------------------------------------------------"
    echo "已选择跳过Docker镜像源配置"
    echo "------------------------------------------------------------------"
fi


# 以 detached 模式启动所有服务
 echo "拉取并启动Docker镜像中..."
 echo "过程可能会很慢，请耐心等待~ o((>ω< ))o"
 docker compose -f docker-compose_all.yml up -d
 if [ $? -eq 0 ]; then
     echo "Docker服务启动成功"
 else
     echo "Docker服务启动失败，请尝试更换镜像源后，重新执行本脚本（安装进度将保留）" >&2
     exit 1
 fi

# 显示xiaozhi-esp32-server-web容器的日志
 echo "检查服务启动状态..."

# 设置超时时间（秒）
TIMEOUT=300
# 记录开始时间
START_TIME=$(date +%s)

# 循环检查日志
while true; do
    # 检查是否超时
    CURRENT_TIME=$(date +%s)
    if [ $((CURRENT_TIME - START_TIME)) -gt $TIMEOUT ]; then
        echo "服务可能启动超时，未在指定时间内找到预期日志内容" >&2
        exit 1
    fi
    
    # 检查日志中是否包含目标字符串
    if docker logs xiaozhi-esp32-server-web 2>&1 | grep -q "Started AdminApplication in"; then
        echo "服务端启动成功！"
        echo "------------------------------说明--------------------------------"
        echo "请使用浏览器，打开智控台，链接：http://127.0.0.1:8002
如果是公网部署，请更换为 http://你的服务器公网IP地址:8002 (记得在服务器安全组放行端口)
在智控台注册第一个用户。第一个用户即是超级管理员，以后的用户都是普通用户。普通用户只能绑定设备和配置智能体;超级管理员可以进行模型管理、用户管理、参数配置等功能。"
        echo "------------------------配置服务器密钥-----------------------------"
        break
    fi
    # 等待1秒后再次检查
    sleep 1
done

# 继续显示日志
#  docker logs -f xiaozhi-esp32-server-web

# 停止所有正在运行的容器的命令
# docker stop $(docker ps -q)

# 调用Python3执行服务器密钥填写脚本
 echo "请使用超级管理员账号，登录智控台，在顶部菜单“参数字典“找到“参数管理“，找到列表中第一条数据，参数编码是server.secret，复制这个参数值。
复制参数值后，请将其粘贴到这里，然后按回车确定。"
 python3 -c "
import sys, yaml; 
config_path = '/opt/xiaozhi-server/data/.config.yaml'; 
with open(config_path, 'r') as f: 
    config = yaml.safe_load(f); 
    secret = input('请输入密钥（为空为跳过配置）: ')
    if secret == '':
        print('未输入内容，跳过配置密钥')
    else:
        config['manager-api'] = {'url': 'http://xiaozhi-esp32-server-web:8002/xiaozhi', 'secret': secret}; 
        with open(config_path, 'w') as f: 
            yaml.dump(config, f); 
            print('密钥已成功写入配置文件')
"

 if [ $? -eq 0 ]; then
     echo "配置成功，正在重启服务应用更改..."
     docker restart xiaozhi-esp32-server

 else
     echo "服务器密钥配置失败，请检查后再试一次。" >&2
     exit 1
 fi

echo "安装完成，请将下列输出的OTA地址和Websocket地址，填写到智控台。"
# Websocket地址
websocket_address=$(docker logs xiaozhi-esp32-server 2>&1 | tac | grep -m 1 -E -o "ws://[^ ]+")
# 视觉地址
vision_address=$(docker logs xiaozhi-esp32-server 2>&1 | tac | grep -m 1 "视觉" | grep -m 1 -E -o "http://[^ ]+")
# OTA地址
ota_address=$(docker logs xiaozhi-esp32-server 2>&1 | tac | grep -m 1 "OTA" | grep -m 1 -E -o "http://[^ ]+")

# 获取本地IP地址
local_ip=$(hostname -I | awk '{print $1}')

echo "------------------------------------------------------------------"
echo "OTA 地址：http://$local_ip:8002/xiaozhi/ota/"
echo "视觉地址：$vision_address"
echo "Websocket 地址：$websocket_address"
echo "------------------------------------------------------------------"
