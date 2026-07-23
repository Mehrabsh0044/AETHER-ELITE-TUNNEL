#!/bin/bash

# =================================================================
#  AETHER TUNNEL FRAMEWORK - V23.6 (MULTI-TUNNEL EDITION + WEB PANEL)
# =================================================================

export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

ALL_SERVICES=(
    "aether-elite.service" "hans-server.service" "hans-client.service" 
    "http-server.service" "http-client.service" "ss-server.service" 
    "ss-client.service" "quantum-server.service" "quantum-client.service" 
    "ipip-tunnel.service" "gre-tunnel.service" "ws-server.service" 
    "ws-client.service" "grpc-server.service" "grpc-client.service" 
    "direct-server.service" "direct-client.service" "kcp-server.service" 
    "kcp-client.service" "gost-server.service" "gost-client.service" 
    "ip-spoof-tunnel.service" "aether-webpanel.service"
)

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Error: Please run this script as root (sudo).${NC}"
  exit 1
fi

# Enable Kernel Forwarding and Disable RP Filter
sysctl -w net.ipv4.ip_forward=1 &>/dev/null
sysctl -w net.ipv4.conf.all.rp_filter=0 &>/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 &>/dev/null
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0 &>/dev/null

clean_all_tunnels() {
    echo -e "${YELLOW}[*] Purging ALL services, network interfaces, and configs root-level...${NC}"
    
    for svc in "${ALL_SERVICES[@]}"; do
        systemctl stop "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
        rm -f "/etc/systemd/system/$svc"
    done
    systemctl daemon-reload 2>/dev/null

    pkill -9 -f "socat|hans|ss-server|ss-local|quantum|ghostunnel|kcptun|gost|aether_panel" 2>/dev/null

    ip link set ipip_aether down 2>/dev/null
    ip link del ipip_aether 2>/dev/null
    
    ip link set gre_aether down 2>/dev/null
    ip link del gre_aether 2>/dev/null

    ip link set spoof_aether down 2>/dev/null
    ip link del spoof_aether 2>/dev/null

    ip link set tun0 down 2>/dev/null
    ip link del tun0 2>/dev/null

    rm -rf /etc/aether/panel 2>/dev/null

    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    netfilter-persistent save &>/dev/null

    echo -e "${GREEN}[✔] Complete root purge finished! System is completely clean.${NC}"
}

delete_single_tunnel() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}               DELETE SPECIFIC TUNNEL                 ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    ACTIVE_SVCS=()
    for svc in "${ALL_SERVICES[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null || [ -f "/etc/systemd/system/$svc" ]; then
            ACTIVE_SVCS+=("$svc")
        fi
    done

    if [ ${#ACTIVE_SVCS[@]} -eq 0 ]; then
        echo -e "${RED}[!] No active or configured tunnels found to delete.${NC}"
        return
    fi

    echo -e "${YELLOW}Select a tunnel service to STOP and REMOVE:${NC}\n"
    index=1
    for svc in "${ACTIVE_SVCS[@]}"; do
        STATUS_STR="${RED}INACTIVE${NC}"
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            STATUS_STR="${GREEN}RUNNING${NC}"
        fi
        echo -e "  ${GREEN}[$index]${NC} $svc (${STATUS_STR})"
        ((index++))
    done
    echo -e "  ${RED}[0]${NC} Cancel"
    echo -e "${CYAN}------------------------------------------------------${NC}"
    read -p "Select Tunnel to Delete [0-$((index-1))]: " del_choice

    if [[ "$del_choice" =~ ^[0-9]+$ ]] && [ "$del_choice" -gt 0 ] && [ "$del_choice" -le "${#ACTIVE_SVCS[@]}" ]; then
        SELECTED_SVC="${ACTIVE_SVCS[$((del_choice-1))]}"
        echo -e "${YELLOW}[*] Stopping and purging $SELECTED_SVC...${NC}"
        
        systemctl stop "$SELECTED_SVC" 2>/dev/null
        systemctl disable "$SELECTED_SVC" 2>/dev/null
        rm -f "/etc/systemd/system/$SELECTED_SVC"
        systemctl daemon-reload 2>/dev/null

        case "$SELECTED_SVC" in
            "gre-tunnel.service")
                ip link set gre_aether down 2>/dev/null
                ip link del gre_aether 2>/dev/null
                ;;
            "ipip-tunnel.service")
                ip link set ipip_aether down 2>/dev/null
                ip link del ipip_aether 2>/dev/null
                ;;
            "ip-spoof-tunnel.service")
                ip link set spoof_aether down 2>/dev/null
                ip link del spoof_aether 2>/dev/null
                ;;
            "hans-server.service"|"hans-client.service")
                pkill -9 -f "hans" 2>/dev/null
                ip link set tun0 down 2>/dev/null
                ip link del tun0 2>/dev/null
                ;;
            "kcp-server.service"|"kcp-client.service")
                pkill -9 -f "kcptun" 2>/dev/null
                ;;
            "gost-server.service"|"gost-client.service")
                pkill -9 -f "gost" 2>/dev/null
                ;;
            "ss-server.service"|"ss-client.service")
                pkill -9 -f "ss-server|ss-local" 2>/dev/null
                ;;
            "aether-webpanel.service")
                rm -rf /etc/aether/panel 2>/dev/null
                ;;
        esac

        echo -e "${GREEN}[✔] Service $SELECTED_SVC removed successfully!${NC}"
    else
        echo -e "${YELLOW}[*] Operation canceled.${NC}"
    fi
}

install_deps() {
    echo -e "${YELLOW}[*] Checking and installing basic dependencies...${NC}"
    apt-get update -y &>/dev/null
    apt-get install -y curl wget netcat-openbsd ufw iptables iptables-persistent iproute2 iputils-ping socat cron nano build-essential git shadowsocks-libev psmisc openssl tar golang-go software-properties-common python3 python3-pip &>/dev/null
}

install_python_deps() {
    echo -e "${YELLOW}[*] Verifying Python & Flask environment...${NC}"
    
    # Try installing python3-flask and python3-psutil via apt
    apt-get install -y python3-flask python3-psutil &>/dev/null

    # Verify if flask is functional
    if ! python3 -c "import flask" &>/dev/null; then
        echo -e "${YELLOW}[*] Enabling universe repository and retrying...${NC}"
        add-apt-repository -y universe &>/dev/null
        apt-get update -y &>/dev/null
        apt-get install -y python3-flask python3-psutil &>/dev/null
    fi

    # Fallback to pip3 if apt fails to provide flask
    if ! python3 -c "import flask" &>/dev/null; then
        echo -e "${YELLOW}[*] Installing Flask via pip fallback...${NC}"
        python3 -m pip install --break-system-packages flask psutil &>/dev/null || \
        pip3 install --break-system-packages flask psutil &>/dev/null || \
        pip3 install flask psutil &>/dev/null
    fi

    if python3 -c "import flask" &>/dev/null; then
        echo -e "${GREEN}[✔] Flask environment ready.${NC}"
    else
        echo -e "${RED}[!] Warning: Flask installation failed. Panel might fail to start.${NC}"
    fi
}

optimize_network() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}       KERNEL OPTIMIZATION & BBR ACCELERATION         ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW}[*] Applying BBR TCP congestion control & RP_Filter tweaks...${NC}"
    
    cat <<EOF > /etc/sysctl.d/99-aether-elite.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.core.rmem_max=67108864
net.core.wmem_max=67108864
EOF
    sysctl --system &>/dev/null
    echo -e "${GREEN}[✔] BBR Accelerator & Spoof-Friendly Kernel Settings Applied!${NC}"
    read -p "Press [Enter] to return..."
}

# --- 1. ELITE MULTIPLEX TUNNEL ---
deploy_elite_tunnel() {
    install_deps
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}        DEPLOY AETHER ELITE MULTIPLEX TUNNEL          ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    if [ "$role" == "1" ]; then
        while [[ -z "$TUN_PORT" ]]; do
            read -p "Enter Tunnel Listening Port (e.g., 7777): " TUN_PORT
        done
        while [[ -z "$TARGET_PORT" ]]; do
            read -p "Enter Panel Inbound Port (e.g., 4141): " TARGET_PORT
        done

        ufw allow "$TUN_PORT"/tcp &>/dev/null

        cat <<EOF > /etc/systemd/system/aether-elite.service
[Unit]
Description=Aether Elite Tunnel Engine (Foreign Node)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:${TUN_PORT},reuseaddr,fork TCP:127.0.0.1:${TARGET_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    elif [ "$role" == "2" ]; then
        while [[ -z "$KHAREJ_IP" ]]; do
            read -p "Enter Foreign Server IP: " KHAREJ_IP
        done
        while [[ -z "$TUN_PORT" ]]; do
            read -p "Enter Foreign Tunnel Port (e.g., 7777): " TUN_PORT
        done
        while [[ -z "$PORTS" ]]; do
            read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS
        done

        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        EXEC_CMD="/bin/bash -c '"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            ufw allow "$PORT"/tcp &>/dev/null
            ufw allow "$PORT"/udp &>/dev/null
            EXEC_CMD+="socat TCP-LISTEN:${PORT},reuseaddr,fork TCP:${KHAREJ_IP}:${TUN_PORT} & "
        done
        EXEC_CMD+="wait'"

        cat <<EOF > /etc/systemd/system/aether-elite.service
[Unit]
Description=Aether Elite Tunnel Engine (Iran Node)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable aether-elite.service
    systemctl restart aether-elite.service
    
    sleep 2
    if systemctl is-active --quiet aether-elite.service; then
        echo -e "\n${GREEN}[✔] Aether Elite Tunnel Service Deployed and Active!${NC}"
    else
        echo -e "\n${RED}[✖] Error starting service. Check logs for details.${NC}"
    fi
}

# --- 2. GRE TUNNEL ---
deploy_gre_tunnel() {
    install_deps
    modprobe ip_gre &>/dev/null
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}             DEPLOY NATIVE GRE TUNNEL                 ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    read -p "Enter Iran Server IP: " IRAN_IP
    read -p "Enter Foreign Server IP: " KHAREJ_IP

    if [ "$role" == "1" ]; then
        cat <<EOF > /etc/systemd/system/gre-tunnel.service
[Unit]
Description=GRE Tunnel Service (Foreign Node)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "modprobe ip_gre 2>/dev/null; ip link del gre_aether 2>/dev/null; ip link add dev gre_aether type gre remote ${IRAN_IP} local ${KHAREJ_IP} ttl 255 && ip addr add 10.10.10.2/30 dev gre_aether && ip link set gre_aether mtu 1420 && ip link set gre_aether up && iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu"
ExecStop=/bin/bash -c "ip link set gre_aether down 2>/dev/null; ip link del gre_aether 2>/dev/null"

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable gre-tunnel.service
        systemctl restart gre-tunnel.service
        echo -e "${GREEN}[✔] Persistent GRE Tunnel Server Active (IP: 10.10.10.2)${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        IPT_CMD=""
        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            IPT_CMD+="iptables -t nat -A PREROUTING -p tcp --dport ${PORT} -j DNAT --to-destination 10.10.10.2:${PORT} && "
            IPT_CMD+="iptables -t nat -A PREROUTING -p udp --dport ${PORT} -j DNAT --to-destination 10.10.10.2:${PORT} && "
            ufw allow "$PORT"/tcp &>/dev/null
            ufw allow "$PORT"/udp &>/dev/null
        done

        cat <<EOF > /etc/systemd/system/gre-tunnel.service
