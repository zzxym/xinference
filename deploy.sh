#!/bin/bash

# ======================================
# Xinference 全功能安装部署脚本 (v1.1)
# 支持常规安装（systemd）+ Docker部署（含模型自动加载）
# 包含环境检测、错误处理、开机自启动等企业级功能
# ======================================

# 全局配置
VERSION="1.1"
DEPLOY_MODES=("normal" "docker")
SERVICE_NAME="xinference"
XINFERENCE_PORT=9997
USER=$(whoami)
WORK_DIR=$(pwd)
DATA_DIR="${WORK_DIR}/data"
LOG_DIR="${WORK_DIR}/logs"
SYSTEMD_TEMPLATE="templates/xinference.service"  # 系统服务模板路径

# 颜色常量
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# 系统兼容性检测
check_system() {
    local os=$(uname -s)
    if [[ "$os" != "Linux" && "$os" != "Darwin" ]]; then
        echo -e "${RED}[错误]${RESET} 仅支持 Linux/macOS 系统"
        exit 1
    fi
}

# --------------------------- 常规安装模块 ---------------------------
install_normal_mode() {
    echo -e "${GREEN}[*]${RESET} 开始常规安装（systemd服务）"
    install_dependencies
    setup_systemd_service
    enable_service
    start_service
    echo -e "${GREEN}[√]${RESET} 常规安装完成"
    show_service_status normal
}

# 安装Python依赖
install_dependencies() {
    echo -e "${CYAN}[*]${RESET} 安装Python依赖..."
    python3 -m pip install --upgrade pip
    python3 -m pip install "xinference[all]" --no-cache-dir || {
        echo -e "${RED}[!]${RESET} 依赖安装失败，请检查网络或手动安装"
        exit 1
    }
}

# 配置systemd服务
setup_systemd_service() {
    mkdir -p "${LOG_DIR}"
    cat <<EOF > "/etc/systemd/system/${SERVICE_NAME}.service"
[Unit]
Description=Xinference AI Service
Documentation=https://inference.readthedocs.io
After=network.target

[Service]
User=${USER}
WorkingDirectory=${WORK_DIR}
ExecStart=$(which xinference-local) -p ${XINFERENCE_PORT} --load-builtin-model qwen2.5-instruct,bge-large-zh-v1.5,jina-reranker-v2
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1
StandardOutput=file:${LOG_DIR}/service.log
StandardError=file:${LOG_DIR}/error.log

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo -e "${CYAN}[*]${RESET} systemd服务文件已生成"
}

# --------------------------- Docker部署模块 ---------------------------
install_docker_mode() {
    echo -e "${GREEN}[*]${RESET} 开始Docker部署（容器化环境）"
    check_docker_installed
    handle_container_conflict
    pull_docker_image
    start_docker_container
    echo -e "${GREEN}[√]${RESET} Docker部署完成"
    show_service_status docker
}

# 检测Docker是否安装
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}[!]${RESET} Docker未安装，开始安装..."
        if [[ "$(uname)" == "Linux" ]]; then
            sudo apt-get update && sudo apt-get install -y docker.io
            sudo systemctl enable --now docker
            sudo usermod -aG docker "${USER}"
            newgrp docker
        else
            echo -e "${YELLOW}[!]${RESET} macOS用户请手动安装Docker Desktop后重新运行"
            exit 1
        fi
    fi
}

# 处理容器冲突
handle_container_conflict() {
    if docker ps -a | grep -q "${SERVICE_NAME}"; then
        echo -e "${YELLOW}[!]${RESET} 发现旧容器，正在清理..."
        docker stop "${SERVICE_NAME}" >/dev/null 2>&1
        docker rm "${SERVICE_NAME}" >/dev/null 2>&1
    fi
}

# 拉取最新镜像
pull_docker_image() {
    echo -e "${CYAN}[*]${RESET} 拉取Xinference镜像..."
    docker pull xprobe/xinference:latest || {
        echo -e "${RED}[!]${RESET} 镜像拉取失败，请检查网络"
        exit 1
    }
}

# 启动Docker容器（含模型加载）
start_docker_container() {
    docker run -d --name "${SERVICE_NAME}" \
        -p "${XINFERENCE_PORT}:${XINFERENCE_PORT}" \
        -v "${DATA_DIR}:/data" \
        --gpus all \
        --restart always \
        xprobe/xinference:latest \
        xinference-local -H 0.0.0.0 --load-builtin-model qwen2.5-instruct,bge-large-zh-v1.5,jina-reranker-v2
    echo -e "${CYAN}[*]${RESET} 容器启动命令已执行"
}

# --------------------------- 公共功能模块 ---------------------------
# 启用服务
enable_service() {
    systemctl enable "${SERVICE_NAME}"
    echo -e "${CYAN}[*]${RESET} 已启用开机自启动"
}

# 启动服务
start_service() {
    systemctl start "${SERVICE_NAME}"
    echo -e "${CYAN}[*]${RESET} 服务已启动"
}

# 显示服务状态
show_service_status() {
    local mode=$1
    case $mode in
        "normal")
            echo -e "${CYAN}[*]${RESET} 服务状态（常规模式）:"
            systemctl status "${SERVICE_NAME}" --no-pager
            ;;
        "docker")
            echo -e "${CYAN}[*]${RESET} 容器状态（Docker模式）:"
            docker ps -f name="${SERVICE_NAME}"
            docker logs "${SERVICE_NAME}" | grep -A 5 "Model loaded"
            ;;
    esac
}

# --------------------------- 交互界面 ---------------------------
display_menu() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║         XLXX inference 部署工具         ║${RESET}"
    echo -e "${GREEN}║            版本: ${VERSION}             ║${RESET}"
    echo -e "${GREEN}╠════════════════════════════════════════╣${RESET}"
    echo -e "${CYAN}1.${RESET} 常规安装（systemd服务，适合CPU环境）"
    echo -e "${CYAN}2.${RESET} Docker部署（容器化，推荐GPU环境）"
    echo -e "${YELLOW}3.${RESET} 退出"
    echo -e "${GREEN}╚════════════════════════════════════════╝${RESET}"
    read -p "请选择部署方式 (1/2/3): " choice
    case $choice in
        1) install_normal_mode ;;
        2) install_docker_mode ;;
        3) exit 0 ;;
        *) echo -e "${RED}[!]${RESET} 无效选择，请重新输入"; sleep 2; display_menu ;;
    esac
}

# --------------------------- 主执行流程 ---------------------------
main() {
    check_system
    display_menu
}

# 执行主函数
main
