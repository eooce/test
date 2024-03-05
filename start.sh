 #!/bin/bash
export UUID=${UUID:-'88888888-8888-8888-8888-888888888888'}
export NEZHA_SERVER=${NEZHA_SERVER:-''}
export NEZHA_PORT=${NEZHA_PORT:-'5555'}  
export NEZHA_KEY=${NEZHA_KEY:-''}
export ARGO_DOMAIN=${ARGO_DOMAIN:-''}  
export ARGO_AUTH=${ARGO_AUTH:-''}
export CFIP=${CFIP:-'na.ma'}
export CFPORT=${CFPORT:-'443'}  
export NAME=${NAME:-'Vls'}
export FILE_PATH=${FILE_PATH:-'./worlds'}
export ARGO_PORT=${ARGO_PORT:-'8001'}  

if [ ! -d "${FILE_PATH}" ]; then
    mkdir ${FILE_PATH}
fi

cleanup_oldfiles() {
  rm -rf ${FILE_PATH}/boot.log ${FILE_PATH}/sub.txt ${FILE_PATH}/config.json ${FILE_PATH}/tunnel.json ${FILE_PATH}/tunnel.yml
}
cleanup_oldfiles
wait

argo_configure() {
  if [[ -z $ARGO_AUTH || -z $ARGO_DOMAIN ]]; then
    echo -e "\e[1;32mARGO_DOMAIN or ARGO_AUTH variable is empty, use quick tunnels\e[0m"
    return
  fi

  if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    echo $ARGO_AUTH > ${FILE_PATH}/tunnel.json
    cat > ${FILE_PATH}/tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$ARGO_AUTH")
credentials-file: ${FILE_PATH}/tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$ARGO_PORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
  else
    echo -e "\e[1;32mARGO_AUTH mismatch TunnelSecret,use token connect to tunnel\e[0m"
  fi
}
argo_configure
wait

generate_config() {
  cat > ${FILE_PATH}/config.json << EOF
{
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": [
    {
      "port": $ARGO_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}", "flow": "xtls-rprx-vision" }],
        "decryption": "none",
        "fallbacks": [
          { "dest": 3001 }, { "path": "/vless", "dest": 3002 },
          { "path": "/vmess", "dest": 3003 }, { "path": "/trojan", "dest": 3004 }
        ]
      },
      "streamSettings": { "network": "tcp" }
    },
    {
      "port": 3001, "listen": "127.0.0.1", "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}" }], "decryption": "none" },
      "streamSettings": { "network": "ws", "security": "none" }
    },
    {
      "port": 3002, "listen": "127.0.0.1", "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}", "level": 0 }], "decryption": "none" },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vless" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false }
    },
    {
      "port": 3003, "listen": "127.0.0.1", "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "alterId": 0 }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false }
    },
    {
      "port": 3004, "listen": "127.0.0.1", "protocol": "trojan",
      "settings": { "clients": [{ "password": "${UUID}" }] },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/trojan" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false }
    }
  ],
  "dns": { "servers": ["https+local://8.8.8.8/dns-query"] },
  "outbounds": [
    { "protocol": "freedom" },
    {
      "tag": "WARP", "protocol": "wireguard",
      "settings": {
        "secretKey": "YFYOAdbw1bKTHlNNi+aEjBM3BO7unuFC5rOkMRAz9XY=",
        "address": ["172.16.0.2/32", "2606:4700:110:8a36:df92:102a:9602:fa18/128"],
        "peers": [{ "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "allowedIPs": ["0.0.0.0/0", "::/0"], "endpoint": "162.159.193.10:2408" }],
        "reserved": [78, 135, 76], "mtu": 1280
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [{ "type": "field", "domain": ["domain:openai.com", "domain:ai.com"], "outboundTag": "WARP" }]
  }
}
EOF
}
generate_config
wait

set_download_url() {
  local program_name="$1"
  local default_url="$2"
  local x64_url="$3"

  if [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "amd64" ] || [ "$(uname -m)" = "x64" ]; then
    download_url="$x64_url"
  else
    download_url="$default_url"
  fi
}

download_program() {
  local program_name="$1"
  local default_url="$2"
  local x64_url="$3"

  set_download_url "$program_name" "$default_url" "$x64_url"

  if [ ! -f "$program_name" ]; then
    if [ -n "$download_url" ]; then
      curl -sSL -C - "$download_url" -o "$program_name" > /dev/null 2>&1
      if [ $? -eq 33 ]; then
        echo "Resuming download $program_name..."
        curl -sSL "$download_url" -o "$program_name" > /dev/null 2>&1
      fi
      if [ $? -eq 0 ]; then
        echo -e "\e[1;32mDownloading $program_name\e[0m"
      else
        echo -e "\e[1;35mFailed to download $program_name\e[0m"
      fi
    else
      echo -e "\e[1;32mSkipping download $program_name\e[0m"
    fi
  else
    echo -e "\e[1;32m$program_name already exists, skipping download\e[0m"
  fi
}

download_program "${FILE_PATH}/npm" "https://github.com/eoovve/test/releases/download/ARM/swith" "https://github.com/eooce/test/releases/download/bulid/swith"
wait

download_program "${FILE_PATH}/web" "https://github.com/eoovve/test/releases/download/ARM/web" "https://github.com/eooce/test/releases/download/123/web"
wait

download_program "${FILE_PATH}/bot" "https://github.com/eooce/test/releases/download/arm64/bot13" "https://github.com/eooce/test/releases/download/amd64/bot13"
wait

run() {
  if [ -e "${FILE_PATH}/npm" ]; then
    chmod 777 "${FILE_PATH}/npm"
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    if [[ "${tlsPorts[*]}" =~ "${NEZHA_PORT}" ]]; then
      NEZHA_TLS="--tls"
    else
      NEZHA_TLS=""
    fi
    if [ -n "$NEZHA_SERVER" ] && [ -n "$NEZHA_PORT" ] && [ -n "$NEZHA_KEY" ]; then
        nohup ${FILE_PATH}/npm -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} >/dev/null 2>&1 &
		    sleep 2
        pgrep -x "npm" > /dev/null && echo -e "\e[1;32mnpm is running\e[0m" || { echo -e "\e[1;35mnpm is not running, restarting...\e[0m"; pkill -x "npm" && nohup "${FILE_PATH}/npm" -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} >/dev/null 2>&1 & sleep 2; echo -e "\e[1;32mnpm restarted\e[0m"; }
    else
        echo -e "\e[1;35mNEZHA variable is empty,skiping runing\e[0m"
    fi
  fi

  if [ -e "${FILE_PATH}/web" ]; then
    chmod 777 "${FILE_PATH}/web"
    nohup ${FILE_PATH}/web -c ${FILE_PATH}/config.json >/dev/null 2>&1 &
	  sleep 2
    pgrep -x "web" > /dev/null && echo -e "\e[1;32mweb is running\e[0m" || { echo -e "\e[1;35mweb is not running, restarting...\e[0m"; pkill -x "web" && nohup "${FILE_PATH}/web" -c ${FILE_PATH}/config.json >/dev/null 2>&1 & sleep 2; echo -e "\e[1;32mweb restarted\e[0m"; }
  fi

  if [ -e "${FILE_PATH}/bot" ]; then
    chmod 777 "${FILE_PATH}/bot"
    if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
      args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
    elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
      args="tunnel --edge-ip-version auto --config ${FILE_PATH}/tunnel.yml run"
    else
      args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ${FILE_PATH}/boot.log --loglevel info --url http://localhost:$ARGO_PORT"
    fi
    nohup ${FILE_PATH}/bot $args >/dev/null 2>&1 &
    sleep 2
    pgrep -x "bot" > /dev/null && echo -e "\e[1;32mbot is running\e[0m" || { echo -e "\e[1;35mbot is not running, restarting...\e[0m"; pkill -x "bot" && nohup "${FILE_PATH}/bot" $args >/dev/null 2>&1 & sleep 2; echo -e "\e[1;32mbot restarted\e[0m"; }
  fi
} 
run
sleep 3