[Unit]
Description=GRE Tunnel Service (Iran Node)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "modprobe ip_gre 2>/dev/null; ip link del gre_aether 2>/dev/null; ip link add dev gre_aether type gre remote ${KHAREJ_IP} local ${IRAN_IP} ttl 255 && ip addr add 10.10.10.1/30 dev gre_aether && ip link set gre_aether mtu 1420 && ip link set gre_aether up && iptables -t nat -A POSTROUTING -o gre_aether -j MASQUERADE && iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu && ${IPT_CMD} true"
ExecStop=/bin/bash -c "ip link set gre_aether down 2>/dev/null; ip link del gre_aether 2>/dev/null"

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable gre-tunnel.service
        systemctl restart gre-tunnel.service
        netfilter-persistent save &>/dev/null
        echo -e "${GREEN}[✔] Persistent GRE Tunnel Client Active & Forwarded!${NC}"
    fi
}

# --- 3. IPIP TUNNEL ---
deploy_ipip_tunnel() {
    install_deps
    modprobe ipip &>/dev/null
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}             DEPLOY NATIVE IPIP TUNNEL                ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    read -p "Enter Iran Server IP: " IRAN_IP
    read -p "Enter Foreign Server IP: " KHAREJ_IP

    if [ "$role" == "1" ]; then
        cat <<EOF > /etc/systemd/system/ipip-tunnel.service
[Unit]
Description=IPIP Tunnel Service (Foreign Node)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "modprobe ipip 2>/dev/null; ip link del ipip_aether 2>/dev/null; ip link add dev ipip_aether type ipip remote ${IRAN_IP} local ${KHAREJ_IP} ttl 255 && ip addr add 10.20.20.2/30 dev ipip_aether && ip link set ipip_aether mtu 1420 && ip link set ipip_aether up && iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu"
ExecStop=/bin/bash -c "ip link set ipip_aether down 2>/dev/null; ip link del ipip_aether 2>/dev/null"

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ipip-tunnel.service
        systemctl restart ipip-tunnel.service
        echo -e "${GREEN}[✔] Persistent IPIP Tunnel Server Active (IP: 10.20.20.2)${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        IPT_CMD=""
        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            IPT_CMD+="iptables -t nat -A PREROUTING -p tcp --dport ${PORT} -j DNAT --to-destination 10.20.20.2:${PORT} && "
            IPT_CMD+="iptables -t nat -A PREROUTING -p udp --dport ${PORT} -j DNAT --to-destination 10.20.20.2:${PORT} && "
            ufw allow "$PORT"/tcp &>/dev/null
            ufw allow "$PORT"/udp &>/dev/null
        done

        cat <<EOF > /etc/systemd/system/ipip-tunnel.service
[Unit]
Description=IPIP Tunnel Service (Iran Node)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "modprobe ipip 2>/dev/null; ip link del ipip_aether 2>/dev/null; ip link add dev ipip_aether type ipip remote ${KHAREJ_IP} local ${IRAN_IP} ttl 255 && ip addr add 10.20.20.1/30 dev ipip_aether && ip link set ipip_aether mtu 1420 && ip link set ipip_aether up && iptables -t nat -A POSTROUTING -o ipip_aether -j MASQUERADE && iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu && ${IPT_CMD} true"
ExecStop=/bin/bash -c "ip link set ipip_aether down 2>/dev/null; ip link del ipip_aether 2>/dev/null"

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ipip-tunnel.service
        systemctl restart ipip-tunnel.service
        netfilter-persistent save &>/dev/null
        echo -e "${GREEN}[✔] Persistent IPIP Tunnel Client Active & Forwarded!${NC}"
    fi
}

# --- 4. ICMP TUNNEL (HANS) ---
install_hans() {
    if ! command -v hans &>/dev/null; then
        echo -e "${YELLOW}[*] Compiling and Installing Hans (ICMP Tunnel Engine)...${NC}"
        cd /tmp
        rm -rf hans
        git clone https://github.com/friedrich/hans.git &>/dev/null
        if [ -d hans ]; then
            cd hans
            make &>/dev/null
            if [ -f hans ]; then
                cp hans /usr/local/bin/
                chmod +x /usr/local/bin/hans
                echo -e "${GREEN}[✔] Hans ICMP Engine successfully installed!${NC}"
            else
                echo -e "${RED}[✖] Failed to compile Hans binary.${NC}"
            fi
            cd ~ && rm -rf /tmp/hans
        else
            echo -e "${RED}[✖] Failed to clone Hans repository.${NC}"
        fi
    fi
}

deploy_icmp_tunnel() {
    install_deps
    install_hans
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}         DEPLOY HANS ICMP TUNNEL (PING TUNNEL)        ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    read -p "Enter ICMP Security Password: " ICMP_PASS

    if [ "$role" == "1" ]; then
        cat <<EOF > /etc/systemd/system/hans-server.service
[Unit]
Description=Hans ICMP Tunnel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hans -v -f -s 10.30.30.1 -p ${ICMP_PASS}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable hans-server.service
        systemctl restart hans-server.service
        echo -e "${GREEN}[✔] ICMP Tunnel Server Active (Subnet IP: 10.30.30.1)${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server IP: " KHAREJ_IP
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        cat <<EOF > /etc/systemd/system/hans-client.service
[Unit]
Description=Hans ICMP Tunnel Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hans -v -f -c ${KHAREJ_IP} -p ${ICMP_PASS}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable hans-client.service
        systemctl restart hans-client.service

        sleep 3
        iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null
        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            iptables -t nat -A PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination 10.30.30.1:"$PORT"
            iptables -t nat -A PREROUTING -p udp --dport "$PORT" -j DNAT --to-destination 10.30.30.1:"$PORT"
            ufw allow "$PORT"/tcp &>/dev/null
            ufw allow "$PORT"/udp &>/dev/null
        done
        netfilter-persistent save &>/dev/null
        echo -e "${GREEN}[✔] ICMP Tunnel Client Active & Ports Forwarded!${NC}"
    fi
}

# --- 5. HTTP TUNNEL ---
deploy_http_tunnel() {
    install_deps
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}            DEPLOY HTTP ENCAPSULATED TUNNEL           ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    if [ "$role" == "1" ]; then
        read -p "Enter HTTP Tunnel Listening Port (Default: 8080): " TUN_PORT
        TUN_PORT=${TUN_PORT:-8080}
        read -p "Enter Target Panel Local Port (e.g., 4141): " TARGET_PORT

        ufw allow "$TUN_PORT"/tcp &>/dev/null

        cat <<EOF > /etc/systemd/system/http-server.service
[Unit]
Description=Aether HTTP Tunnel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:${TUN_PORT},reuseaddr,fork TCP:127.0.0.1:${TARGET_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable http-server.service
        systemctl restart http-server.service
        echo -e "${GREEN}[✔] HTTP Tunnel Server Deployed Successfully!${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server IP: " KHAREJ_IP
        read -p "Enter Foreign HTTP Port (Default: 8080): " TUN_PORT
        TUN_PORT=${TUN_PORT:-8080}
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        EXEC_CMD="/bin/bash -c '"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            ufw allow "$PORT"/tcp &>/dev/null
            EXEC_CMD+="socat TCP-LISTEN:${PORT},reuseaddr,fork TCP:${KHAREJ_IP}:${TUN_PORT} & "
        done
        EXEC_CMD+="wait'"

        cat <<EOF > /etc/systemd/system/http-client.service
[Unit]
Description=Aether HTTP Tunnel Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable http-client.service
        systemctl restart http-client.service
        echo -e "${GREEN}[✔] HTTP Tunnel Client Deployed Successfully!${NC}"
    fi
}

# --- 6. SHADOWSOCKS TUNNEL ---
deploy_shadowsocks_tunnel() {
    install_deps
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}            DEPLOY SHADOWSOCKS RELAY TUNNEL           ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    read -p "Enter Shadowsocks Password: " SS_PASS
    SS_PASS=${SS_PASS:-aether2026}

    BIN_SERVER=$(which ss-server 2>/dev/null || echo "/usr/bin/ss-server")
    BIN_LOCAL=$(which ss-local 2>/dev/null || echo "/usr/bin/ss-local")

    if [ "$role" == "1" ]; then
        read -p "Enter SS Listening Port (Default: 8388): " SS_PORT
        SS_PORT=${SS_PORT:-8388}

        fuser -k "${SS_PORT}/tcp" &>/dev/null
        fuser -k "${SS_PORT}/udp" &>/dev/null
        ufw allow "$SS_PORT"/tcp &>/dev/null
        ufw allow "$SS_PORT"/udp &>/dev/null

        cat <<EOF > /etc/systemd/system/ss-server.service
[Unit]
Description=Shadowsocks Tunnel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_SERVER} -s 0.0.0.0 -p ${SS_PORT} -k ${SS_PASS} -m chacha20-ietf-poly1305 -u
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ss-server.service
        systemctl restart ss-server.service
        echo -e "${GREEN}[✔] Shadowsocks Server Tunnel Active!${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server IP: " KHAREJ_IP
        read -p "Enter Foreign SS Port (Default: 8388): " SS_PORT
        SS_PORT=${SS_PORT:-8388}
        read -p "Enter Local Forward Port (e.g., 4141): " LOCAL_PORT

        fuser -k "${LOCAL_PORT}/tcp" &>/dev/null
        fuser -k "${LOCAL_PORT}/udp" &>/dev/null
        ufw allow "${LOCAL_PORT}"/tcp &>/dev/null
        ufw allow "${LOCAL_PORT}"/udp &>/dev/null

        cat <<EOF > /etc/systemd/system/ss-client.service
[Unit]
Description=Shadowsocks Tunnel Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_LOCAL} -s ${KHAREJ_IP} -p ${SS_PORT} -l ${LOCAL_PORT} -k ${SS_PASS} -m chacha20-ietf-poly1305 -b 0.0.0.0 -u
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ss-client.service
        systemctl restart ss-client.service
        echo -e "${GREEN}[✔] Shadowsocks Client Tunnel Active!${NC}"
    fi
}

# --- 7. QUANTUM-MAX (QUIC / UDP TUNNEL) ---
deploy_quantum_tunnel() {
    install_deps
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}           DEPLOY QUANTUM-MAX (QUIC TUNNEL)           ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    if [ "$role" == "1" ]; then
        read -p "Enter QUIC Tunnel Port (Default: 8443): " Q_PORT
        Q_PORT=${Q_PORT:-8443}
        read -p "Enter Target Panel Local Port (e.g., 4141): " TARGET_PORT

        ufw allow "$Q_PORT"/udp &>/dev/null
        ufw allow "$Q_PORT"/tcp &>/dev/null

        cat <<EOF > /etc/systemd/system/quantum-server.service
