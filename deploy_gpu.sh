#!/bin/bash

# ==============================================================================
# 环境配置
# ==============================================================================
USERNAME=$(whoami)          # 当前用户名
BASE_DIR="/home/${USERNAME}"  # 项目根目录
ENV_DIR="${BASE_DIR}/xinference_env"  # 虚拟环境路径
SERVICE_NAME="xinference"   # Systemd 服务名
PORT="9997"                 # 服务端口
DATA_DIR="${BASE_DIR}/.xinference"  # 持久化数据目录（默认 Xinference 数据目录）

# ==============================================================================
# 基础依赖安装
# ==============================================================================
echo ">>> 安装系统依赖（需 sudo 权限）"
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y \
    build-essential \
    python3-dev \
    python3-venv \
    git \
    curl \
    libnvidia-common-570  # 显卡驱动依赖
sudo apt clean

# ==============================================================================
# 创建虚拟环境并安装 Xinference
# ==============================================================================
echo ">>> 创建虚拟环境并激活"
python3 -m venv "${ENV_DIR}"
source "${ENV_DIR}/bin/activate"

echo ">>> 安装 Xinference（GPU 版本）"
pip install xinference --no-cache-dir

# ==============================================================================
# 配置持久化数据目录
# ==============================================================================
echo ">>> 创建数据持久化目录"
mkdir -p "${DATA_DIR}/models"  # 模型存储目录
mkdir -p "${DATA_DIR}/configs"  # 配置存储目录

# ==============================================================================
# 编写 Systemd 服务文件
# ==============================================================================
echo ">>> 配置开机自动启动服务"
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF >/dev/null
[Unit]
Description=Xinference Model Serving Service
After=network.target
Requires=nvidia-persistenced.service

[Service]
User=${USERNAME}
Environment="PATH=${ENV_DIR}/bin:%PATH%"
ExecStart=${ENV_DIR}/bin/xinference-local --host 0.0.0.0 --port ${PORT}
WorkingDirectory=${BASE_DIR}
Restart=always
RestartSec=10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# ==============================================================================
# 启动服务并设置开机自启
# ==============================================================================
echo ">>> 启动服务并设置开机自启"
sudo systemctl daemon-reload
sudo systemctl enable --now "${SERVICE_NAME}.service"

# ==============================================================================
# 验证部署
# ==============================================================================
echo ">>> 验证服务状态"
systemctl status "${SERVICE_NAME}.service" --no-pager

echo ">>> 部署完成！"
echo "  - 服务端口：http://localhost:${PORT}/docs"
echo "  - 数据目录：${DATA_DIR}"
echo "  - 重启后自动启动（通过 Systemd 管理）"