function get_argodomain() {
  if [[ -n $ARGO_AUTH ]]; then
    echo "$ARGO_DOMAIN"
  else
    grep -o "https://.*trycloudflare\.com" "${FILE_PATH}/boot.log" | sed 's@https://@@' | awk -F/ '{print $1}'
  fi
}

generate_links() {
  argodomain=$(get_argodomain)
  echo -e "\e[1;32mArgodomain:\e[1;35m${argodomain}\e[0m"
  sleep 2

  isp=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
  sleep 2

  VMESS="{ \"v\": \"2\", \"ps\": \"${NAME}-${isp}\", \"add\": \"${CFIP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${argodomain}\", \"path\": \"/vmess?ed=2048\", \"tls\": \"tls\", \"sni\": \"${argodomain}\", \"alpn\": \"\" }"

  cat > ${FILE_PATH}/list.txt <<EOF
vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argodomain}&type=ws&host=${argodomain}&path=%2Fvless?ed=2048#${NAME}-${isp}

vmess://$(echo "$VMESS" | base64 -w0)

trojan://${UUID}@${CFIP}:${CFPORT}?security=tls&sni=${argodomain}&type=ws&host=${argodomain}&path=%2Ftrojan?ed=2048#${NAME}-${isp}
EOF

  base64 -w0 ${FILE_PATH}/list.txt > ${FILE_PATH}/sub.txt
  cat ${FILE_PATH}/sub.txt
  echo -e "\n\e[1;32m${FILE_PATH}/sub.txt saved successfully\e[0m"
  sleep 5  
  rm -rf ${FILE_PATH}/list.txt ${FILE_PATH}/boot.log ${FILE_PATH}/config.json ${FILE_PATH}/tunnel.json ${FILE_PATH}/tunnel.yml ${FILE_PATH}/sub.txt ${FILE_PATH}/npm ${FILE_PATH}/web ${FILE_PATH}/bot
}
generate_links
echo -e "\e[1;96mRunning done!\e[0m"
echo -e "\e[1;96mThank you for using this script,enjoy!\e[0m"
sleep 15
clear


tail -f /dev/null