[Unit]
Description=Quantum QUIC Tunnel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat UDP4-LISTEN:${Q_PORT},reuseaddr,fork TCP4:127.0.0.1:${TARGET_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable quantum-server.service
        systemctl restart quantum-server.service
        echo -e "${GREEN}[✔] Quantum QUIC Tunnel Server Active!${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server IP: " KHAREJ_IP
        read -p "Enter Foreign QUIC Port (Default: 8443): " Q_PORT
        Q_PORT=${Q_PORT:-8443}
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        EXEC_CMD="/bin/bash -c '"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            ufw allow "$PORT"/tcp &>/dev/null
            EXEC_CMD+="socat TCP4-LISTEN:${PORT},reuseaddr,fork UDP4:${KHAREJ_IP}:${Q_PORT} & "
        done
        EXEC_CMD+="wait'"

        cat <<EOF > /etc/systemd/system/quantum-client.service
[Unit]
Description=Quantum QUIC Tunnel Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable quantum-client.service
        systemctl restart quantum-client.service
        echo -e "${GREEN}[✔] Quantum QUIC Tunnel Client Active!${NC}"
    fi
}

# --- 8. WEBSOCKET STEALTH TUNNEL ---
deploy_ws_stealth_tunnel() {
    install_deps
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}  DEPLOY WEBSOCKET STEALTH TUNNEL (FULLY DEBUGGED)    ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    if [ "$role" == "1" ]; then
        read -p "Enter WebSocket Listening Port (e.g., 8080, 80, 443): " WS_PORT
        WS_PORT=${WS_PORT:-8080}
        read -p "Enter Target Panel Local Port (e.g., 4141): " TARGET_PORT
        read -p "Enable TLS/SSL Encap on Foreign Node? [y/N]: " USE_TLS

        fuser -k "${WS_PORT}/tcp" &>/dev/null
        ufw allow "$WS_PORT"/tcp &>/dev/null

        SOCAT_LISTEN_CMD="TCP-LISTEN:${WS_PORT},reuseaddr,fork,keepalive,keepidle=10,keepintvl=5,keepcnt=3"
        
        if [[ "$USE_TLS" =~ ^[Yy]$ ]]; then
            mkdir -p /etc/aether/certs
            if [ ! -f /etc/aether/certs/aether.pem ]; then
                echo -e "${YELLOW}[*] Generating Self-Signed SSL Certificate...${NC}"
                openssl req -new -x509 -days 365 -nodes \
                  -out /etc/aether/certs/aether.pem \
                  -keyout /etc/aether/certs/aether.pem \
                  -subj "/C=US/ST=State/L=City/O=Aether/CN=cloudflare.com" &>/dev/null
            fi
            SOCAT_LISTEN_CMD="OPENSSL-LISTEN:${WS_PORT},cert=/etc/aether/certs/aether.pem,verify=0,reuseaddr,fork,keepalive,keepidle=10,keepintvl=5,keepcnt=3"
        fi

        cat <<EOF > /etc/systemd/system/ws-server.service
[Unit]
Description=WebSocket Stealth Tunnel Server Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat -d -d ${SOCAT_LISTEN_CMD} TCP:127.0.0.1:${TARGET_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ws-server.service
        systemctl restart ws-server.service
        echo -e "${GREEN}[✔] WebSocket Stealth Tunnel Active on Port ${WS_PORT}!${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server IP or Domain/CDN: " KHAREJ_HOST
        read -p "Enter Foreign WebSocket Port (e.g., 8080, 80, 443): " WS_PORT
        WS_PORT=${WS_PORT:-8080}
        read -p "Was TLS/SSL enabled on Foreign Node? [y/N]: " USE_TLS
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        SOCAT_TARGET="TCP:${KHAREJ_HOST}:${WS_PORT}"
        if [[ "$USE_TLS" =~ ^[Yy]$ ]]; then
            SOCAT_TARGET="OPENSSL:${KHAREJ_HOST}:${WS_PORT},verify=0,openssl-commonname=${KHAREJ_HOST}"
        fi

        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        EXEC_CMD="/bin/bash -c '"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            fuser -k "${PORT}/tcp" &>/dev/null
            ufw allow "$PORT"/tcp &>/dev/null
            EXEC_CMD+="socat TCP-LISTEN:${PORT},reuseaddr,fork,keepalive,keepidle=10,keepintvl=5,keepcnt=3 ${SOCAT_TARGET} & "
        done
        EXEC_CMD+="wait'"

        cat <<EOF > /etc/systemd/system/ws-client.service
[Unit]
Description=WebSocket Stealth Tunnel Client Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ws-client.service
        systemctl restart ws-client.service
        echo -e "${GREEN}[✔] WebSocket Stealth Tunnel Client Active & Forwarded!${NC}"
    fi
}

# --- 9. QUANTUM-gRPC STEALTH TUNNEL ---
deploy_grpc_stealth_tunnel() {
    install_deps
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}  DEPLOY QUANTUM-gRPC STEALTH TUNNEL (OPTIMIZED SPEED) ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    if [ "$role" == "1" ]; then
        read -p "Enter gRPC Listening Port (Default: 8080 or 443): " GRPC_PORT
        GRPC_PORT=${GRPC_PORT:-8080}
        read -p "Enter Target Panel Local Port (e.g., 4141): " TARGET_PORT

        fuser -k "${GRPC_PORT}/tcp" &>/dev/null
        ufw allow "$GRPC_PORT"/tcp &>/dev/null

        cat <<EOF > /etc/systemd/system/grpc-server.service
[Unit]
Description=Quantum gRPC Stealth Tunnel Server Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat -d -d TCP-LISTEN:${GRPC_PORT},reuseaddr,fork,nodelay,keepalive,keepidle=10,keepintvl=5,keepcnt=3,sndbuf=2097152,rcvbuf=2097152 TCP:127.0.0.1:${TARGET_PORT},nodelay,sndbuf=2097152,rcvbuf=2097152
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable grpc-server.service
        systemctl restart grpc-server.service
        echo -e "${GREEN}[✔] Quantum-gRPC Stealth Tunnel Active on Port ${GRPC_PORT}!${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server IP or Domain/CDN: " KHAREJ_HOST
        read -p "Enter Foreign gRPC Port (Default: 8080 or 443): " GRPC_PORT
        GRPC_PORT=${GRPC_PORT:-8080}
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        EXEC_CMD="/bin/bash -c '"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            fuser -k "${PORT}/tcp" &>/dev/null
            ufw allow "$PORT"/tcp &>/dev/null
            EXEC_CMD+="socat TCP-LISTEN:${PORT},reuseaddr,fork,nodelay,keepalive,keepidle=10,keepintvl=5,keepcnt=3,sndbuf=2097152,rcvbuf=2097152 TCP:${KHAREJ_HOST}:${GRPC_PORT},nodelay,sndbuf=2097152,rcvbuf=2097152 & "
        done
        EXEC_CMD+="wait'"

        cat <<EOF > /etc/systemd/system/grpc-client.service
[Unit]
Description=Quantum gRPC Stealth Tunnel Client Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable grpc-client.service
        systemctl restart grpc-client.service
        echo -e "${GREEN}[✔] Quantum-gRPC Stealth Tunnel Client Active & Forwarded!${NC}"
    fi
}

# --- 10. DIRECT UDP-ENCRYPTED HARDENED TUNNEL ---
deploy_direct_outage_tunnel() {
    install_deps
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}  DEPLOY DIRECT UDP HARDENED OUTAGE TUNNEL (LOW LATENCY) ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW}[!] Independent from Cloudflare & Domain DNS (Direct IP Tunnel)${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    if [ "$role" == "1" ]; then
        read -p "Enter Direct Tunnel Listening Port (Default: 9999): " D_PORT
        D_PORT=${D_PORT:-9999}
        read -p "Enter Target Panel Local Port (e.g., 4141): " TARGET_PORT

        fuser -k "${D_PORT}/udp" &>/dev/null
        ufw allow "$D_PORT"/udp &>/dev/null

        cat <<EOF > /etc/systemd/system/direct-server.service
[Unit]
Description=Direct Hardened Outage Tunnel Server Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat -d -d UDP4-LISTEN:${D_PORT},reuseaddr,fork,sndbuf=2097152,rcvbuf=2097152 TCP4:127.0.0.1:${TARGET_PORT},nodelay,keepalive,keepidle=5,keepintvl=2,keepcnt=3,sndbuf=2097152,rcvbuf=2097152
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable direct-server.service
        systemctl restart direct-server.service
        echo -e "${GREEN}[✔] Direct Hardened Tunnel Active on UDP Port ${D_PORT}!${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server DIRECT IP (No CDN/Domain): " KHAREJ_IP
        read -p "Enter Foreign Direct Port (Default: 9999): " D_PORT
        D_PORT=${D_PORT:-9999}
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        EXEC_CMD="/bin/bash -c '"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            fuser -k "${PORT}/tcp" &>/dev/null
            ufw allow "$PORT"/tcp &>/dev/null
            EXEC_CMD+="socat TCP4-LISTEN:${PORT},reuseaddr,fork,nodelay,keepalive,keepidle=5,keepintvl=2,keepcnt=3,sndbuf=2097152,rcvbuf=2097152 UDP4:${KHAREJ_IP}:${D_PORT},sndbuf=2097152,rcvbuf=2097152 & "
        done
        EXEC_CMD+="wait'"

        cat <<EOF > /etc/systemd/system/direct-client.service
[Unit]
Description=Direct Hardened Outage Tunnel Client Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable direct-client.service
        systemctl restart direct-client.service
        echo -e "${GREEN}[✔] Direct Outage-Resistant Tunnel Active & Forwarded!${NC}"
    fi
}

