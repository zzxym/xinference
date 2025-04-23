#!/bin/bash

# ==============================================================================
# 环境配置（可通过环境变量覆盖）
# ==============================================================================
USERNAME="${USERNAME:-$(whoami)}"          # 当前用户名
BASE_DIR="${BASE_DIR:-/opt/xinference}"     # 项目根目录
ENV_DIR="${BASE_DIR}/env"                  # 虚拟环境路径
SERVICE_NAME="xinference-prod"             # Systemd服务名
PORT="${PORT:-9997}"                       # 服务端口
DATA_DIR="${DATA_DIR:-/var/lib/xinference}" # 持久化数据目录
WEB_UI_ENABLED="${WEB_UI_ENABLED:-0}"       # 是否构建Web UI（0=关闭，1=开启）
PYTHON_VERSION="${PYTHON_VERSION:-3.10}"    # Python版本
GPU_SUPPORT="${GPU_SUPPORT:-1}"             # GPU支持（1=启用，0=禁用）

# ==============================================================================
# 基础环境检查
# ==============================================================================
echo ">>> 检查系统依赖"
if ! command -v python3."${PYTHON_VERSION%%.*}" &> /dev/null; then
    echo "错误：未找到Python ${PYTHON_VERSION}，开始安装..."
    sudo apt update -y
    sudo apt install -y python3."${PYTHON_VERSION%%.*}" python3-pip python3-venv
fi

# ==============================================================================
# 创建项目目录
# ==============================================================================
mkdir -p "${BASE_DIR}" "${DATA_DIR}"
chown -R "${USERNAME}" "${BASE_DIR}" "${DATA_DIR}"
cd "${BASE_DIR}"

# ==============================================================================
# 创建虚拟环境并安装Xinference
# ==============================================================================
echo ">>> 创建虚拟环境"
python3 -m venv "${ENV_DIR}"
source "${ENV_DIR}/bin/activate"

echo ">>> 安装Xinference（生产环境版本）"
# 关闭Web UI构建（生产环境可选）
if [ "${WEB_UI_ENABLED}" -eq 0 ]; then
    export NO_WEB_UI=1
fi
# 安装GPU版本或CPU版本
if [ "${GPU_SUPPORT}" -eq 1 ]; then
    pip install "xinference[gpu]" --no-cache-dir
else
    pip install "xinference[cpu]" --no-cache-dir
fi

# ==============================================================================
# 配置Systemd服务
# ==============================================================================
cat <<EOF | sudo tee /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Xinference Production Service
After=network.target

[Service]
User=${USERNAME}
WorkingDirectory=${BASE_DIR}
Environment="PATH=${ENV_DIR}/bin:$PATH"
ExecStart=${ENV_DIR}/bin/xinference-local --port ${PORT} --data-dir ${DATA_DIR}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# ==============================================================================
# 启动并验证服务
# ==============================================================================
echo ">>> 启动服务"
sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}

echo ">>> 检查服务状态"
systemctl status ${SERVICE_NAME} --no-pager

echo ">>> 验证API可用性"
if curl -s http://localhost:${PORT}/health | jq .status | grep -q "healthy"; then
    echo "部署成功！服务运行在 http://localhost:${PORT}/docs"
else
    echo "错误：服务启动失败，请检查日志"
    systemctl status ${SERVICE_NAME}
    exit 1
fi