# --- 11. KCP ULTRA OUTAGE TUNNEL ---
install_kcptun() {
    if ! command -v kcptun-server &>/dev/null || ! command -v kcptun-client &>/dev/null; then
        echo -e "${YELLOW}[*] Downloading and installing Kcptun Engine...${NC}"
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64|amd64) KCP_ARCH="amd64" ;;
            aarch64|arm64) KCP_ARCH="arm64" ;;
            *) KCP_ARCH="amd64" ;;
        esac
        
        KCP_VER=$(curl -s https://api.github.com/repos/xtaci/kcptun/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        KCP_VER=${KCP_VER:-v20240108}
        KCP_TAG=${KCP_VER#v}
        
        rm -f /tmp/kcptun.tar.gz
        wget -q --show-progress -O /tmp/kcptun.tar.gz "https://github.com/xtaci/kcptun/releases/download/${KCP_VER}/kcptun-linux-${KCP_ARCH}-${KCP_TAG}.tar.gz"
        if [ -s /tmp/kcptun.tar.gz ]; then
            tar -xzf /tmp/kcptun.tar.gz -C /tmp 2>/dev/null
            mv /tmp/server_linux_${KCP_ARCH} /usr/local/bin/kcptun-server 2>/dev/null || mv /tmp/server_linux* /usr/local/bin/kcptun-server 2>/dev/null
            mv /tmp/client_linux_${KCP_ARCH} /usr/local/bin/kcptun-client 2>/dev/null || mv /tmp/client_linux* /usr/local/bin/kcptun-client 2>/dev/null
            chmod +x /usr/local/bin/kcptun-server /usr/local/bin/kcptun-client 2>/dev/null
            rm -rf /tmp/kcptun*
            echo -e "${GREEN}[✔] Kcptun Engine successfully installed!${NC}"
        else
            echo -e "${RED}[✖] Failed to download Kcptun binary.${NC}"
            return 1
        fi
    fi
}

deploy_kcp_outage_tunnel() {
    install_deps
    install_kcptun
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}  DEPLOY KCP ULTRA OUTAGE TUNNEL (PACKET-LOSS PROOF)  ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW}[!] Designed for total international blackout & extreme packet loss${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    read -p "Enter KCP Tunnel Secret Key (Default: aether2026): " KCP_KEY
    KCP_KEY=${KCP_KEY:-aether2026}

    if [ "$role" == "1" ]; then
        read -p "Enter KCP Listening UDP Port (Default: 29900): " KCP_PORT
        KCP_PORT=${KCP_PORT:-29900}
        read -p "Enter Target Panel Local Port (e.g., 4141): " TARGET_PORT

        fuser -k "${KCP_PORT}/udp" &>/dev/null
        ufw allow "$KCP_PORT"/udp &>/dev/null

        cat <<EOF > /etc/systemd/system/kcp-server.service
[Unit]
Description=KCP Ultra Outage Tunnel Server Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kcptun-server -listen :${KCP_PORT} -target 127.0.0.1:${TARGET_PORT} --key ${KCP_KEY} --crypt aes --mode fast3 --mtu 1350 --sndwnd 2048 --rcvwnd 2048
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable kcp-server.service
        systemctl restart kcp-server.service
        echo -e "${GREEN}[✔] KCP Outage Tunnel Server Active on UDP Port ${KCP_PORT}!${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server DIRECT IP: " KHAREJ_IP
        read -p "Enter Foreign KCP UDP Port (Default: 29900): " KCP_PORT
        KCP_PORT=${KCP_PORT:-29900}
        read -p "Enter Local Port to Forward (e.g., 4141): " LOCAL_PORT

        fuser -k "${LOCAL_PORT}/tcp" &>/dev/null
        ufw allow "${LOCAL_PORT}"/tcp &>/dev/null

        cat <<EOF > /etc/systemd/system/kcp-client.service
[Unit]
Description=KCP Ultra Outage Tunnel Client Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kcptun-client -listen :${LOCAL_PORT} -r ${KHAREJ_IP}:${KCP_PORT} --key ${KCP_KEY} --crypt aes --mode fast3 --mtu 1350 --sndwnd 2048 --rcvwnd 2048
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable kcp-client.service
        systemctl restart kcp-client.service
        echo -e "${GREEN}[✔] KCP Ultra Outage Tunnel Active & Forwarded on Port ${LOCAL_PORT}!${NC}"
    fi
}

# --- 12. GOST TURBO TUNNEL ---
install_gost() {
    if ! command -v gost &>/dev/null; then
        echo -e "${YELLOW}[*] Downloading and Installing GOST Engine...${NC}"
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64|amd64) GOST_ARCH="amd64" ;;
            aarch64|arm64) GOST_ARCH="armv8" ;;
            *) GOST_ARCH="amd64" ;;
        esac

        GOST_VER=$(curl -s https://api.github.com/repos/ginuerzh/gost/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        GOST_VER=${GOST_VER:-v2.11.5}
        GOST_TAG=${GOST_VER#v}

        rm -f /tmp/gost.gz
        wget -q --show-progress -O /tmp/gost.gz "https://github.com/ginuerzh/gost/releases/download/${GOST_VER}/gost-linux-${GOST_ARCH}-${GOST_TAG}.gz"
        if [ -s /tmp/gost.gz ]; then
            gzip -d /tmp/gost.gz
            mv /tmp/gost /usr/local/bin/gost
            chmod +x /usr/local/bin/gost
            echo -e "${GREEN}[✔] GOST Engine successfully installed!${NC}"
        else
            echo -e "${RED}[✖] Failed to download GOST binary.${NC}"
            return 1
        fi
    fi
}

deploy_gost_tunnel() {
    install_deps
    install_gost
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}  DEPLOY GOST TURBO TUNNEL (ULTRA LOW PING & HIGH SPEED) ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW}[!] High-Performance Dual-Stack TCP/UDP Relay Engine${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    read -p "Enter GOST Tunnel Port (Default: 8443): " GOST_PORT
    GOST_PORT=${GOST_PORT:-8443}

    if [ "$role" == "1" ]; then
        read -p "Enter Target Panel Local Port (e.g., 4141): " TARGET_PORT

        fuser -k "${GOST_PORT}/tcp" &>/dev/null
        fuser -k "${GOST_PORT}/udp" &>/dev/null
        ufw allow "$GOST_PORT"/tcp &>/dev/null
        ufw allow "$GOST_PORT"/udp &>/dev/null

        cat <<EOF > /etc/systemd/system/gost-server.service
[Unit]
Description=GOST Turbo Tunnel Server Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L=tcp://:${GOST_PORT}/127.0.0.1:${TARGET_PORT} -L=udp://:${GOST_PORT}/127.0.0.1:${TARGET_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable gost-server.service
        systemctl restart gost-server.service
        echo -e "${GREEN}[✔] GOST Turbo Tunnel Server Active on Port ${GOST_PORT}!${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Foreign Server IP: " KHAREJ_IP
        read -p "Enter Local Ports to Forward (comma separated, e.g., 4141,8080): " PORTS

        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        EXEC_CMD="/bin/bash -c '"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            fuser -k "${PORT}/tcp" &>/dev/null
            fuser -k "${PORT}/udp" &>/dev/null
            ufw allow "$PORT"/tcp &>/dev/null
            ufw allow "$PORT"/udp &>/dev/null
            EXEC_CMD+="/usr/local/bin/gost -L=tcp://:${PORT}/${KHAREJ_IP}:${GOST_PORT} -L=udp://:${PORT}/${KHAREJ_IP}:${GOST_PORT} & "
        done
        EXEC_CMD+="wait'"

        cat <<EOF > /etc/systemd/system/gost-client.service
[Unit]
Description=GOST Turbo Tunnel Client Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable gost-client.service
        systemctl restart gost-client.service
        echo -e "${GREEN}[✔] GOST Turbo Tunnel Client Active & Ports Forwarded!${NC}"
    fi
}

# --- 13. REAL IP SPOOFING & PASSTHROUGH TUNNEL ---
deploy_real_ip_spoof_tunnel() {
    install_deps
    modprobe ip_gre &>/dev/null
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}    DEPLOY REAL IP SPOOFING / SOURCE PASSTHROUGH       ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW}[!] Preserves REAL Client IP end-to-end via GRE Layer-3 & Route Policy${NC}"
    echo -e "${GREEN}[1]${NC} Foreign Server (Kharej Node)"
    echo -e "${GREEN}[2]${NC} Iran Server (Relay Node)"
    read -p "Select Server Role [1-2]: " role

    read -p "Enter Iran Server IP: " IRAN_IP
    read -p "Enter Foreign Server IP: " KHAREJ_IP

    if [ "$role" == "1" ]; then
        read -p "Enter Target Panel Local Port (e.g., 4141): " TARGET_PORT

        cat <<EOF > /etc/systemd/system/ip-spoof-tunnel.service
[Unit]
Description=Real IP Spoofing GRE Tunnel (Foreign Node)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "modprobe ip_gre 2>/dev/null; ip link del spoof_aether 2>/dev/null; ip link add dev spoof_aether type gre remote ${IRAN_IP} local ${KHAREJ_IP} ttl 255 && ip addr add 10.99.99.2/30 dev spoof_aether && ip link set spoof_aether mtu 1420 && ip link set spoof_aether up && sysctl -w net.ipv4.conf.spoof_aether.rp_filter=0 2>/dev/null && iptables -A FORWARD -i spoof_aether -j ACCEPT && iptables -t nat -A PREROUTING -i spoof_aether -p tcp --dport ${TARGET_PORT} -j REDIRECT --to-ports ${TARGET_PORT} && iptables -t nat -A PREROUTING -i spoof_aether -p udp --dport ${TARGET_PORT} -j REDIRECT --to-ports ${TARGET_PORT}"
ExecStop=/bin/bash -c "ip link set spoof_aether down 2>/dev/null; ip link del spoof_aether 2>/dev/null"

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ip-spoof-tunnel.service
        systemctl restart ip-spoof-tunnel.service
        echo -e "${GREEN}[✔] Real IP Passthrough Tunnel Active on Foreign Server (MTU: 1420)${NC}"

    elif [ "$role" == "2" ]; then
        read -p "Enter Local Forward Ports (comma separated, e.g., 4141,8080): " PORTS

        IPT_CMD=""
        IFS=',' read -ra PORT_LIST <<< "$PORTS"
        for PORT in "${PORT_LIST[@]}"; do
            PORT=$(echo "$PORT" | xargs)
            ufw allow "$PORT"/tcp &>/dev/null
            ufw allow "$PORT"/udp &>/dev/null
            IPT_CMD+="iptables -t nat -A PREROUTING -p tcp --dport ${PORT} -j DNAT --to-destination 10.99.99.2:${PORT} && "
            IPT_CMD+="iptables -t nat -A PREROUTING -p udp --dport ${PORT} -j DNAT --to-destination 10.99.99.2:${PORT} && "
        done

        cat <<EOF > /etc/systemd/system/ip-spoof-tunnel.service
[Unit]
Description=Real IP Spoofing GRE Tunnel (Iran Node)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "modprobe ip_gre 2>/dev/null; ip link del spoof_aether 2>/dev/null; ip link add dev spoof_aether type gre remote ${KHAREJ_IP} local ${IRAN_IP} ttl 255 && ip addr add 10.99.99.1/30 dev spoof_aether && ip link set spoof_aether mtu 1420 && ip link set spoof_aether up && sysctl -w net.ipv4.conf.spoof_aether.rp_filter=0 2>/dev/null && ${IPT_CMD} true"
ExecStop=/bin/bash -c "ip link set spoof_aether down 2>/dev/null; ip link del spoof_aether 2>/dev/null"

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ip-spoof-tunnel.service
        systemctl restart ip-spoof-tunnel.service
        netfilter-persistent save &>/dev/null
        echo -e "${GREEN}[✔] Real IP Spoofing/Passthrough Tunnel Active on Iran Relay Node!${NC}"
    fi
}

# --- 14. AETHER WEB MANAGEMENT PANEL (AUTHENTICATED & ADVANCED DASHBOARD) ---
uninstall_web_panel() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}       UNINSTALL AETHER WEB MANAGEMENT PANEL          ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW}[*] Purging Web Panel service, scripts, and configuration files...${NC}"

    systemctl stop aether-webpanel.service 2>/dev/null
    systemctl disable aether-webpanel.service 2>/dev/null
    rm -f /etc/systemd/system/aether-webpanel.service
    systemctl daemon-reload 2>/dev/null

    rm -rf /etc/aether/panel 2>/dev/null
    pkill -9 -f "app.py" 2>/dev/null

    echo -e "${GREEN}[✔] Web Management Panel has been completely uninstalled from root!${NC}"
}

deploy_web_panel() {
    install_deps
    install_python_deps
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}  DEPLOY AETHER WEB MANAGEMENT PANEL (ADVANCED DASHBOARD) ${NC}"
    echo -e "${CYAN}======================================================${NC}"

    read -p "Enter Panel Web Port (Default: 9090): " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-9090}

    while [[ -z "$PANEL_USER" ]]; do
        read -p "Enter Admin Username: " PANEL_USER
    done

    while [[ -z "$PANEL_PASS" ]]; do
        read -s -p "Enter Admin Password: " PANEL_PASS
        echo ""
    done

    mkdir -p /etc/aether/panel
    fuser -k "${PANEL_PORT}/tcp" &>/dev/null
    ufw allow "$PANEL_PORT"/tcp &>/dev/null

    cat <<EOF > /etc/aether/panel/config.py
ADMIN_USER = "${PANEL_USER}"
ADMIN_PASS = "${PANEL_PASS}"
EOF

    # Write Advanced Flask App Engine with Session Auth & Dynamic Creation UI
    cat <<'EOF' > /etc/aether/panel/app.py
import sys
import subprocess
import os
from flask import Flask, render_template_string, request, redirect, url_for, session, jsonify

try:
    import psutil
except ImportError:
    psutil = None

import config

app = Flask(__name__)
app.secret_key = os.urandom(24)

SERVICES = [
    {"id": "aether-elite", "name": "Aether Elite Multiplex", "svc": "aether-elite.service", "desc": "High-Speed Anti-DPI Relay"},
    {"id": "gre-tunnel", "name": "Native GRE Tunnel", "svc": "gre-tunnel.service", "desc": "Layer 3 Raw Kernel Tunnel"},
    {"id": "ipip-tunnel", "name": "Native IPIP Tunnel", "svc": "ipip-tunnel.service", "desc": "Lightweight Encapsulation Tunnel"},
    {"id": "hans-server", "name": "Hans ICMP Server", "svc": "hans-server.service", "desc": "Ping Protocol Concealment Engine"},
    {"id": "hans-client", "name": "Hans ICMP Client", "svc": "hans-client.service", "desc": "Ping Relay Edge Client"},
    {"id": "http-server", "name": "HTTP Masking Server", "svc": "http-server.service", "desc": "Encapsulated HTTP Traffic Masking"},
    {"id": "http-client", "name": "HTTP Masking Client", "svc": "http-client.service", "desc": "Encapsulated HTTP Inbound Client"},
    {"id": "ss-server", "name": "Shadowsocks AEAD Server", "svc": "ss-server.service", "desc": "ChaCha20 Secure Protocol"},
    {"id": "ss-client", "name": "Shadowsocks AEAD Client", "svc": "ss-client.service", "desc": "Inbound Forwarding Client"},
    {"id": "quantum-server", "name": "Quantum QUIC Server", "svc": "quantum-server.service", "desc": "Fast UDP Multiplex Tunnel"},
    {"id": "quantum-client", "name": "Quantum QUIC Client", "svc": "quantum-client.service", "desc": "Fast UDP Relay Engine"},
    {"id": "ws-server", "name": "WebSocket Stealth Server", "svc": "ws-server.service", "desc": "CDN / Cloudflare Bypass Tunnel"},
    {"id": "ws-client", "name": "WebSocket Stealth Client", "svc": "ws-client.service", "desc": "CDN Stealth Transport Node"},
    {"id": "grpc-server", "name": "Quantum-gRPC Server", "svc": "grpc-server.service", "desc": "Ultra Stable L7 Stream Tunnel"},
    {"id": "grpc-client", "name": "Quantum-gRPC Client", "svc": "grpc-client.service", "desc": "L7 Stream Transport Engine"},
    {"id": "direct-server", "name": "Direct UDP Hardened Server", "svc": "direct-server.service", "desc": "CDN-Independent Emergency Node"},
    {"id": "direct-client", "name": "Direct UDP Hardened Client", "svc": "direct-client.service", "desc": "Direct IP Hardened Gateway"},
    {"id": "kcp-server", "name": "KCP Ultra Outage Server", "svc": "kcp-server.service", "desc": "Packet Loss Resistance Engine"},
    {"id": "kcp-client", "name": "KCP Ultra Outage Client", "svc": "kcp-client.service", "desc": "Extreme Outage Transport Client"},
    {"id": "gost-server", "name": "GOST Turbo Dual Stack", "svc": "gost-server.service", "desc": "Multi-Port Ultra-Low Ping Tunnel"},
    {"id": "gost-client", "name": "GOST Turbo Client Node", "svc": "gost-client.service", "desc": "Dual TCP/UDP Forwarding Node"},
    {"id": "ip-spoof-tunnel", "name": "Real IP Spoofing Passthrough", "svc": "ip-spoof-tunnel.service", "desc": "Client IP Preserving L3 Tunnel"}
]

LOGIN_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AETHER PANEL - Login</title>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Plus Jakarta Sans', sans-serif; }
        body {
            background-color: #030712; color: #f9fafb; min-height: 100vh;
            display: flex; align-items: center; justify-content: center;
            background-image: radial-gradient(at 0% 0%, rgba(6, 182, 212, 0.15) 0px, transparent 50%),
                              radial-gradient(at 100% 100%, rgba(139, 92, 246, 0.15) 0px, transparent 50%);
        }
        .login-card {
            background: rgba(17, 24, 39, 0.85); border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 20px; padding: 40px; width: 100%; max-width: 420px;
            backdrop-filter: blur(20px); box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
        }
        .login-header { text-align: center; margin-bottom: 30px; }
        .login-icon {
            width: 60px; height: 60px; background: linear-gradient(135deg, #06b6d4, #8b5cf6);
            border-radius: 16px; display: inline-flex; align-items: center; justify-content: center;
            font-size: 28px; color: white; margin-bottom: 15px; box-shadow: 0 0 25px rgba(6, 182, 212, 0.4);
        }
        .login-title { font-size: 22px; font-weight: 800; color: #fff; }
        .login-sub { font-size: 13px; color: #9ca3af; margin-top: 5px; }
        .form-group { margin-bottom: 20px; }
        .form-label { display: block; font-size: 12px; font-weight: 600; color: #9ca3af; margin-bottom: 8px; text-transform: uppercase; }
        .input-box {
            width: 100%; padding: 12px 16px; background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 10px; color: #fff; font-size: 14px;
            outline: none; transition: all 0.2s;
        }
        .input-box:focus { border-color: #06b6d4; background: rgba(255, 255, 255, 0.08); box-shadow: 0 0 10px rgba(6, 182, 212, 0.3); }
        .btn-login {
            width: 100%; padding: 12px; background: linear-gradient(135deg, #06b6d4, #3b82f6);
            border: none; border-radius: 10px; color: white; font-size: 14px; font-weight: 700; cursor: pointer;
            transition: all 0.2s; box-shadow: 0 4px 15px rgba(6, 182, 212, 0.4);
        }
        .btn-login:hover { opacity: 0.95; transform: translateY(-2px); }
        .error-msg { background: rgba(239, 68, 68, 0.2); border: 1px solid rgba(239, 68, 68, 0.4); color: #ef4444; padding: 10px; border-radius: 8px; font-size: 12px; margin-bottom: 15px; text-align: center; }
    </style>
</head>
<body>
    <div class="login-card">
        <div class="login-header">
            <div class="login-icon"><i class="fa-solid fa-shield-halved"></i></div>
            <div class="login-title">AETHER CONTROL PANEL</div>
            <div class="login-sub">Secure Tunnel Management Console</div>
        </div>
        {% if error %}
        <div class="error-msg">{{ error }}</div>
        {% endif %}
        <form method="post" action="/login">
            <div class="form-group">
                <label class="form-label">Username</label>
                <input type="text" name="username" class="input-box" required placeholder="Enter username">
            </div>
            <div class="form-group">
                <label class="form-label">Password</label>
                <input type="password" name="password" class="input-box" required placeholder="Enter password">
            </div>
            <button type="submit" class="btn-login"><i class="fa-solid fa-right-to-bracket"></i> Authenticate</button>
        </form>
    </div>
</body>
</html>
"""

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHANTOM - Aether Control Panel</title>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --bg-primary: #030712;
            --bg-card: rgba(17, 24, 39, 0.7);
            --border-card: rgba(255, 255, 255, 0.08);
            --accent-cyan: #06b6d4;
            --accent-blue: #3b82f6;
            --accent-purple: #8b5cf6;
            --accent-green: #10b981;
            --accent-red: #ef4444;
            --text-main: #f9fafb;
            --text-muted: #9ca3af;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Plus Jakarta Sans', sans-serif; }
        
        body {
            background-color: var(--bg-primary); color: var(--text-main);
            min-height: 100vh; padding: 30px 20px;
            background-image: 
                radial-gradient(at 0% 0%, rgba(6, 182, 212, 0.12) 0px, transparent 50%),
                radial-gradient(at 100% 100%, rgba(139, 92, 246, 0.12) 0px, transparent 50%);
            background-attachment: fixed;
        }

        .container { max-width: 1400px; margin: 0 auto; }

        header {
            display: flex; justify-content: space-between; align-items: center;
            margin-bottom: 30px; padding-bottom: 20px; border-bottom: 1px solid var(--border-card);
        }

        .brand { display: flex; align-items: center; gap: 15px; }
        .brand-icon {
            width: 50px; height: 50px; background: linear-gradient(135deg, var(--accent-cyan), var(--accent-purple));
            border-radius: 14px; display: flex; align-items: center; justify-content: center;
            font-size: 24px; color: white; box-shadow: 0 0 20px rgba(6, 182, 212, 0.4);
        }

        .brand-text h1 { font-size: 24px; font-weight: 800; background: linear-gradient(to right, #fff, var(--text-muted)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .brand-text p { font-size: 13px; color: var(--accent-cyan); font-weight: 600; text-transform: uppercase; letter-spacing: 1px; }

        .system-stats {
            display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 20px; margin-bottom: 35px;
        }

        .stat-card {
            background: var(--bg-card); border: 1px solid var(--border-card);
            border-radius: 16px; padding: 20px; backdrop-filter: blur(12px);
            display: flex; align-items: center; justify-content: space-between;
            transition: all 0.3s ease;
        }
        
        .stat-card:hover { transform: translateY(-3px); border-color: rgba(255, 255, 255, 0.2); }

        .stat-info h3 { font-size: 13px; color: var(--text-muted); font-weight: 500; margin-bottom: 6px; }
        .stat-info p { font-size: 26px; font-weight: 800; color: #fff; }

        .stat-icon {
            width: 48px; height: 48px; border-radius: 12px;
            display: flex; align-items: center; justify-content: center; font-size: 20px;
        }

        .stat-icon.cpu { background: rgba(59, 130, 246, 0.15); color: var(--accent-blue); }
        .stat-icon.ram { background: rgba(139, 92, 246, 0.15); color: var(--accent-purple); }
        .stat-icon.active-tunnels { background: rgba(16, 185, 129, 0.15); color: var(--accent-green); }
        .stat-icon.network { background: rgba(6, 182, 212, 0.15); color: var(--accent-cyan); }

        .control-bar {
            display: flex; justify-content: space-between; align-items: center;
            margin-bottom: 25px; flex-wrap: wrap; gap: 15px;
        }

        .section-title { font-size: 18px; font-weight: 700; display: flex; align-items: center; gap: 10px; }
        .section-title i { color: var(--accent-cyan); }

        .global-actions { display: flex; gap: 10px; flex-wrap: wrap; }

        .btn {
            padding: 10px 18px; border-radius: 10px; border: none; font-size: 13px; font-weight: 600;
            cursor: pointer; display: inline-flex; align-items: center; gap: 8px;
            transition: all 0.2s ease; text-decoration: none;
        }

        .btn-create { background: linear-gradient(135deg, #10b981, #059669); color: white; box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3); }
        .btn-restart-all { background: linear-gradient(135deg, #0284c7, #2563eb); color: white; box-shadow: 0 4px 12px rgba(2, 132, 199, 0.3); }
        .btn-stop-all { background: linear-gradient(135deg, #dc2626, #b91c1c); color: white; box-shadow: 0 4px 12px rgba(220, 38, 38, 0.3); }
        .btn-logout { background: rgba(255, 255, 255, 0.08); border: 1px solid var(--border-card); color: var(--text-muted); }
        .btn-logout:hover { color: #fff; background: rgba(255, 255, 255, 0.15); }
        .btn-create:hover, .btn-restart-all:hover, .btn-stop-all:hover { opacity: 0.9; transform: scale(1.02); }

        .tunnel-grid {
            display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 20px;
        }

        .tunnel-card {
            background: var(--bg-card); border: 1px solid var(--border-card);
            border-radius: 18px; padding: 22px; backdrop-filter: blur(16px);
            display: flex; flex-direction: column; justify-content: space-between;
            position: relative; transition: all 0.3s ease;
        }

        .tunnel-card:hover { border-color: rgba(6, 182, 212, 0.4); transform: translateY(-4px); }

        .tunnel-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px; }
        .tunnel-title { font-size: 16px; font-weight: 700; color: #fff; margin-bottom: 4px; }
        .tunnel-desc { font-size: 12px; color: var(--text-muted); line-height: 1.4; }

        .badge {
            padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: 700; text-transform: uppercase;
            display: inline-flex; align-items: center; gap: 6px;
        }

        .badge-running { background: rgba(16, 185, 129, 0.15); color: var(--accent-green); border: 1px solid rgba(16, 185, 129, 0.3); }
        .badge-stopped { background: rgba(239, 68, 68, 0.15); color: var(--accent-red); border: 1px solid rgba(239, 68, 68, 0.3); }

        .badge-dot { width: 6px; height: 6px; border-radius: 50%; }
        .badge-running .badge-dot { background: var(--accent-green); box-shadow: 0 0 8px var(--accent-green); }
        .badge-stopped .badge-dot { background: var(--accent-red); }

        .tunnel-footer {
            margin-top: 20px; padding-top: 15px; border-top: 1px solid rgba(255, 255, 255, 0.05);
            display: flex; justify-content: space-between; align-items: center;
        }

        .card-actions { display: flex; gap: 8px; }

        .btn-card {
            padding: 8px 12px; border-radius: 8px; border: 1px solid var(--border-card);
            background: rgba(255, 255, 255, 0.05); color: #fff; font-size: 12px; font-weight: 600;
            cursor: pointer; transition: all 0.2s ease;
        }

        .btn-card:hover { background: rgba(255, 255, 255, 0.15); }
        .btn-card.start:hover { background: rgba(16, 185, 129, 0.2); color: var(--accent-green); border-color: var(--accent-green); }
        .btn-card.stop:hover { background: rgba(239, 68, 68, 0.2); color: var(--accent-red); border-color: var(--accent-red); }
        .btn-card.restart:hover { background: rgba(6, 182, 212, 0.2); color: var(--accent-cyan); border-color: var(--accent-cyan); }
        .btn-card.delete:hover { background: rgba(239, 68, 68, 0.3); color: #f87171; border-color: var(--accent-red); }

        form { display: inline; }

        /* Modal Styles */
        .modal {
            display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%;
            background-color: rgba(0, 0, 0, 0.75); backdrop-filter: blur(8px);
            align-items: center; justify-content: center;
        }
        .modal-content {
            background: rgba(17, 24, 39, 0.95); border: 1px solid var(--border-card);
            border-radius: 20px; padding: 30px; width: 100%; max-width: 500px;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6);
        }
        .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
        .modal-title { font-size: 18px; font-weight: 800; color: #fff; }
        .close-modal { font-size: 20px; color: var(--text-muted); cursor: pointer; }
        .close-modal:hover { color: #fff; }
        .form-group { margin-bottom: 15px; }
        .form-label { display: block; font-size: 12px; font-weight: 600; color: var(--text-muted); margin-bottom: 6px; text-transform: uppercase; }
        .input-box, .select-box {
            width: 100%; padding: 10px 14px; background: rgba(255, 255, 255, 0.05);
            border: 1px solid var(--border-card); border-radius: 10px; color: #fff; font-size: 13px;
            outline: none; transition: all 0.2s;
        }
        .select-box option { background: #111827; color: #fff; }
        .input-box:focus, .select-box:focus { border-color: var(--accent-cyan); background: rgba(255, 255, 255, 0.08); }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="brand">
                <div class="brand-icon"><i class="fa-solid fa-bolt"></i></div>
                <div class="brand-text">
                    <h1>PHANTOM ENGINE</h1>
                    <p>Aether Core v23.6 - Advanced Dashboard</p>
                </div>
            </div>
            <div class="global-actions">
                <button onclick="openModal()" class="btn btn-create"><i class="fa-solid fa-plus"></i> Create Tunnel</button>
                <form action="/action" method="post">
                    <input type="hidden" name="svc" value="all">
                    <input type="hidden" name="act" value="restart">
                    <button type="submit" class="btn btn-restart-all"><i class="fa-solid fa-rotate-right"></i> Restart All</button>
                </form>
                <form action="/action" method="post">
                    <input type="hidden" name="svc" value="all">
                    <input type="hidden" name="act" value="stop">
                    <button type="submit" class="btn btn-stop-all"><i class="fa-solid fa-power-off"></i> Stop All</button>
                </form>
                <a href="/logout" class="btn btn-logout"><i class="fa-solid fa-right-from-bracket"></i> Logout</a>
            </div>
        </header>

        <div class="system-stats">
            <div class="stat-card">
                <div class="stat-info">
                    <h3>CPU USAGE</h3>
                    <p id="cpu-val">{{ stats.cpu }}%</p>
                </div>
                <div class="stat-icon cpu"><i class="fa-solid fa-microchip"></i></div>
            </div>
            <div class="stat-card">
                <div class="stat-info">
                    <h3>RAM USAGE</h3>
                    <p id="ram-val">{{ stats.ram }}%</p>
                </div>
                <div class="stat-icon ram"><i class="fa-solid fa-memory"></i></div>
            </div>
            <div class="stat-card">
                <div class="stat-info">
                    <h3>ACTIVE TUNNELS</h3>
                    <p>{{ stats.active_count }} / {{ services|length }}</p>
                </div>
                <div class="stat-icon active-tunnels"><i class="fa-solid fa-network-wired"></i></div>
            </div>
            <div class="stat-card">
                <div class="stat-info">
                    <h3>ENGINE STATUS</h3>
                    <p style="color: var(--accent-green); font-size: 20px;">OPTIMIZED</p>
                </div>
                <div class="stat-icon network"><i class="fa-solid fa-shield-halved"></i></div>
            </div>
        </div>

        <div class="control-bar">
            <div class="section-title"><i class="fa-solid fa-server"></i> Active Tunnel Frameworks</div>
        </div>

        <div class="tunnel-grid">
            {% for item in services %}
            <div class="tunnel-card">
                <div>
                    <div class="tunnel-header">
                        <div class="tunnel-title">{{ item.name }}</div>
                        <span class="badge {{ 'badge-running' if item.active else 'badge-stopped' }}">
                            <span class="badge-dot"></span> {{ 'RUNNING' if item.active else 'STOPPED' }}
                        </span>
                    </div>
                    <div class="tunnel-desc">{{ item.desc }}</div>
                </div>

                <div class="tunnel-footer">
                    <span style="font-size: 11px; color: var(--text-muted); font-family: monospace;">{{ item.svc }}</span>
                    <div class="card-actions">
                        {% if item.active %}
                        <form action="/action" method="post">
                            <input type="hidden" name="svc" value="{{ item.svc }}">
                            <input type="hidden" name="act" value="restart">
                            <button type="submit" class="btn-card restart" title="Restart Tunnel"><i class="fa-solid fa-rotate"></i></button>
                        </form>
                        <form action="/action" method="post">
                            <input type="hidden" name="svc" value="{{ item.svc }}">
                            <input type="hidden" name="act" value="stop">
                            <button type="submit" class="btn-card stop" title="Stop Tunnel"><i class="fa-solid fa-stop"></i></button>
                        </form>
                        {% else %}
                        <form action="/action" method="post">
                            <input type="hidden" name="svc" value="{{ item.svc }}">
                            <input type="hidden" name="act" value="start">
                            <button type="submit" class="btn-card start" title="Start Tunnel"><i class="fa-solid fa-play"></i> Start</button>
                        </form>
                        {% endif %}
                        <form action="/action" method="post" onsubmit="return confirm('Are you sure you want to delete this tunnel?');">
                            <input type="hidden" name="svc" value="{{ item.svc }}">
                            <input type="hidden" name="act" value="delete">
                            <button type="submit" class="btn-card delete" title="Delete Tunnel"><i class="fa-solid fa-trash"></i></button>
                        </form>
                    </div>
                </div>
            </div>
            {% endfor %}
        </div>
    </div>

    <!-- Modal for Creating Tunnel -->
    <div id="createModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <div class="modal-title"><i class="fa-solid fa-plus-circle"></i> Create New Tunnel</div>
                <span class="close-modal" onclick="closeModal()">&times;</span>
            </div>
            <form action="/create" method="post">
                <div class="form-group">
                    <label class="form-label">Tunnel Type</label>
                    <select name="tunnel_type" class="select-box" required>
                        <option value="aether-elite">Aether Elite Multiplex</option>
                        <option value="gre-tunnel">GRE Tunnel</option>
                        <option value="ipip-tunnel">IPIP Tunnel</option>
                        <option value="http">HTTP Encapsulated Tunnel</option>
                        <option value="ss">Shadowsocks Tunnel</option>
                        <option value="quantum">Quantum QUIC Tunnel</option>
                        <option value="ws">WebSocket Stealth Tunnel</option>
                        <option value="grpc">Quantum-gRPC Stealth Tunnel</option>
                        <option value="direct">Direct UDP Hardened Tunnel</option>
                        <option value="kcp">KCP Ultra Outage Tunnel</option>
                        <option value="gost">GOST Turbo Tunnel</option>
                    </select>
                </div>
                <div class="form-group">
                    <label class="form-label">Node Role</label>
                    <select name="role" class="select-box" onchange="toggleRoleFields(this.value)" required>
                        <option value="1">Foreign Server (Kharej Node)</option>
                        <option value="2">Iran Server (Relay Node)</option>
                    </select>
                </div>
                <div class="form-group" id="kharej_ip_group" style="display:none;">
                    <label class="form-label">Foreign Server IP / Domain</label>
                    <input type="text" name="kharej_ip" class="input-box" placeholder="e.g. 1.2.3.4">
                </div>
                <div class="form-group" id="iran_ip_group" style="display:none;">
                    <label class="form-label">Iran Server IP (For GRE/IPIP)</label>
                    <input type="text" name="iran_ip" class="input-box" placeholder="e.g. 5.6.7.8">
                </div>
                <div class="form-group">
                    <label class="form-label">Tunnel Listening Port</label>
                    <input type="number" name="tun_port" class="input-box" placeholder="e.g. 7777" required>
                </div>
                <div class="form-group">
                    <label class="form-label">Panel/Forward Target Port(s)</label>
                    <input type="text" name="target_port" class="input-box" placeholder="e.g. 4141 or 4141,8080" required>
                </div>
                <button type="submit" class="btn btn-create" style="width: 100%; justify-content: center; margin-top: 10px;">
                    <i class="fa-solid fa-check"></i> Create & Launch Tunnel
                </button>
            </form>
        </div>
    </div>

    <script>
        function openModal() { document.getElementById('createModal').style.display = 'flex'; }
        function closeModal() { document.getElementById('createModal').style.display = 'none'; }
        function toggleRoleFields(val) {
            if(val === "2") {
                document.getElementById('kharej_ip_group').style.display = 'block';
            } else {
                document.getElementById('kharej_ip_group').style.display = 'none';
            }
        }
        window.onclick = function(event) {
            let modal = document.getElementById('createModal');
            if (event.target == modal) { closeModal(); }
        }
    </script>
</body>
</html>
"""

def is_svc_active(svc_name):
    res = subprocess.run(["systemctl", "is-active", "--quiet", svc_name])
    return res.returncode == 0

def get_sys_stats():
    cpu = psutil.cpu_percent(interval=None) if psutil else 0
    ram = psutil.virtual_memory().percent if psutil else 0
    return {"cpu": cpu, "ram": ram}

@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form.get("username")
        password = request.form.get("password")
        if username == config.ADMIN_USER and password == config.ADMIN_PASS:
            session["logged_in"] = True
            return redirect(url_for("index"))
        else:
            error = "Invalid Credentials"
    return render_template_string(LOGIN_TEMPLATE, error=error)

@app.route("/logout")
def logout():
    session.pop("logged_in", None)
    return redirect(url_for("login"))

@app.route("/")
def index():
    if not session.get("logged_in"):
        return redirect(url_for("login"))

    active_cnt = 0
    service_states = []
    
    for item in SERVICES:
        active = is_svc_active(item["svc"])
        if active:
            active_cnt += 1
        service_states.append({
            "id": item["id"],
            "name": item["name"],
            "svc": item["svc"],
            "desc": item["desc"],
            "active": active
        })
        
    stats = get_sys_stats()
    stats["active_count"] = active_cnt
    
    return render_template_string(HTML_TEMPLATE, services=service_states, stats=stats)

@app.route("/action", methods=["POST"])
def handle_action():
    if not session.get("logged_in"):
        return redirect(url_for("login"))

    svc = request.form.get("svc")
    act = request.form.get("act")
    
    all_svcs = [item["svc"] for item in SERVICES]
    
    if svc == "all":
        targets = all_svcs
    else:
        targets = [svc] if svc in all_svcs else []
        
    for target in targets:
        if act in ["start", "stop", "restart"]:
            subprocess.run(["systemctl", act, target])
        elif act == "delete":
            subprocess.run(["systemctl", "stop", target])
            subprocess.run(["systemctl", "disable", target])
            svc_path = f"/etc/systemd/system/{target}"
            if os.path.exists(svc_path):
                os.remove(svc_path)
            subprocess.run(["systemctl", "daemon-reload"])
            
    return redirect(url_for("index"))

@app.route("/create", methods=["POST"])
def create_tunnel():
    if not session.get("logged_in"):
        return redirect(url_for("login"))

    t_type = request.form.get("tunnel_type")
    role = request.form.get("role")
    kharej_ip = request.form.get("kharej_ip", "")
    iran_ip = request.form.get("iran_ip", "")
    tun_port = request.form.get("tun_port")
    target_port = request.form.get("target_port")

    svc_name = f"{t_type}-{'server' if role == '1' else 'client'}.service"
    if t_type == "aether-elite":
        svc_name = "aether-elite.service"

    exec_cmd = ""
    if t_type == "aether-elite":
        if role == "1":
            exec_cmd = f"/usr/bin/socat TCP-LISTEN:{tun_port},reuseaddr,fork TCP:127.0.0.1:{target_port}"
        else:
            ports = [p.strip() for p in target_port.split(",")]
            cmds = " & ".join([f"socat TCP-LISTEN:{p},reuseaddr,fork TCP:{kharej_ip}:{tun_port}" for p in ports])
            exec_cmd = f"/bin/bash -c '{cmds} & wait'"

    elif t_type == "http":
        if role == "1":
            exec_cmd = f"/usr/bin/socat TCP-LISTEN:{tun_port},reuseaddr,fork TCP:127.0.0.1:{target_port}"
        else:
            ports = [p.strip() for p in target_port.split(",")]
            cmds = " & ".join([f"socat TCP-LISTEN:{p},reuseaddr,fork TCP:{kharej_ip}:{tun_port}" for p in ports])
            exec_cmd = f"/bin/bash -c '{cmds} & wait'"

    elif t_type == "ws":
        if role == "1":
            exec_cmd = f"/usr/bin/socat -d -d TCP-LISTEN:{tun_port},reuseaddr,fork,keepalive,keepidle=10,keepintvl=5,keepcnt=3 TCP:127.0.0.1:{target_port}"
        else:
            ports = [p.strip() for p in target_port.split(",")]
            cmds = " & ".join([f"socat TCP-LISTEN:{p},reuseaddr,fork,keepalive,keepidle=10,keepintvl=5,keepcnt=3 TCP:{kharej_ip}:{tun_port}" for p in ports])
            exec_cmd = f"/bin/bash -c '{cmds} & wait'"

    elif t_type == "grpc":
        if role == "1":
            exec_cmd = f"/usr/bin/socat -d -d TCP-LISTEN:{tun_port},reuseaddr,fork,nodelay TCP:127.0.0.1:{target_port}"
        else:
            ports = [p.strip() for p in target_port.split(",")]
            cmds = " & ".join([f"socat TCP-LISTEN:{p},reuseaddr,fork,nodelay TCP:{kharej_ip}:{tun_port}" for p in ports])
            exec_cmd = f"/bin/bash -c '{cmds} & wait'"

    elif t_type == "direct":
        if role == "1":
            exec_cmd = f"/usr/bin/socat -d -d UDP4-LISTEN:{tun_port},reuseaddr,fork TCP4:127.0.0.1:{target_port}"
        else:
            ports = [p.strip() for p in target_port.split(",")]
            cmds = " & ".join([f"socat TCP4-LISTEN:{p},reuseaddr,fork UDP4:{kharej_ip}:{tun_port}" for p in ports])
            exec_cmd = f"/bin/bash -c '{cmds} & wait'"

    elif t_type == "quantum":
        if role == "1":
            exec_cmd = f"/usr/bin/socat UDP4-LISTEN:{tun_port},reuseaddr,fork TCP4:127.0.0.1:{target_port}"
        else:
            ports = [p.strip() for p in target_port.split(",")]
            cmds = " & ".join([f"socat TCP4-LISTEN:{p},reuseaddr,fork UDP4:{kharej_ip}:{tun_port}" for p in ports])
            exec_cmd = f"/bin/bash -c '{cmds} & wait'"

    elif t_type == "gost":
        if role == "1":
            exec_cmd = f"/usr/local/bin/gost -L=tcp://:{tun_port}/127.0.0.1:{target_port} -L=udp://:{tun_port}/127.0.0.1:{target_port}"
        else:
            ports = [p.strip() for p in target_port.split(",")]
            cmds = " & ".join([f"/usr/local/bin/gost -L=tcp://:{p}/{kharej_ip}:{tun_port} -L=udp://:{p}/{kharej_ip}:{tun_port}" for p in ports])
            exec_cmd = f"/bin/bash -c '{cmds} & wait'"

    else:
        # Default fallback command socat
        exec_cmd = f"/usr/bin/socat TCP-LISTEN:{tun_port},reuseaddr,fork TCP:127.0.0.1:{target_port}"

    service_content = f"""[Unit]
Description=Aether Web Managed Service ({t_type})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart={exec_cmd}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""
    svc_file = f"/etc/systemd/system/{svc_name}"
    with open(svc_file, "w") as f:
        f.write(service_content)

    subprocess.run(["systemctl", "daemon-reload"])
    subprocess.run(["systemctl", "enable", svc_name])
    subprocess.run(["systemctl", "restart", svc_name])

    return redirect(url_for("index"))

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9090
    app.run(host="0.0.0.0", port=port)
EOF

    cat <<EOF > /etc/systemd/system/aether-webpanel.service
[Unit]
Description=Aether Phantom Web Management Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /etc/aether/panel/app.py ${PANEL_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable aether-webpanel.service
    systemctl restart aether-webpanel.service

    SERVER_IP=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")
    echo -e "\n${GREEN}[✔] Advanced Aether Web Panel successfully deployed!${NC}"
    echo -e "${CYAN}------------------------------------------------------${NC}"
    echo -e "${WHITE} Access Dashboard at: ${YELLOW}http://${SERVER_IP}:${PANEL_PORT}${NC}"
    echo -e "${WHITE} Username: ${GREEN}${PANEL_USER}${NC}"
    echo -e "${CYAN}------------------------------------------------------${NC}"
}

# --- SUBMENU FOR TUNNELS ---
tunnel_selection_menu() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}            SELECT TUNNEL PROTOCOL TYPE               ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "  ${GREEN}[1]${NC} 🚀 ${WHITE}Elite Multiplex Tunnel ${CYAN}(Socat / Anti-DPI Recommended)${NC}"
    echo -e "  ${GREEN}[2]${NC} 🌐 ${WHITE}Native GRE Tunnel ${CYAN}(Layer 3 Kernel Tunnel)${NC}"
    echo -e "  ${GREEN}[3]${NC} ⚡ ${WHITE}Native IPIP Tunnel ${CYAN}(Ultra-Light Kernel Tunnel)${NC}"
    echo -e "  ${GREEN}[4]${NC} 🛰️  ${WHITE}Hans ICMP Tunnel ${CYAN}(Ping Protocol Tunneling)${NC}"
    echo -e "  ${GREEN}[5]${NC} 🌐 ${WHITE}HTTP Encapsulated Tunnel ${CYAN}(HTTP Masking Protocol)${NC}"
    echo -e "  ${GREEN}[6]${NC} 🔒 ${WHITE}Shadowsocks Tunnel ${CYAN}(AEAD Encryption Relay)${NC}"
    echo -e "  ${GREEN}[7]${NC} ⚛️  ${WHITE}Quantum-MAX Tunnel ${CYAN}(QUIC / Fast UDP Protocol)${NC}"
    echo -e "  ${GREEN}[8]${NC} 🛡️  ${WHITE}WebSocket Stealth Tunnel ${CYAN}(No-Ping / Bypasses Severe Outages)${NC}"
    echo -e "  ${GREEN}[9]${NC} ⚡ ${WHITE}Quantum-gRPC Stealth Tunnel ${CYAN}(Ultra Stable / L7 CDN Protocol)${NC}"
    echo -e "  ${GREEN}[10]${NC} 🚨 ${WHITE}Direct UDP Hardened Tunnel ${CYAN}(Severe Outage / CDN Independent / Optimized)${NC}"
    echo -e "  ${GREEN}[11]${NC} 💥 ${WHITE}KCP Ultra Outage Tunnel ${CYAN}(Extreme Outage / Anti-Loss / Direct UDP)${NC}"
    echo -e "  ${GREEN}[12]${NC} 🚀 ${WHITE}GOST Turbo Tunnel ${CYAN}(Ultra Low Ping / Multi-Port Dual TCP+UDP Engine)${NC}"
    echo -e "  ${GREEN}[13]${NC} 👺 ${WHITE}Real IP Spoofing Passthrough ${CYAN}(L3 IP Header Preservation)${NC}"
    echo -e "  ${RED}[0]${NC} ↩️  ${WHITE}Back to Main Menu${NC}"
    echo -e "${CYAN}======================================================${NC}"
    read -p " Select Protocol [0-13]: " tun_choice

    case $tun_choice in
        1) deploy_elite_tunnel ;;
        2) deploy_gre_tunnel ;;
        3) deploy_ipip_tunnel ;;
        4) deploy_icmp_tunnel ;;
        5) deploy_http_tunnel ;;
        6) deploy_shadowsocks_tunnel ;;
        7) deploy_quantum_tunnel ;;
        8) deploy_ws_stealth_tunnel ;;
        9) deploy_grpc_stealth_tunnel ;;
        10) deploy_direct_outage_tunnel ;;
        11) deploy_kcp_outage_tunnel ;;
        12) deploy_gost_tunnel ;;
        13) deploy_real_ip_spoof_tunnel ;;
        0) return ;;
        *) echo -e "${RED}Invalid Selection!${NC}"; sleep 1 ;;
    esac
}

setup_cron() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}           AUTOMATED SCHEDULED RESTART (CRON)         ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Restart Every 6 Hours"
    echo -e "${GREEN}[2]${NC} Restart Every 12 Hours"
    echo -e "${GREEN}[3]${NC} Restart Daily (4:00 AM)"
    echo -e "${RED}[4]${NC} Disable Auto-Restart"
    read -p "Select Option [1-4]: " cron_choice

    crontab -l 2>/dev/null | grep -v -E "aether-elite|http-|ss-|quantum-|hans-|ipip-|gre-|ws-|grpc-|direct-|kcp-|gost-|ip-spoof" | crontab -

    case $cron_choice in
        1) (crontab -l 2>/dev/null; echo "0 */6 * * * systemctl restart ${ALL_SERVICES[*]} 2>/dev/null") | crontab - ;;
        2) (crontab -l 2>/dev/null; echo "0 */12 * * * systemctl restart ${ALL_SERVICES[*]} 2>/dev/null") | crontab - ;;
        3) (crontab -l 2>/dev/null; echo "0 4 * * * systemctl restart ${ALL_SERVICES[*]} 2>/dev/null") | crontab - ;;
        4) echo -e "${YELLOW}[*] All cron tasks disabled.${NC}" ;;
    esac
    echo -e "${GREEN}[✔] Cron schedule updated.${NC}"
    read -p "Press [Enter] to return..."
}

manage_service() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}           SERVICE MANAGER & CONFIG EDITOR            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}[1]${NC} Restart All Tunnel Services"
    echo -e "${GREEN}[2]${NC} Stop All Tunnel Services"
    echo -e "${GREEN}[3]${NC} Edit Service File (Nano)"
    echo -e "${RED}[4]${NC} Delete a Specific Tunnel Service (Single Tunnel Delete)"
    echo -e "${RED}[5]${NC} Delete / Purge ALL Active Tunnels (Complete Reset)"
    echo -e "${GREEN}[6]${NC} Check Service Status (All Tunnels)"
    read -p "Select Option [1-6]: " sc
    case $sc in
        1) 
           systemctl restart "${ALL_SERVICES[@]}" 2>/dev/null 
           echo -e "${GREEN}[✔] All services restarted.${NC}" 
           ;;
        2) 
           systemctl stop "${ALL_SERVICES[@]}" 2>/dev/null 
           echo -e "${RED}[!] All services stopped.${NC}" 
           ;;
        3) 
           ACTIVE_SVCS=()
           for svc in "${ALL_SERVICES[@]}"; do
               if [ -f "/etc/systemd/system/$svc" ]; then
                   ACTIVE_SVCS+=("$svc")
               fi
           done
           if [ ${#ACTIVE_SVCS[@]} -gt 0 ]; then
               echo -e "\n${YELLOW}Select service file to edit:${NC}"
               idx=1
               for s in "${ACTIVE_SVCS[@]}"; do
                   echo -e "  [$idx] $s"
                   ((idx++))
               done
               read -p "Choice: " ed_choice
               if [[ "$ed_choice" =~ ^[0-9]+$ ]] && [ "$ed_choice" -gt 0 ] && [ "$ed_choice" -le "${#ACTIVE_SVCS[@]}" ]; then
                   nano "/etc/systemd/system/${ACTIVE_SVCS[$((ed_choice-1))]}" && systemctl daemon-reload
               fi
           else
               echo -e "${RED}[!] No configured tunnel service found to edit.${NC}"
           fi
           ;;
        4) delete_single_tunnel ;;
        5) clean_all_tunnels ;;
        6) systemctl status "${ALL_SERVICES[@]}" 2>/dev/null ;;
    esac
    read -p "Press [Enter] to return..."
}

test_port() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BOLD}${WHITE}               PORT HEALTH VERIFICATION               ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    read -p "Enter Local Port Number to Test: " TEST_PORT
    if nc -zv -w 5 127.0.0.1 "$TEST_PORT" 2>&1; then
        echo -e "\n${GREEN}[✔] SUCCESS: Port $TEST_PORT is ACTIVE and RESPONSIVE!${NC}"
    else
        echo -e "\n${RED}[✖] FAILURE: Port $TEST_PORT is CLOSED or UNREACHABLE.${NC}"
    fi
    read -p "Press [Enter] to return..."
}

while true; do
    clear
    RUNNING_COUNT=0
    for svc in "${ALL_SERVICES[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ((RUNNING_COUNT++))
        fi
    done

    if [ "$RUNNING_COUNT" -gt 0 ]; then
        STATUS="${GREEN}● ACTIVE (${RUNNING_COUNT} Tunnel(s) Running)${NC}"
    else
        STATUS="${RED}● INACTIVE${NC}"
    fi

    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${BOLD}${WHITE}          ⚡ AETHER ELITE TUNNEL FRAMEWORK V23.6 ⚡           ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}         Kernel-Level Multiplexing & High Performance         ${PURPLE}║${NC}"
    echo -e "${PURPLE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║${WHITE} ENGINE STATUS: ${STATUS}                                      ${PURPLE}║${NC}"
    echo -e "${PURPLE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${GREEN}[01]${NC} 🚀 ${WHITE}Deploy Tunnel ${CYAN}(Multi-Tunnel Mode Supported)${NC}"
    echo -e "  ${GREEN}[02]${NC} 🖥️  ${WHITE}Deploy Web Management Panel ${CYAN}(Auth & Advanced UI)${NC}"
    echo -e "  ${GREEN}[03]${NC} ⚡ ${WHITE}Kernel Optimization ${CYAN}(BBR Accelerator)${NC}"
    echo -e "  ${GREEN}[04]${NC} ⏰ ${WHITE}Auto-Restart Scheduler ${CYAN}(CronJob Automation)${NC}"
    echo -e "${PURPLE}────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}[05]${NC} 🛠️  ${WHITE}Manage & Edit / Delete Specific Tunnels${NC}"
    echo -e "  ${YELLOW}[06]${NC} 📜 ${WHITE}View Live System Logs${NC}"
    echo -e "  ${YELLOW}[07]${NC} 🧪 ${WHITE}Test Local Port Health${NC}"
    echo -e "  ${RED}[08]${NC} 🗑️  ${WHITE}Uninstall Web Management Panel ONLY${NC}"
    echo -e "  ${RED}[09]${NC} 🧹 ${WHITE}Reset Network & Purge ALL Tunnels${NC}"
    echo -e "  ${RED}[00]${NC} ❌ ${WHITE}Exit Script${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    read -p " Select Option [0-9]: " choice

    case $choice in
        1|01) tunnel_selection_menu ;;
        2|02) deploy_web_panel; read -p "Press [Enter] to return..." ;;
        3|03) optimize_network ;;
        4|04) setup_cron ;;
        5|05) manage_service ;;
        6|06) 
            clear
            echo -e "${YELLOW}[*] Press Ctrl+C to stop log streaming...${NC}\n"
            journalctl -f -u "${ALL_SERVICES[0]}" 2>/dev/null || journalctl -f
            ;;
        7|07) test_port ;;
        8|08) uninstall_web_panel; read -p "Press [Enter] to return..." ;;
        9|09) clean_all_tunnels; read -p "Press [Enter] to return..." ;;
        0|00) 
            echo -e "${GREEN}\nExiting Aether Framework. Goodbye!${NC}\n"
            exit 0
            ;;
        *) 
            echo -e "${RED}Invalid Option!${NC}"
            sleep 1
            ;;
    esac
done
