#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  ECLIPSE VPN — Полный установщик v2.0
#  Всё в одном файле. Запуск: sudo bash install.sh
# ═══════════════════════════════════════════════════════════════════════

# Осознанно БЕЗ set -e — все ошибки обрабатываем вручную
set -uo pipefail

# ── Цвета ──────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; DIM='\033[2m'; NC='\033[0m'

INSTALL_DIR="/opt/eclipse"
LOG="/tmp/eclipse_install.log"
ERRORS=()
STEP=0
> "$LOG"

# ── Утилиты ──────────────────────────────────────────────────────────
step() {
  STEP=$((STEP+1))
  echo ""
  echo -e "${B}${C}╔═══════════════════════════════════════════════════╗${NC}"
  printf  "${B}${C}║  ШАГ %d: %-43s║\n${NC}" "$STEP" "$*"
  echo -e "${B}${C}╚═══════════════════════════════════════════════════╝${NC}"
}
ok()   { echo -e "  ${G}✔${NC}  $*"; }
inf()  { echo -e "  ${C}→${NC}  $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; ERRORS+=("$*"); }
die()  {
  echo ""
  echo -e "${R}${B}╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${R}${B}║  ОШИБКА — УСТАНОВКА ПРЕРВАНА                      ║${NC}"
  echo -e "${R}${B}╚═══════════════════════════════════════════════════╝${NC}"
  echo -e "  ${R}$*${NC}"
  echo ""
  echo -e "  ${DIM}Полный лог: ${LOG}${NC}"
  echo -e "  ${DIM}Последние строки:${NC}"
  tail -30 "$LOG" 2>/dev/null | sed 's/^/    /'
  exit 1
}

run_spin() {
  local msg="$1"; shift
  local spins='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  "$@" >>"$LOG" 2>&1 &
  local pid=$!
  tput civis 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${C}${spins:$((i%${#spins})):1}${NC}  ${DIM}%-55s${NC}" "$msg…"
    i=$((i+1)); sleep 0.1
  done
  tput cnorm 2>/dev/null || true
  if wait "$pid"; then
    printf "\r  ${G}✔${NC}  %-55s\n" "$msg"
  else
    printf "\r  ${R}✗${NC}  %-55s\n" "$msg"
    echo -e "\n  ${R}Ошибка при: $*${NC}"
    echo -e "  ${DIM}Последние строки лога:${NC}"
    tail -25 "$LOG" | sed 's/^/      /'
    die "Не удалось: $msg"
  fi
}

# ── Баннер ───────────────────────────────────────────────────────────
echo -e "${C}${B}"
cat << 'BANNER'

  ███████╗ ██████╗██╗     ██╗██████╗ ███████╗███████╗
  ██╔════╝██╔════╝██║     ██║██╔══██╗██╔════╝██╔════╝
  █████╗  ██║     ██║     ██║██████╔╝███████╗█████╗
  ██╔══╝  ██║     ██║     ██║██╔═══╝ ╚════██║██╔══╝
  ███████╗╚██████╗███████╗██║██║     ███████║███████╗
  ╚══════╝ ╚═════╝╚══════╝╚═╝╚═╝     ╚══════╝╚══════╝
           ПОЛНЫЙ УСТАНОВЩИК v2.0

BANNER
echo -e "${NC}"

# ════════════════════════════════════════════════════════════════════
step "ОЧИСТКА ПРЕДЫДУЩЕЙ УСТАНОВКИ"

inf "Останавливаем старые контейнеры Eclipse/Eclips…"
for dir in /opt/eclipse /opt/eclips ~/eclipse ~/eclips; do
  if [[ -f "${dir}/docker-compose.yml" ]]; then
    inf "Найден стек в ${dir} — останавливаем…"
    (cd "${dir}" && docker compose down --remove-orphans 2>/dev/null) || true
    ok "Стек в ${dir} остановлен"
  fi
done

# Удаляем контейнеры по имени на случай если compose уже нет
for c in eclipse_xray eclipse_backend eclipse_nginx eclipse_xray eclipse_backend eclipse_nginx; do
  if docker inspect "$c" &>/dev/null 2>&1; then
    docker rm -f "$c" >>$LOG 2>&1 || true
    ok "Удалён контейнер: $c"
  fi
done

# Чистим старые директории
for dir in /opt/eclipse /opt/eclips; do
  if [[ -d "$dir" ]]; then
    rm -rf "$dir"
    ok "Удалена директория: $dir"
  fi
done

ok "Очистка завершена"

# ════════════════════════════════════════════════════════════════════
step "ПРОВЕРКА СИСТЕМЫ"

[[ $EUID -ne 0 ]] && die "Запустите от root:\n  sudo bash install.sh"

source /etc/os-release 2>/dev/null || true
ok "ОС: ${PRETTY_NAME:-Unknown}"
ok "Архитектура: $(uname -m)"
ok "Лог установки: ${LOG}"

# ════════════════════════════════════════════════════════════════════
step "ВВОД ПАРАМЕТРОВ"

inf "Определяем внешний IP…"
SERVER_IP=""
for url in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
  _ip=$(curl -s --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]') || true
  [[ "$_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { SERVER_IP="$_ip"; break; }
done
[[ -z "$SERVER_IP" ]] && SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || true
[[ -z "$SERVER_IP" ]] && SERVER_IP="0.0.0.0"
ok "Определён IP: ${B}${SERVER_IP}${NC}"

echo ""
echo -ne "  ${C}?${NC}  Введите IP или домен сервера [${SERVER_IP}]: "
read -r _inp
SERVER_IP="${_inp:-$SERVER_IP}"
ok "Используем: ${SERVER_IP}"

echo ""
while true; do
  echo -ne "  ${C}?${NC}  Пароль для веб-интерфейса (мин. 8 символов): "
  read -rs PASS1; echo ""
  if [[ ${#PASS1} -lt 8 ]]; then
    echo -e "  ${R}✗  Слишком короткий — минимум 8 символов${NC}"; continue
  fi
  echo -ne "  ${C}?${NC}  Повторите пароль: "
  read -rs PASS2; echo ""
  [[ "$PASS1" == "$PASS2" ]] && { UI_PASSWORD="$PASS1"; ok "Пароль принят"; break; }
  echo -e "  ${R}✗  Пароли не совпадают${NC}"
done

# ════════════════════════════════════════════════════════════════════
step "УСТАНОВКА ПАКЕТОВ"

run_spin "Обновление apt" apt-get update -qq
run_spin "Базовые пакеты" apt-get install -y -qq \
  curl wget git unzip ufw ca-certificates gnupg lsb-release software-properties-common

# ════════════════════════════════════════════════════════════════════
step "УСТАНОВКА DOCKER"

if command -v docker &>/dev/null; then
  ok "Docker уже установлен: $(docker --version | awk '{print $3}' | tr -d ',')"
else
  run_spin "GPG-ключ Docker" bash -c '
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg'

  run_spin "Репозиторий Docker" bash -c '
    source /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq'

  run_spin "Docker CE + Compose" \
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

  systemctl enable docker >>$LOG 2>&1 || true
  systemctl start  docker >>$LOG 2>&1 || true
  ok "Docker установлен"
fi

docker compose version >>$LOG 2>&1 || apt-get install -y -qq docker-compose-plugin >>$LOG 2>&1 || true
ok "Docker Compose: v2 ✔"

# ════════════════════════════════════════════════════════════════════
step "ГЕНЕРАЦИЯ X25519 КЛЮЧЕЙ"

XRAY_BIN=""
for c in xray /usr/local/bin/xray /usr/bin/xray; do
  command -v "$c" &>/dev/null && { XRAY_BIN="$c"; break; }
done

if [[ -z "$XRAY_BIN" ]]; then
  ARCH=$(uname -m)
  case "$ARCH" in aarch64|arm64) XA="arm64-v8a";; *) XA="64";; esac

  XVER=$(curl -s --max-time 10 https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null \
    | grep '"tag_name"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/' || echo "v24.9.30")
  [[ "$XVER" =~ ^v[0-9] ]] || XVER="v24.9.30"
  inf "Xray ${XVER} для linux-${XA}"

  run_spin "Скачивание Xray ${XVER}" \
    wget -q "https://github.com/XTLS/Xray-core/releases/download/${XVER}/Xray-linux-${XA}.zip" \
    -O /tmp/xray.zip

  run_spin "Распаковка Xray" bash -c '
    unzip -qo /tmp/xray.zip xray -d /usr/local/bin/
    chmod +x /usr/local/bin/xray
    rm -f /tmp/xray.zip'

  XRAY_BIN="/usr/local/bin/xray"
fi
ok "Xray binary: ${XRAY_BIN}"

# Генерируем ключи — результат в переменную напрямую
echo -n "  ${C}→${NC}  Генерация X25519 ключей… "
KEY_RAW=$("$XRAY_BIN" x25519 2>>$LOG)
RET=$?
if [[ $RET -ne 0 || -z "$KEY_RAW" ]]; then
  echo -e "${R}ОШИБКА (rc=$RET)${NC}"
  die "xray x25519 не вернул результат. Лог: $LOG"
fi
echo -e "${G}OK${NC}"
echo "xray x25519 raw: $KEY_RAW" >>$LOG

# Парсим — поддержка всех форматов всех версий xray
PRIVATE_KEY=$(echo "$KEY_RAW" | grep -i "private" | grep -oE '[A-Za-z0-9_/+=\-]{40,}' | head -1 || true)
PUBLIC_KEY=$(echo  "$KEY_RAW" | grep -i "public"  | grep -oE '[A-Za-z0-9_/+=\-]{40,}' | head -1 || true)
# Fallback: просто первое длинное слово в каждой строке
[[ -z "$PRIVATE_KEY" ]] && PRIVATE_KEY=$(echo "$KEY_RAW" | awk 'NR==1{for(i=NF;i>=1;i--) if(length($i)>20){print $i; exit}}')
[[ -z "$PUBLIC_KEY"  ]] && PUBLIC_KEY=$(echo  "$KEY_RAW" | awk 'NR==2{for(i=NF;i>=1;i--) if(length($i)>20){print $i; exit}}')

[[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]] && die "Не удалось распарсить ключи.\nВывод:\n$KEY_RAW"

ok "Private Key: ${B}${PRIVATE_KEY:0:16}…${NC}"
ok "Public Key:  ${B}${PUBLIC_KEY}${NC}"

# ════════════════════════════════════════════════════════════════════
step "НАСТРОЙКА FIREWALL (UFW)"

ufw --force reset          >>$LOG 2>&1 || true
ufw default deny incoming  >>$LOG 2>&1 || true
ufw default allow outgoing >>$LOG 2>&1 || true
for p in 22 80 443 8080 8443; do
  ufw allow ${p}/tcp >>$LOG 2>&1 || true
  ok "Открыт порт ${p}/tcp"
done
ufw --force enable >>$LOG 2>&1 || true
ok "UFW включён"

# ════════════════════════════════════════════════════════════════════
step "СОЗДАНИЕ ФАЙЛОВ ПРОЕКТА"

mkdir -p "${INSTALL_DIR}"/{backend,frontend,nginx,data,xray_config,xray_logs}
inf "Директория: ${INSTALL_DIR}"

# Распаковываем все файлы из встроенных base64-переменных
decode_file() {
  local b64="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  echo "$b64" | base64 -d > "$dst" || die "Не удалось декодировать: $dst"
  ok "Создан: $dst"
}

cat > "${INSTALL_DIR}/docker-compose.yml" << 'DCEOF'
version: "3.9"

networks:
  eclipse_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

services:
  xray:
    image: teddysun/xray:latest
    container_name: eclipse_xray
    restart: unless-stopped
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    security_opt: [no-new-privileges:true]
    ports:
      - "443:443/tcp"
      - "8443:8443/tcp"
    volumes:
      - ./xray_config:/etc/xray
      - ./xray_logs:/var/log/xray
    networks:
      eclipse_net:
        ipv4_address: 172.20.0.2
    environment:
      - XRAY_LOCATION_CONFIG=/etc/xray
    ulimits:
      nofile: {soft: 65536, hard: 65536}

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: eclipse_backend
    restart: unless-stopped
    depends_on: [xray]
    ports:
      - "8080:8080"
    volumes:
      - ./xray_config:/etc/xray
      - ./xray_logs:/var/log/xray
      - ./data:/app/data
    networks:
      eclipse_net:
        ipv4_address: 172.20.0.3
    environment:
      - ECLIPSE_PASSWORD=${ECLIPSE_PASSWORD}
      - XRAY_CONFIG_PATH=/etc/xray/config.json
      - XRAY_LOG_PATH=/var/log/xray
      - SERVER_IP=${SERVER_IP}
      - PRIVATE_KEY=${PRIVATE_KEY}
      - PUBLIC_KEY=${PUBLIC_KEY}
      - DATA_PATH=/app/data
      - PYTHONUNBUFFERED=1
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  nginx:
    image: nginx:alpine
    container_name: eclipse_nginx
    restart: unless-stopped
    depends_on: [backend]
    ports:
      - "80:80"
    volumes:
      - ./frontend:/usr/share/nginx/html:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      eclipse_net:
        ipv4_address: 172.20.0.4
DCEOF
ok "Создан: ${INSTALL_DIR}/docker-compose.yml" 
decode_file "IiIiCkVjbGlwcyBWUE4g4oCUIEZhc3RBUEkgQmFja2VuZApYcmF5LWNvcmUgY29uZmlnIG1hbmFnZXIsIERQSSBtb25pdG9yLCBrZXkgcm90YXRpb24sIFZMRVNTIGxpbmsgZ2VuZXJhdG9yCiIiIgoKaW1wb3J0IGFzeW5jaW8KaW1wb3J0IGJhc2U2NAppbXBvcnQgaGFzaGxpYgppbXBvcnQgaG1hYwppbXBvcnQganNvbgppbXBvcnQgbG9nZ2luZwppbXBvcnQgb3MKaW1wb3J0IHJhbmRvbQppbXBvcnQgcmUKaW1wb3J0IHNlY3JldHMKaW1wb3J0IHN0cmluZwppbXBvcnQgc3VicHJvY2VzcwppbXBvcnQgdGltZQppbXBvcnQgdXVpZApmcm9tIGNvbnRleHRsaWIgaW1wb3J0IGFzeW5jY29udGV4dG1hbmFnZXIKZnJvbSBkYXRldGltZSBpbXBvcnQgZGF0ZXRpbWUsIHRpbWVkZWx0YQpmcm9tIHBhdGhsaWIgaW1wb3J0IFBhdGgKZnJvbSB0eXBpbmcgaW1wb3J0IEFueSwgT3B0aW9uYWwKCmltcG9ydCBodHRweAppbXBvcnQgcHN1dGlsCmltcG9ydCBxcmNvZGUKaW1wb3J0IHFyY29kZS5pbWFnZS5zdmcKZnJvbSBhcHNjaGVkdWxlci5zY2hlZHVsZXJzLmFzeW5jaW8gaW1wb3J0IEFzeW5jSU9TY2hlZHVsZXIKZnJvbSBmYXN0YXBpIGltcG9ydCBEZXBlbmRzLCBGYXN0QVBJLCBIVFRQRXhjZXB0aW9uLCBSZXF1ZXN0LCBzdGF0dXMKZnJvbSBmYXN0YXBpLm1pZGRsZXdhcmUuY29ycyBpbXBvcnQgQ09SU01pZGRsZXdhcmUKZnJvbSBmYXN0YXBpLnJlc3BvbnNlcyBpbXBvcnQgSlNPTlJlc3BvbnNlLCBTdHJlYW1pbmdSZXNwb25zZQpmcm9tIGZhc3RhcGkuc2VjdXJpdHkgaW1wb3J0IEhUVFBCYXNpYywgSFRUUEJhc2ljQ3JlZGVudGlhbHMKZnJvbSBpbyBpbXBvcnQgQnl0ZXNJTwpmcm9tIHB5ZGFudGljIGltcG9ydCBCYXNlTW9kZWwKCiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiMgQ29uZmlnIC8gRW52CiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACgpsb2dnaW5nLmJhc2ljQ29uZmlnKGxldmVsPWxvZ2dpbmcuSU5GTywgZm9ybWF0PSIlKGFzY3RpbWUpcyBbJShsZXZlbG5hbWUpc10gJShtZXNzYWdlKXMiKQpsb2cgPSBsb2dnaW5nLmdldExvZ2dlcigiZWNsaXBzZSIpCgpFQ0xJUFNfUEFTU1dPUkQgID0gb3MuZ2V0ZW52KCJFQ0xJUFNfUEFTU1dPUkQiLCAiY2hhbmdlbWVfc3Ryb25nX3Bhc3N3b3JkIikKWFJBWV9DT05GSUdfUEFUSCA9IFBhdGgob3MuZ2V0ZW52KCJYUkFZX0NPTkZJR19QQVRIIiwgIi9ldGMveHJheS9jb25maWcuanNvbiIpKQpYUkFZX0xPR19QQVRIICAgID0gUGF0aChvcy5nZXRlbnYoIlhSQVlfTE9HX1BBVEgiLCAiL3Zhci9sb2cveHJheSIpKQpTRVJWRVJfSVAgICAgICAgID0gb3MuZ2V0ZW52KCJTRVJWRVJfSVAiLCAiMC4wLjAuMCIpClBSSVZBVEVfS0VZICAgICAgPSBvcy5nZXRlbnYoIlBSSVZBVEVfS0VZIiwgIiIpClBVQkxJQ19LRVkgICAgICAgPSBvcy5nZXRlbnYoIlBVQkxJQ19LRVkiLCAiIikKREFUQV9QQVRIICAgICAgICA9IFBhdGgob3MuZ2V0ZW52KCJEQVRBX1BBVEgiLCAiL2FwcC9kYXRhIikpCkRBVEFfUEFUSC5ta2RpcihwYXJlbnRzPVRydWUsIGV4aXN0X29rPVRydWUpCgpTVEFURV9GSUxFID0gREFUQV9QQVRIIC8gInN0YXRlLmpzb24iCgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIFNOSSBwb29sIOKAlCByb3RhdGVkIGV2ZXJ5IDI0aAojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoKU05JX1BPT0wgPSBbCiAgICAiaWNsb3VkLmNvbSIsCiAgICAiZ2F0ZXdheS5pY2xvdWQuY29tIiwKICAgICJjZG4uYXBwbGUtY2xvdWRraXQuY29tIiwKICAgICJ3d3cuYXBwbGUuY29tIiwKICAgICJhcHBsZWlkLmFwcGxlLmNvbSIsCiAgICAiYXBpLnNiZXJiYW5rLnJ1IiwKICAgICJvbmxpbmUuc2JlcmJhbmsucnUiLAogICAgImdvc3VzbHVnaS5ydSIsCiAgICAibGsuZ29zdXNsdWdpLnJ1IiwKICAgICJlc2lhLmdvc3VzbHVnaS5ydSIsCl0KCkRFU1RfU0lURVMgPSB7CiAgICAiaWNsb3VkLmNvbSI6NDQzLAogICAgImdhdGV3YXkuaWNsb3VkLmNvbSI6NDQzLAogICAgInd3dy5hcHBsZS5jb20iOjQ0MywKICAgICJnb3N1c2x1Z2kucnUiOjQ0MywKfQoKQkxPQ0tFRF9TSVRFU19DSEVDSyA9IFsKICAgICJodHRwczovL3d3dy55b3V0dWJlLmNvbSIsCiAgICAiaHR0cHM6Ly90d2l0dGVyLmNvbSIsCiAgICAiaHR0cHM6Ly9mYWNlYm9vay5jb20iLApdCkRJUkVDVF9TSVRFU19DSEVDSyA9IFsKICAgICJodHRwczovL3d3dy5nb29nbGUuY29tIiwKICAgICJodHRwczovL2Nsb3VkZmxhcmUuY29tIiwKICAgICJodHRwczovLzEuMS4xLjEiLApdCgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIFN0YXRlIGhlbHBlcnMKIyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKCmRlZiBsb2FkX3N0YXRlKCkgLT4gZGljdDoKICAgIGlmIFNUQVRFX0ZJTEUuZXhpc3RzKCk6CiAgICAgICAgdHJ5OgogICAgICAgICAgICByZXR1cm4ganNvbi5sb2FkcyhTVEFURV9GSUxFLnJlYWRfdGV4dCgpKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgICAgIHBhc3MKICAgIHJldHVybiB7fQoKCmRlZiBzYXZlX3N0YXRlKGRhdGE6IGRpY3QpOgogICAgU1RBVEVfRklMRS53cml0ZV90ZXh0KGpzb24uZHVtcHMoZGF0YSwgaW5kZW50PTIpKQoKCmRlZiBnZW5fc2hvcnRfaWQobGVuZ3RoOiBpbnQgPSA4KSAtPiBzdHI6CiAgICAiIiJIZXggc2hvcnQtaWQgcmVxdWlyZWQgYnkgUmVhbGl0eS4iIiIKICAgIHJldHVybiBzZWNyZXRzLnRva2VuX2hleChsZW5ndGggLy8gMikKCgpkZWYgZ2VuX3V1aWQoKSAtPiBzdHI6CiAgICByZXR1cm4gc3RyKHV1aWQudXVpZDQoKSkKCgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIFhyYXkgY29uZmlnIGdlbmVyYXRvcgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoKZGVmIGJ1aWxkX3hyYXlfY29uZmlnKHN0YXRlOiBkaWN0KSAtPiBkaWN0OgogICAgIiIiR2VuZXJhdGUgZnVsbCBYcmF5IGNvbmZpZy5qc29uIHdpdGggVkxFU1MrUmVhbGl0eSAoVENQKSBhbmQgVkxFU1MrUmVhbGl0eSAoZ1JQQykuIiIiCgogICAgc25pICAgICAgID0gc3RhdGUuZ2V0KCJzbmkiLCByYW5kb20uY2hvaWNlKFNOSV9QT09MKSkKICAgIHNob3J0X2lkICA9IHN0YXRlLmdldCgic2hvcnRfaWQiLCBnZW5fc2hvcnRfaWQoKSkKICAgIHVzZXJfaWQgICA9IHN0YXRlLmdldCgidXNlcl9pZCIsIGdlbl91dWlkKCkpCiAgICBwcml2X2tleSAgPSBQUklWQVRFX0tFWSBvciBzdGF0ZS5nZXQoInByaXZhdGVfa2V5IiwgIiIpCiAgICBwdWJfa2V5ICAgPSBQVUJMSUNfS0VZICBvciBzdGF0ZS5nZXQoInB1YmxpY19rZXkiLCAiIikKCiAgICBkZXN0X2hvc3QsIGRlc3RfcG9ydCA9IHNuaSwgREVTVF9TSVRFUy5nZXQoc25pLCA0NDMpCgogICAgY29uZmlnID0gewogICAgICAgICJsb2ciOiB7CiAgICAgICAgICAgICJsb2dsZXZlbCI6ICJ3YXJuaW5nIiwKICAgICAgICAgICAgImFjY2VzcyI6IHN0cihYUkFZX0xPR19QQVRIIC8gImFjY2Vzcy5sb2ciKSwKICAgICAgICAgICAgImVycm9yIjogIHN0cihYUkFZX0xPR19QQVRIIC8gImVycm9yLmxvZyIpLAogICAgICAgIH0sCiAgICAgICAgImluYm91bmRzIjogWwogICAgICAgICAgICAjIOKUgOKUgCBWTEVTUyArIFJlYWxpdHkg4oCUIFRDUCBwb3J0IDQ0MyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgImxpc3RlbiI6ICIwLjAuMC4wIiwKICAgICAgICAgICAgICAgICJwb3J0IjogNDQzLAogICAgICAgICAgICAgICAgInByb3RvY29sIjogInZsZXNzIiwKICAgICAgICAgICAgICAgICJzZXR0aW5ncyI6IHsKICAgICAgICAgICAgICAgICAgICAiY2xpZW50cyI6IFsKICAgICAgICAgICAgICAgICAgICAgICAgeyJpZCI6IHVzZXJfaWQsICJmbG93IjogInh0bHMtcnByeC12aXNpb24ifQogICAgICAgICAgICAgICAgICAgIF0sCiAgICAgICAgICAgICAgICAgICAgImRlY3J5cHRpb24iOiAibm9uZSIsCiAgICAgICAgICAgICAgICB9LAogICAgICAgICAgICAgICAgInN0cmVhbVNldHRpbmdzIjogewogICAgICAgICAgICAgICAgICAgICJuZXR3b3JrIjogInRjcCIsCiAgICAgICAgICAgICAgICAgICAgInNlY3VyaXR5IjogInJlYWxpdHkiLAogICAgICAgICAgICAgICAgICAgICJyZWFsaXR5U2V0dGluZ3MiOiB7CiAgICAgICAgICAgICAgICAgICAgICAgICJzaG93IjogRmFsc2UsCiAgICAgICAgICAgICAgICAgICAgICAgICJkZXN0IjogZiJ7ZGVzdF9ob3N0fTp7ZGVzdF9wb3J0fSIsCiAgICAgICAgICAgICAgICAgICAgICAgICJ4dmVyIjogMCwKICAgICAgICAgICAgICAgICAgICAgICAgInNlcnZlck5hbWVzIjogW3NuaSwgZiJ3d3cue3NuaX0iIGlmIG5vdCBzbmkuc3RhcnRzd2l0aCgid3d3LiIpIGVsc2Ugc25pXSwKICAgICAgICAgICAgICAgICAgICAgICAgInByaXZhdGVLZXkiOiBwcml2X2tleSwKICAgICAgICAgICAgICAgICAgICAgICAgInNob3J0SWRzIjogW3Nob3J0X2lkXSwKICAgICAgICAgICAgICAgICAgICB9LAogICAgICAgICAgICAgICAgICAgICJ0Y3BTZXR0aW5ncyI6IHsKICAgICAgICAgICAgICAgICAgICAgICAgImhlYWRlciI6IHsidHlwZSI6ICJub25lIn0sCiAgICAgICAgICAgICAgICAgICAgfSwKICAgICAgICAgICAgICAgIH0sCiAgICAgICAgICAgICAgICAic25pZmZpbmciOiB7CiAgICAgICAgICAgICAgICAgICAgImVuYWJsZWQiOiBUcnVlLAogICAgICAgICAgICAgICAgICAgICJkZXN0T3ZlcnJpZGUiOiBbImh0dHAiLCAidGxzIiwgInF1aWMiXSwKICAgICAgICAgICAgICAgIH0sCiAgICAgICAgICAgIH0sCiAgICAgICAgICAgICMg4pSA4pSAIFZMRVNTICsgUmVhbGl0eSDigJQgZ1JQQyBwb3J0IDg0NDMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICJsaXN0ZW4iOiAiMC4wLjAuMCIsCiAgICAgICAgICAgICAgICAicG9ydCI6IDg0NDMsCiAgICAgICAgICAgICAgICAicHJvdG9jb2wiOiAidmxlc3MiLAogICAgICAgICAgICAgICAgInNldHRpbmdzIjogewogICAgICAgICAgICAgICAgICAgICJjbGllbnRzIjogWwogICAgICAgICAgICAgICAgICAgICAgICB7ImlkIjogdXNlcl9pZCwgImZsb3ciOiAiIn0KICAgICAgICAgICAgICAgICAgICBdLAogICAgICAgICAgICAgICAgICAgICJkZWNyeXB0aW9uIjogIm5vbmUiLAogICAgICAgICAgICAgICAgfSwKICAgICAgICAgICAgICAgICJzdHJlYW1TZXR0aW5ncyI6IHsKICAgICAgICAgICAgICAgICAgICAibmV0d29yayI6ICJncnBjIiwKICAgICAgICAgICAgICAgICAgICAic2VjdXJpdHkiOiAicmVhbGl0eSIsCiAgICAgICAgICAgICAgICAgICAgInJlYWxpdHlTZXR0aW5ncyI6IHsKICAgICAgICAgICAgICAgICAgICAgICAgInNob3ciOiBGYWxzZSwKICAgICAgICAgICAgICAgICAgICAgICAgImRlc3QiOiBmIntkZXN0X2hvc3R9OntkZXN0X3BvcnR9IiwKICAgICAgICAgICAgICAgICAgICAgICAgInh2ZXIiOiAwLAogICAgICAgICAgICAgICAgICAgICAgICAic2VydmVyTmFtZXMiOiBbc25pXSwKICAgICAgICAgICAgICAgICAgICAgICAgInByaXZhdGVLZXkiOiBwcml2X2tleSwKICAgICAgICAgICAgICAgICAgICAgICAgInNob3J0SWRzIjogW3Nob3J0X2lkXSwKICAgICAgICAgICAgICAgICAgICB9LAogICAgICAgICAgICAgICAgICAgICJncnBjU2V0dGluZ3MiOiB7CiAgICAgICAgICAgICAgICAgICAgICAgICJzZXJ2aWNlTmFtZSI6ICJlY2xpcHNlLWdycGMiLAogICAgICAgICAgICAgICAgICAgICAgICAibXVsdGlNb2RlIjogVHJ1ZSwKICAgICAgICAgICAgICAgICAgICB9LAogICAgICAgICAgICAgICAgfSwKICAgICAgICAgICAgICAgICJzbmlmZmluZyI6IHsKICAgICAgICAgICAgICAgICAgICAiZW5hYmxlZCI6IFRydWUsCiAgICAgICAgICAgICAgICAgICAgImRlc3RPdmVycmlkZSI6IFsiaHR0cCIsICJ0bHMiXSwKICAgICAgICAgICAgICAgIH0sCiAgICAgICAgICAgIH0sCiAgICAgICAgXSwKICAgICAgICAib3V0Ym91bmRzIjogWwogICAgICAgICAgICB7InByb3RvY29sIjogImZyZWVkb20iLCAidGFnIjogImRpcmVjdCJ9LAogICAgICAgICAgICB7InByb3RvY29sIjogImJsYWNraG9sZSIsICJ0YWciOiAiYmxvY2sifSwKICAgICAgICBdLAogICAgICAgICJyb3V0aW5nIjogewogICAgICAgICAgICAiZG9tYWluU3RyYXRlZ3kiOiAiSVBJZk5vbk1hdGNoIiwKICAgICAgICAgICAgInJ1bGVzIjogWwogICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgICJ0eXBlIjogImZpZWxkIiwKICAgICAgICAgICAgICAgICAgICAiaXAiOiBbImdlb2lwOnByaXZhdGUiXSwKICAgICAgICAgICAgICAgICAgICAib3V0Ym91bmRUYWciOiAiYmxvY2siLAogICAgICAgICAgICAgICAgfSwKICAgICAgICAgICAgXSwKICAgICAgICB9LAogICAgICAgICJwb2xpY3kiOiB7CiAgICAgICAgICAgICJsZXZlbHMiOiB7CiAgICAgICAgICAgICAgICAiMCI6IHsKICAgICAgICAgICAgICAgICAgICAiaGFuZHNoYWtlIjogNCwKICAgICAgICAgICAgICAgICAgICAiY29ubklkbGUiOiAzMDAsCiAgICAgICAgICAgICAgICAgICAgInVwbGlua09ubHkiOiA1LAogICAgICAgICAgICAgICAgICAgICJkb3dubGlua09ubHkiOiAzMCwKICAgICAgICAgICAgICAgICAgICAiYnVmZmVyU2l6ZSI6IDQsCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0sCiAgICAgICAgICAgICJzeXN0ZW0iOiB7CiAgICAgICAgICAgICAgICAic3RhdHNJbmJvdW5kVXBsaW5rIjogVHJ1ZSwKICAgICAgICAgICAgICAgICJzdGF0c0luYm91bmREb3dubGluayI6IFRydWUsCiAgICAgICAgICAgIH0sCiAgICAgICAgfSwKICAgICAgICAic3RhdHMiOiB7fSwKICAgIH0KICAgIHJldHVybiBjb25maWcKCgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIFJvdGF0aW9uIGxvZ2ljCiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACgpkZWYgcm90YXRlX2tleXNfYW5kX3NuaShzdGF0ZTogZGljdCkgLT4gZGljdDoKICAgICIiIlBpY2sgbmV3IFNOSSArIFNob3J0SUQuIEtleXMgc3RheSB1bmxlc3MgZXhwbGljaXRseSByZXF1ZXN0ZWQuIiIiCiAgICBzdGF0ZVsic25pIl0gICAgICAgID0gcmFuZG9tLmNob2ljZShTTklfUE9PTCkKICAgIHN0YXRlWyJzaG9ydF9pZCJdICAgPSBnZW5fc2hvcnRfaWQoKQogICAgc3RhdGVbInJvdGF0ZWRfYXQiXSA9IGRhdGV0aW1lLnV0Y25vdygpLmlzb2Zvcm1hdCgpCiAgICByZXR1cm4gc3RhdGUKCgpkZWYgd3JpdGVfeHJheV9jb25maWcoY2ZnOiBkaWN0KToKICAgIFhSQVlfQ09ORklHX1BBVEgucGFyZW50Lm1rZGlyKHBhcmVudHM9VHJ1ZSwgZXhpc3Rfb2s9VHJ1ZSkKICAgIHRtcCA9IFhSQVlfQ09ORklHX1BBVEgud2l0aF9zdWZmaXgoIi50bXAiKQogICAgdG1wLndyaXRlX3RleHQoanNvbi5kdW1wcyhjZmcsIGluZGVudD0yKSkKICAgIHRtcC5yZW5hbWUoWFJBWV9DT05GSUdfUEFUSCkKICAgIGxvZy5pbmZvKCJYcmF5IGNvbmZpZyB3cml0dGVuIOKGkiAlcyIsIFhSQVlfQ09ORklHX1BBVEgpCgoKZGVmIHJlbG9hZF94cmF5KCk6CiAgICAiIiJTZW5kIFNJR1VTUjEgdG8geHJheSBwcm9jZXNzIGZvciBob3QgcmVsb2FkIChubyBkb3dudGltZSkuIiIiCiAgICB0cnk6CiAgICAgICAgcmVzdWx0ID0gc3VicHJvY2Vzcy5ydW4oCiAgICAgICAgICAgIFsicGtpbGwiLCAiLVNJR1VTUjEiLCAieHJheSJdLAogICAgICAgICAgICBjYXB0dXJlX291dHB1dD1UcnVlLCB0aW1lb3V0PTUKICAgICAgICApCiAgICAgICAgbG9nLmluZm8oIlhyYXkgcmVsb2FkIHNpZ25hbCBzZW50IChyYz0lZCkiLCByZXN1bHQucmV0dXJuY29kZSkKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICBsb2cud2FybmluZygiQ291bGQgbm90IHNlbmQgcmVsb2FkIHNpZ25hbDogJXMiLCBlKQoKCiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiMgVkxFU1MgbGluayBidWlsZGVyCiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACgpkZWYgYnVpbGRfdmxlc3NfbGluayhzdGF0ZTogZGljdCwgdHJhbnNwb3J0OiBzdHIgPSAidGNwIikgLT4gc3RyOgogICAgdWlkICAgICAgPSBzdGF0ZS5nZXQoInVzZXJfaWQiLCAiIikKICAgIHNuaSAgICAgID0gc3RhdGUuZ2V0KCJzbmkiLCAiaWNsb3VkLmNvbSIpCiAgICBwdWJfa2V5ICA9IFBVQkxJQ19LRVkgb3Igc3RhdGUuZ2V0KCJwdWJsaWNfa2V5IiwgIiIpCiAgICBzaG9ydF9pZCA9IHN0YXRlLmdldCgic2hvcnRfaWQiLCAiIikKICAgIHNlcnZlciAgID0gU0VSVkVSX0lQCiAgICBmcCAgICAgICA9ICJzYWZhcmkiICAjIHVUTFMgZmluZ2VycHJpbnQKCiAgICBpZiB0cmFuc3BvcnQgPT0gInRjcCI6CiAgICAgICAgcG9ydCAgID0gNDQzCiAgICAgICAgZmxvdyAgID0gInh0bHMtcnByeC12aXNpb24iCiAgICAgICAgcGFyYW1zID0gKAogICAgICAgICAgICBmInR5cGU9dGNwJnNlY3VyaXR5PXJlYWxpdHkiCiAgICAgICAgICAgIGYiJnBiaz17cHViX2tleX0mZnA9e2ZwfSZzbmk9e3NuaX0iCiAgICAgICAgICAgIGYiJnNpZD17c2hvcnRfaWR9JmZsb3c9e2Zsb3d9IgogICAgICAgICkKICAgIGVsc2U6ICAjIGdycGMKICAgICAgICBwb3J0ICAgPSA4NDQzCiAgICAgICAgcGFyYW1zID0gKAogICAgICAgICAgICBmInR5cGU9Z3JwYyZzZWN1cml0eT1yZWFsaXR5IgogICAgICAgICAgICBmIiZwYms9e3B1Yl9rZXl9JmZwPXtmcH0mc25pPXtzbml9IgogICAgICAgICAgICBmIiZzaWQ9e3Nob3J0X2lkfSZzZXJ2aWNlTmFtZT1lY2xpcHNlLWdycGMmbW9kZT1tdWx0aSIKICAgICAgICApCgogICAgdGFnICA9IGYiZWNsaXBzZS17dHJhbnNwb3J0fSIKICAgIGxpbmsgPSBmInZsZXNzOi8ve3VpZH1Ae3NlcnZlcn06e3BvcnR9P3twYXJhbXN9I3t0YWd9IgogICAgcmV0dXJuIGxpbmsKCgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIERQSSBNb25pdG9yCiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACgpkcGlfc2NvcmVfY2FjaGU6IGRpY3QgPSB7InNjb3JlIjogMCwgInVwZGF0ZWRfYXQiOiBOb25lLCAiZGV0YWlscyI6IHt9fQoKCmFzeW5jIGRlZiBtZWFzdXJlX2xhdGVuY3kodXJsOiBzdHIsIHRpbWVvdXQ6IGZsb2F0ID0gNS4wKSAtPiBPcHRpb25hbFtmbG9hdF06CiAgICB0cnk6CiAgICAgICAgc3RhcnQgPSB0aW1lLm1vbm90b25pYygpCiAgICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PXRpbWVvdXQsIGZvbGxvd19yZWRpcmVjdHM9VHJ1ZSkgYXMgY2xpZW50OgogICAgICAgICAgICByZXNwID0gYXdhaXQgY2xpZW50LmdldCh1cmwpCiAgICAgICAgcmV0dXJuIHJvdW5kKCh0aW1lLm1vbm90b25pYygpIC0gc3RhcnQpICogMTAwMCwgMSkgICMgbXMKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIE5vbmUKCgphc3luYyBkZWYgcnVuX2RwaV9tb25pdG9yKCk6CiAgICAiIiIKICAgIE1lYXN1cmVzIGxhdGVuY3kgcmF0aW8gYmV0d2VlbiAnYmxvY2tlZCcgYW5kICdkaXJlY3QnIHNpdGVzLgogICAgU2NvcmUgMC0xMDA6IDAgPSBjbGVhbiwgMTAwID0gaGVhdnkgaW50ZXJmZXJlbmNlLgogICAgIiIiCiAgICBibG9ja2VkX2xhdGVuY2llcywgZGlyZWN0X2xhdGVuY2llcyA9IFtdLCBbXQoKICAgIGZvciB1cmwgaW4gQkxPQ0tFRF9TSVRFU19DSEVDSzoKICAgICAgICBsYXQgPSBhd2FpdCBtZWFzdXJlX2xhdGVuY3kodXJsKQogICAgICAgIGlmIGxhdDoKICAgICAgICAgICAgYmxvY2tlZF9sYXRlbmNpZXMuYXBwZW5kKGxhdCkKCiAgICBmb3IgdXJsIGluIERJUkVDVF9TSVRFU19DSEVDSzoKICAgICAgICBsYXQgPSBhd2FpdCBtZWFzdXJlX2xhdGVuY3kodXJsKQogICAgICAgIGlmIGxhdDoKICAgICAgICAgICAgZGlyZWN0X2xhdGVuY2llcy5hcHBlbmQobGF0KQoKICAgIGF2Z19ibG9ja2VkID0gc3VtKGJsb2NrZWRfbGF0ZW5jaWVzKSAvIGxlbihibG9ja2VkX2xhdGVuY2llcykgaWYgYmxvY2tlZF9sYXRlbmNpZXMgZWxzZSA5OTk5CiAgICBhdmdfZGlyZWN0ICA9IHN1bShkaXJlY3RfbGF0ZW5jaWVzKSAgLyBsZW4oZGlyZWN0X2xhdGVuY2llcykgIGlmIGRpcmVjdF9sYXRlbmNpZXMgIGVsc2UgMQoKICAgICMgVGltZW91dCAvIG5vIHJlc3BvbnNlIGNvdW50cyBhcyBoZWF2eSBibG9ja2luZwogICAgYmxvY2tlZF90aW1lb3V0cyA9IGxlbihCTE9DS0VEX1NJVEVTX0NIRUNLKSAtIGxlbihibG9ja2VkX2xhdGVuY2llcykKCiAgICByYXRpbyA9IGF2Z19ibG9ja2VkIC8gbWF4KGF2Z19kaXJlY3QsIDEpCiAgICBzY29yZSA9IG1pbigxMDAsIGludCgocmF0aW8gLSAxKSAqIDIwKSArIGJsb2NrZWRfdGltZW91dHMgKiAyMCkKICAgIHNjb3JlID0gbWF4KDAsIHNjb3JlKQoKICAgIGRwaV9zY29yZV9jYWNoZS51cGRhdGUoewogICAgICAgICJzY29yZSI6ICAgICAgc2NvcmUsCiAgICAgICAgInVwZGF0ZWRfYXQiOiBkYXRldGltZS51dGNub3coKS5pc29mb3JtYXQoKSwKICAgICAgICAiZGV0YWlscyI6IHsKICAgICAgICAgICAgImF2Z19ibG9ja2VkX21zIjogYXZnX2Jsb2NrZWQsCiAgICAgICAgICAgICJhdmdfZGlyZWN0X21zIjogIGF2Z19kaXJlY3QsCiAgICAgICAgICAgICJibG9ja2VkX3RpbWVvdXRzIjogYmxvY2tlZF90aW1lb3V0cywKICAgICAgICAgICAgImJsb2NrZWRfc2FtcGxlcyI6IGJsb2NrZWRfbGF0ZW5jaWVzLAogICAgICAgICAgICAiZGlyZWN0X3NhbXBsZXMiOiAgZGlyZWN0X2xhdGVuY2llcywKICAgICAgICB9CiAgICB9KQogICAgbG9nLmluZm8oIkRQSSBzY29yZTogJWQgIChibG9ja2VkX2F2Zz0lLjBmbXMgIGRpcmVjdF9hdmc9JS4wZm1zKSIsIHNjb3JlLCBhdmdfYmxvY2tlZCwgYXZnX2RpcmVjdCkKCgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIFNjaGVkdWxlcgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoKc2NoZWR1bGVyID0gQXN5bmNJT1NjaGVkdWxlcigpCgoKYXN5bmMgZGVmIHNjaGVkdWxlZF9yb3RhdGlvbigpOgogICAgbG9nLmluZm8oIuKPsCBTY2hlZHVsZWQgcm90YXRpb24gdHJpZ2dlcmVkIikKICAgIHN0YXRlID0gbG9hZF9zdGF0ZSgpCiAgICBzdGF0ZSA9IHJvdGF0ZV9rZXlzX2FuZF9zbmkoc3RhdGUpCiAgICBjZmcgICA9IGJ1aWxkX3hyYXlfY29uZmlnKHN0YXRlKQogICAgd3JpdGVfeHJheV9jb25maWcoY2ZnKQogICAgcmVsb2FkX3hyYXkoKQogICAgc2F2ZV9zdGF0ZShzdGF0ZSkKICAgIGxvZy5pbmZvKCLinIUgUm90YXRpb24gY29tcGxldGUuIE5ldyBTTkk6ICVzICBTaG9ydElEOiAlcyIsIHN0YXRlWyJzbmkiXSwgc3RhdGVbInNob3J0X2lkIl0pCgoKIyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKIyBBcHAgbGlmZXNwYW4KIyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKCkBhc3luY2NvbnRleHRtYW5hZ2VyCmFzeW5jIGRlZiBsaWZlc3BhbihhcHA6IEZhc3RBUEkpOgogICAgIyBJbml0aWFsaXNlIHN0YXRlIG9uIGZpcnN0IGJvb3QKICAgIHN0YXRlID0gbG9hZF9zdGF0ZSgpCiAgICBpZiBub3Qgc3RhdGUuZ2V0KCJ1c2VyX2lkIik6CiAgICAgICAgc3RhdGVbInVzZXJfaWQiXSAgICA9IGdlbl91dWlkKCkKICAgICAgICBzdGF0ZVsic25pIl0gICAgICAgID0gcmFuZG9tLmNob2ljZShTTklfUE9PTCkKICAgICAgICBzdGF0ZVsic2hvcnRfaWQiXSAgID0gZ2VuX3Nob3J0X2lkKCkKICAgICAgICBzdGF0ZVsicHJpdmF0ZV9rZXkiXSA9IFBSSVZBVEVfS0VZCiAgICAgICAgc3RhdGVbInB1YmxpY19rZXkiXSAgPSBQVUJMSUNfS0VZCiAgICAgICAgc3RhdGVbInJvdGF0ZWRfYXQiXSAgPSBkYXRldGltZS51dGNub3coKS5pc29mb3JtYXQoKQogICAgICAgIHNhdmVfc3RhdGUoc3RhdGUpCgogICAgIyBXcml0ZSBpbml0aWFsIHhyYXkgY29uZmlnCiAgICBjZmcgPSBidWlsZF94cmF5X2NvbmZpZyhzdGF0ZSkKICAgIHdyaXRlX3hyYXlfY29uZmlnKGNmZykKICAgIHJlbG9hZF94cmF5KCkKCiAgICAjIFNjaGVkdWxlIHJvdGF0aW9uIGV2ZXJ5IDI0IGhvdXJzCiAgICBzY2hlZHVsZXIuYWRkX2pvYihzY2hlZHVsZWRfcm90YXRpb24sICJpbnRlcnZhbCIsIGhvdXJzPTI0LCBpZD0icm90YXRpb24iKQogICAgIyBEUEkgY2hlY2sgZXZlcnkgMTAgbWludXRlcwogICAgc2NoZWR1bGVyLmFkZF9qb2IocnVuX2RwaV9tb25pdG9yLCAiaW50ZXJ2YWwiLCBtaW51dGVzPTEwLCBpZD0iZHBpX21vbml0b3IiKQogICAgc2NoZWR1bGVyLnN0YXJ0KCkKCiAgICAjIEluaXRpYWwgRFBJIHByb2JlCiAgICBhc3luY2lvLmNyZWF0ZV90YXNrKHJ1bl9kcGlfbW9uaXRvcigpKQoKICAgIHlpZWxkCgogICAgc2NoZWR1bGVyLnNodXRkb3duKCkKCgojIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAojIEZhc3RBUEkgYXBwCiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACgphcHAgPSBGYXN0QVBJKHRpdGxlPSJFY2xpcHMgVlBOIEFQSSIsIHZlcnNpb249IjEuMC4wIiwgbGlmZXNwYW49bGlmZXNwYW4pCgphcHAuYWRkX21pZGRsZXdhcmUoCiAgICBDT1JTTWlkZGxld2FyZSwKICAgIGFsbG93X29yaWdpbnM9WyIqIl0sCiAgICBhbGxvd19jcmVkZW50aWFscz1UcnVlLAogICAgYWxsb3dfbWV0aG9kcz1bIioiXSwKICAgIGFsbG93X2hlYWRlcnM9WyIqIl0sCikKCnNlY3VyaXR5ID0gSFRUUEJhc2ljKCkKCgpkZWYgdmVyaWZ5X3Bhc3N3b3JkKGNyZWRlbnRpYWxzOiBIVFRQQmFzaWNDcmVkZW50aWFscyA9IERlcGVuZHMoc2VjdXJpdHkpKToKICAgIGNvcnJlY3QgPSBobWFjLmNvbXBhcmVfZGlnZXN0KAogICAgICAgIGNyZWRlbnRpYWxzLnBhc3N3b3JkLmVuY29kZSgpLCBFQ0xJUFNfUEFTU1dPUkQuZW5jb2RlKCkKICAgICkKICAgIGlmIG5vdCAoY3JlZGVudGlhbHMudXNlcm5hbWUgPT0gImVjbGlwc2UiIGFuZCBjb3JyZWN0KToKICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKAogICAgICAgICAgICBzdGF0dXNfY29kZT1zdGF0dXMuSFRUUF80MDFfVU5BVVRIT1JJWkVELAogICAgICAgICAgICBkZXRhaWw9IkludmFsaWQgY3JlZGVudGlhbHMiLAogICAgICAgICAgICBoZWFkZXJzPXsiV1dXLUF1dGhlbnRpY2F0ZSI6ICJCYXNpYyJ9LAogICAgICAgICkKICAgIHJldHVybiBjcmVkZW50aWFscy51c2VybmFtZQoKCiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACiMgUm91dGVzCiMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACgpAYXBwLmdldCgiL2hlYWx0aCIpCmFzeW5jIGRlZiBoZWFsdGgoKToKICAgIHJldHVybiB7InN0YXR1cyI6ICJvayIsICJ0cyI6IGRhdGV0aW1lLnV0Y25vdygpLmlzb2Zvcm1hdCgpfQoKCkBhcHAuZ2V0KCIvYXBpL3N0YXR1cyIsIGRlcGVuZGVuY2llcz1bRGVwZW5kcyh2ZXJpZnlfcGFzc3dvcmQpXSkKYXN5bmMgZGVmIGdldF9zdGF0dXMoKToKICAgIHN0YXRlID0gbG9hZF9zdGF0ZSgpCiAgICB1cHRpbWUgPSBOb25lCiAgICB0cnk6CiAgICAgICAgYm9vdCA9IHBzdXRpbC5ib290X3RpbWUoKQogICAgICAgIHVwdGltZSA9IGludCh0aW1lLnRpbWUoKSAtIGJvb3QpCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHBhc3MKCiAgICByZXR1cm4gewogICAgICAgICJzbmkiOiAgICAgICAgc3RhdGUuZ2V0KCJzbmkiKSwKICAgICAgICAic2hvcnRfaWQiOiAgIHN0YXRlLmdldCgic2hvcnRfaWQiKSwKICAgICAgICAicm90YXRlZF9hdCI6IHN0YXRlLmdldCgicm90YXRlZF9hdCIpLAogICAgICAgICJzZXJ2ZXJfaXAiOiAgU0VSVkVSX0lQLAogICAgICAgICJ1cHRpbWVfc2VjIjogdXB0aW1lLAogICAgICAgICJkcGkiOiAgICAgICAgZHBpX3Njb3JlX2NhY2hlLAogICAgICAgICJwb3J0cyI6IHsidGNwIjogNDQzLCAiZ3JwYyI6IDg0NDN9LAogICAgfQoKCkBhcHAuZ2V0KCIvYXBpL2xpbmtzIiwgZGVwZW5kZW5jaWVzPVtEZXBlbmRzKHZlcmlmeV9wYXNzd29yZCldKQphc3luYyBkZWYgZ2V0X2xpbmtzKCk6CiAgICBzdGF0ZSA9IGxvYWRfc3RhdGUoKQogICAgcmV0dXJuIHsKICAgICAgICAidGNwIjogIGJ1aWxkX3ZsZXNzX2xpbmsoc3RhdGUsICJ0Y3AiKSwKICAgICAgICAiZ3JwYyI6IGJ1aWxkX3ZsZXNzX2xpbmsoc3RhdGUsICJncnBjIiksCiAgICB9CgoKQGFwcC5nZXQoIi9hcGkvcXIve3RyYW5zcG9ydH0iLCBkZXBlbmRlbmNpZXM9W0RlcGVuZHModmVyaWZ5X3Bhc3N3b3JkKV0pCmFzeW5jIGRlZiBnZXRfcXIodHJhbnNwb3J0OiBzdHIgPSAidGNwIik6CiAgICBpZiB0cmFuc3BvcnQgbm90IGluICgidGNwIiwgImdycGMiKToKICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKDQwMCwgInRyYW5zcG9ydCBtdXN0IGJlIHRjcCBvciBncnBjIikKICAgIHN0YXRlID0gbG9hZF9zdGF0ZSgpCiAgICBsaW5rICA9IGJ1aWxkX3ZsZXNzX2xpbmsoc3RhdGUsIHRyYW5zcG9ydCkKCiAgICBpbWcgICA9IHFyY29kZS5tYWtlKGxpbmspCiAgICBidWYgICA9IEJ5dGVzSU8oKQogICAgaW1nLnNhdmUoYnVmLCBmb3JtYXQ9IlBORyIpCiAgICBidWYuc2VlaygwKQogICAgcmV0dXJuIFN0cmVhbWluZ1Jlc3BvbnNlKGJ1ZiwgbWVkaWFfdHlwZT0iaW1hZ2UvcG5nIikKCgpAYXBwLnBvc3QoIi9hcGkvcm90YXRlIiwgZGVwZW5kZW5jaWVzPVtEZXBlbmRzKHZlcmlmeV9wYXNzd29yZCldKQphc3luYyBkZWYgZW1lcmdlbmN5X3JvdGF0ZSgpOgogICAgIiIiRW1lcmdlbmN5IE9yYml0IOKAlCByb3RhdGUgYWxsIGtleXMgYW5kIFNOSSBpbW1lZGlhdGVseS4iIiIKICAgIHN0YXRlID0gbG9hZF9zdGF0ZSgpCiAgICBzdGF0ZSA9IHJvdGF0ZV9rZXlzX2FuZF9zbmkoc3RhdGUpCiAgICBjZmcgICA9IGJ1aWxkX3hyYXlfY29uZmlnKHN0YXRlKQogICAgd3JpdGVfeHJheV9jb25maWcoY2ZnKQogICAgcmVsb2FkX3hyYXkoKQogICAgc2F2ZV9zdGF0ZShzdGF0ZSkKICAgIGxvZy5pbmZvKCLwn5qoIEVtZXJnZW5jeSByb3RhdGlvbiB0cmlnZ2VyZWQgYnkgQVBJIikKICAgIHJldHVybiB7CiAgICAgICAgInN1Y2Nlc3MiOiAgVHJ1ZSwKICAgICAgICAibmV3X3NuaSI6ICAgICAgc3RhdGVbInNuaSJdLAogICAgICAgICJuZXdfc2hvcnRfaWQiOiBzdGF0ZVsic2hvcnRfaWQiXSwKICAgICAgICAicm90YXRlZF9hdCI6ICAgc3RhdGVbInJvdGF0ZWRfYXQiXSwKICAgICAgICAidGNwX2xpbmsiOiAgYnVpbGRfdmxlc3NfbGluayhzdGF0ZSwgInRjcCIpLAogICAgICAgICJncnBjX2xpbmsiOiBidWlsZF92bGVzc19saW5rKHN0YXRlLCAiZ3JwYyIpLAogICAgfQoKCkBhcHAuZ2V0KCIvYXBpL2RwaSIsIGRlcGVuZGVuY2llcz1bRGVwZW5kcyh2ZXJpZnlfcGFzc3dvcmQpXSkKYXN5bmMgZGVmIGdldF9kcGkoKToKICAgIHJldHVybiBkcGlfc2NvcmVfY2FjaGUKCgpAYXBwLnBvc3QoIi9hcGkvZHBpL3JlZnJlc2giLCBkZXBlbmRlbmNpZXM9W0RlcGVuZHModmVyaWZ5X3Bhc3N3b3JkKV0pCmFzeW5jIGRlZiByZWZyZXNoX2RwaSgpOgogICAgYXN5bmNpby5jcmVhdGVfdGFzayhydW5fZHBpX21vbml0b3IoKSkKICAgIHJldHVybiB7Im1lc3NhZ2UiOiAiRFBJIHByb2JlIHN0YXJ0ZWQifQoKCkBhcHAuZ2V0KCIvYXBpL2xvZ3MiLCBkZXBlbmRlbmNpZXM9W0RlcGVuZHModmVyaWZ5X3Bhc3N3b3JkKV0pCmFzeW5jIGRlZiBnZXRfbG9ncyhsaW5lczogaW50ID0gMTAwKToKICAgIGxvZ19maWxlID0gWFJBWV9MT0dfUEFUSCAvICJhY2Nlc3MubG9nIgogICAgZXJyX2ZpbGUgPSBYUkFZX0xPR19QQVRIIC8gImVycm9yLmxvZyIKICAgIHJlc3VsdCAgID0ge30KICAgIGZvciBuYW1lLCBmIGluIFsoImFjY2VzcyIsIGxvZ19maWxlKSwgKCJlcnJvciIsIGVycl9maWxlKV06CiAgICAgICAgaWYgZi5leGlzdHMoKToKICAgICAgICAgICAgY29udGVudCA9IGYucmVhZF90ZXh0KGVycm9ycz0icmVwbGFjZSIpLnNwbGl0bGluZXMoKQogICAgICAgICAgICByZXN1bHRbbmFtZV0gPSBjb250ZW50Wy1saW5lczpdCiAgICAgICAgZWxzZToKICAgICAgICAgICAgcmVzdWx0W25hbWVdID0gW10KICAgIHJldHVybiByZXN1bHQKCgpAYXBwLmdldCgiL2FwaS9jb25maWciLCBkZXBlbmRlbmNpZXM9W0RlcGVuZHModmVyaWZ5X3Bhc3N3b3JkKV0pCmFzeW5jIGRlZiBnZXRfY29uZmlnKCk6CiAgICBzdGF0ZSA9IGxvYWRfc3RhdGUoKQogICAgY2ZnICAgPSBidWlsZF94cmF5X2NvbmZpZyhzdGF0ZSkKICAgICMgUmVkYWN0IHByaXZhdGUga2V5CiAgICBpZiAiaW5ib3VuZHMiIGluIGNmZzoKICAgICAgICBmb3IgaW5iIGluIGNmZ1siaW5ib3VuZHMiXToKICAgICAgICAgICAgcnMgPSBpbmIuZ2V0KCJzdHJlYW1TZXR0aW5ncyIsIHt9KS5nZXQoInJlYWxpdHlTZXR0aW5ncyIsIHt9KQogICAgICAgICAgICBpZiAicHJpdmF0ZUtleSIgaW4gcnM6CiAgICAgICAgICAgICAgICByc1sicHJpdmF0ZUtleSJdID0gIioqKlJFREFDVEVEKioqIgogICAgcmV0dXJuIGNmZwo=" "${INSTALL_DIR}/backend/main.py"
decode_file "d29ya2VyX3Byb2Nlc3NlcyBhdXRvOwpldmVudHMgeyB3b3JrZXJfY29ubmVjdGlvbnMgMTAyNDsgfQoKaHR0cCB7CiAgICBpbmNsdWRlICAgICAgIC9ldGMvbmdpbngvbWltZS50eXBlczsKICAgIGRlZmF1bHRfdHlwZSAgYXBwbGljYXRpb24vb2N0ZXQtc3RyZWFtOwogICAgc2VuZGZpbGUgICAgICBvbjsKICAgIGtlZXBhbGl2ZV90aW1lb3V0IDY1OwoKICAgIGd6aXAgb247CiAgICBnemlwX3R5cGVzIHRleHQvcGxhaW4gdGV4dC9jc3MgYXBwbGljYXRpb24vanNvbiBhcHBsaWNhdGlvbi9qYXZhc2NyaXB0OwoKICAgIHNlcnZlciB7CiAgICAgICAgbGlzdGVuIDgwOwogICAgICAgIHNlcnZlcl9uYW1lIF87CgogICAgICAgIHJvb3QgL3Vzci9zaGFyZS9uZ2lueC9odG1sOwogICAgICAgIGluZGV4IGluZGV4Lmh0bWw7CgogICAgICAgICMgQVBJIHByb3h5IOKGkiBGYXN0QVBJIGJhY2tlbmQKICAgICAgICBsb2NhdGlvbiAvYXBpLyB7CiAgICAgICAgICAgIHByb3h5X3Bhc3MgICAgICAgICBodHRwOi8vZWNsaXBzZV9iYWNrZW5kOjgwODA7CiAgICAgICAgICAgIHByb3h5X2h0dHBfdmVyc2lvbiAxLjE7CiAgICAgICAgICAgIHByb3h5X3NldF9oZWFkZXIgICBIb3N0ICRob3N0OwogICAgICAgICAgICBwcm94eV9zZXRfaGVhZGVyICAgWC1SZWFsLUlQICRyZW1vdGVfYWRkcjsKICAgICAgICAgICAgcHJveHlfcmVhZF90aW1lb3V0IDYwOwogICAgICAgIH0KCiAgICAgICAgbG9jYXRpb24gL2hlYWx0aCB7CiAgICAgICAgICAgIHByb3h5X3Bhc3MgaHR0cDovL2VjbGlwc2VfYmFja2VuZDo4MDgwL2hlYWx0aDsKICAgICAgICB9CgogICAgICAgICMgU1BBIGZhbGxiYWNrCiAgICAgICAgbG9jYXRpb24gLyB7CiAgICAgICAgICAgIHRyeV9maWxlcyAkdXJpICR1cmkvIC9pbmRleC5odG1sOwogICAgICAgIH0KICAgIH0KfQo=" "${INSTALL_DIR}/nginx/nginx.conf"
decode_file "PCFET0NUWVBFIGh0bWw+CjxodG1sIGxhbmc9InJ1Ij4KPGhlYWQ+CjxtZXRhIGNoYXJzZXQ9IlVURi04Ij4KPG1ldGEgbmFtZT0idmlld3BvcnQiIGNvbnRlbnQ9IndpZHRoPWRldmljZS13aWR0aCxpbml0aWFsLXNjYWxlPTEiPgo8dGl0bGU+RUNMSVBTIOKAlCBDb250cm9sIE5vZGU8L3RpdGxlPgo8bGluayByZWw9InByZWNvbm5lY3QiIGhyZWY9Imh0dHBzOi8vZm9udHMuZ29vZ2xlYXBpcy5jb20iPgo8bGluayBocmVmPSJodHRwczovL2ZvbnRzLmdvb2dsZWFwaXMuY29tL2NzczI/ZmFtaWx5PVNoYXJlK1RlY2grTW9ubyZmYW1pbHk9T3JiaXRyb246d2dodEA0MDA7NzAwOzkwMCZkaXNwbGF5PXN3YXAiIHJlbD0ic3R5bGVzaGVldCI+CjxzY3JpcHQgc3JjPSJodHRwczovL2NkbmpzLmNsb3VkZmxhcmUuY29tL2FqYXgvbGlicy9xcmNvZGVqcy8xLjAuMC9xcmNvZGUubWluLmpzIj48L3NjcmlwdD4KPHN0eWxlPgogIDpyb290IHsKICAgIC0tYmc6ICAgICAgIzAzMDcxMjsKICAgIC0tc3VyZmFjZTogIzBhMGYxZTsKICAgIC0tYm9yZGVyOiAgIzBmMjA0MDsKICAgIC0tYWNjZW50OiAgIzAwZDRmZjsKICAgIC0tYWNjZW50MjogIzdiMmZmZjsKICAgIC0tZ3JlZW46ICAgIzAwZmY4ODsKICAgIC0tcmVkOiAgICAgI2ZmMzg2MDsKICAgIC0teWVsbG93OiAgI2ZmZGQ1NzsKICAgIC0tdGV4dDogICAgI2M4ZDhmMDsKICAgIC0tZGltOiAgICAgIzNhNTA3MDsKICAgIC0tZ2xvdzogICAgMCAwIDIwcHggcmdiYSgwLDIxMiwyNTUsLjM1KTsKICAgIC0tZ2xvdzI6ICAgMCAwIDMwcHggcmdiYSgxMjMsNDcsMjU1LC40KTsKICB9CgogICosICo6OmJlZm9yZSwgKjo6YWZ0ZXIgeyBib3gtc2l6aW5nOiBib3JkZXItYm94OyBtYXJnaW46IDA7IHBhZGRpbmc6IDA7IH0KCiAgYm9keSB7CiAgICBiYWNrZ3JvdW5kOiB2YXIoLS1iZyk7CiAgICBjb2xvcjogdmFyKC0tdGV4dCk7CiAgICBmb250LWZhbWlseTogJ1NoYXJlIFRlY2ggTW9ubycsIG1vbm9zcGFjZTsKICAgIG1pbi1oZWlnaHQ6IDEwMHZoOwogICAgb3ZlcmZsb3cteDogaGlkZGVuOwogIH0KCiAgLyog4pSA4pSAIFNjYW5saW5lcyBvdmVybGF5IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgCAqLwogIGJvZHk6OmJlZm9yZSB7CiAgICBjb250ZW50OiAnJzsKICAgIHBvc2l0aW9uOiBmaXhlZDsgaW5zZXQ6IDA7IHotaW5kZXg6IDk5OTsgcG9pbnRlci1ldmVudHM6IG5vbmU7CiAgICBiYWNrZ3JvdW5kOiByZXBlYXRpbmctbGluZWFyLWdyYWRpZW50KAogICAgICAwZGVnLAogICAgICB0cmFuc3BhcmVudCwKICAgICAgdHJhbnNwYXJlbnQgMnB4LAogICAgICByZ2JhKDAsMCwwLC4wOCkgMnB4LAogICAgICByZ2JhKDAsMCwwLC4wOCkgNHB4CiAgICApOwogIH0KCiAgLyog4pSA4pSAIEdyaWQgYmFja2dyb3VuZCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAgKi8KICBib2R5OjphZnRlciB7CiAgICBjb250ZW50OiAnJzsKICAgIHBvc2l0aW9uOiBmaXhlZDsgaW5zZXQ6IDA7IHotaW5kZXg6IDA7IHBvaW50ZXItZXZlbnRzOiBub25lOwogICAgYmFja2dyb3VuZC1pbWFnZToKICAgICAgbGluZWFyLWdyYWRpZW50KHJnYmEoMCwyMTIsMjU1LC4wMykgMXB4LCB0cmFuc3BhcmVudCAxcHgpLAogICAgICBsaW5lYXItZ3JhZGllbnQoOTBkZWcsIHJnYmEoMCwyMTIsMjU1LC4wMykgMXB4LCB0cmFuc3BhcmVudCAxcHgpOwogICAgYmFja2dyb3VuZC1zaXplOiA0MHB4IDQwcHg7CiAgfQoKICAuY29udGFpbmVyIHsKICAgIHBvc2l0aW9uOiByZWxhdGl2ZTsgei1pbmRleDogMTsKICAgIG1heC13aWR0aDogMTI4MHB4OwogICAgbWFyZ2luOiAwIGF1dG87CiAgICBwYWRkaW5nOiAwIDI0cHggNDhweDsKICB9CgogIC8qIOKUgOKUgCBIZWFkZXIg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSAICovCiAgaGVhZGVyIHsKICAgIGRpc3BsYXk6IGZsZXg7CiAgICBhbGlnbi1pdGVtczogY2VudGVyOwogICAganVzdGlmeS1jb250ZW50OiBzcGFjZS1iZXR3ZWVuOwogICAgcGFkZGluZzogMjRweCAwIDIwcHg7CiAgICBib3JkZXItYm90dG9tOiAxcHggc29saWQgdmFyKC0tYm9yZGVyKTsKICAgIG1hcmdpbi1ib3R0b206IDMycHg7CiAgfQoKICAubG9nbyB7CiAgICBmb250LWZhbWlseTogJ09yYml0cm9uJywgbW9ub3NwYWNlOwogICAgZm9udC13ZWlnaHQ6IDkwMDsKICAgIGZvbnQtc2l6ZTogMjhweDsKICAgIGxldHRlci1zcGFjaW5nOiA2cHg7CiAgICBjb2xvcjogdmFyKC0tYWNjZW50KTsKICAgIHRleHQtc2hhZG93OiB2YXIoLS1nbG93KTsKICAgIGRpc3BsYXk6IGZsZXg7CiAgICBhbGlnbi1pdGVtczogY2VudGVyOwogICAgZ2FwOiAxMnB4OwogIH0KCiAgLmxvZ28tZG90IHsKICAgIHdpZHRoOiAxMHB4OyBoZWlnaHQ6IDEwcHg7CiAgICBib3JkZXItcmFkaXVzOiA1MCU7CiAgICBiYWNrZ3JvdW5kOiB2YXIoLS1ncmVlbik7CiAgICBib3gtc2hhZG93OiAwIDAgMTJweCB2YXIoLS1ncmVlbik7CiAgICBhbmltYXRpb246IHB1bHNlIDJzIGVhc2UtaW4tb3V0IGluZmluaXRlOwogIH0KCiAgQGtleWZyYW1lcyBwdWxzZSB7CiAgICAwJSwxMDAlIHsgb3BhY2l0eTogMTsgdHJhbnNmb3JtOiBzY2FsZSgxKTsgfQogICAgNTAlICAgICAgeyBvcGFjaXR5OiAuNTsgdHJhbnNmb3JtOiBzY2FsZSguOCk7IH0KICB9CgogIC5oZWFkZXItbWV0YSB7CiAgICBmb250LXNpemU6IDExcHg7CiAgICBjb2xvcjogdmFyKC0tZGltKTsKICAgIHRleHQtYWxpZ246IHJpZ2h0OwogICAgbGluZS1oZWlnaHQ6IDEuODsKICB9CgogICNzZXJ2ZXItaXAgeyBjb2xvcjogdmFyKC0tYWNjZW50KTsgfQogICNjbG9jayAgICAgeyBjb2xvcjogdmFyKC0tZ3JlZW4pOyB9CgogIC8qIOKUgOKUgCBBdXRoIG92ZXJsYXkg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSAICovCiAgI2F1dGgtb3ZlcmxheSB7CiAgICBwb3NpdGlvbjogZml4ZWQ7IGluc2V0OiAwOyB6LWluZGV4OiAxMDA7CiAgICBiYWNrZ3JvdW5kOiByZ2JhKDMsNywxOCwuOTcpOwogICAgZGlzcGxheTogZmxleDsKICAgIGFsaWduLWl0ZW1zOiBjZW50ZXI7CiAgICBqdXN0aWZ5LWNvbnRlbnQ6IGNlbnRlcjsKICAgIGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47CiAgICBnYXA6IDIwcHg7CiAgfQoKICAuYXV0aC1ib3ggewogICAgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYWNjZW50KTsKICAgIGJhY2tncm91bmQ6IHZhcigtLXN1cmZhY2UpOwogICAgcGFkZGluZzogNDBweDsKICAgIHdpZHRoOiAzNjBweDsKICAgIGJveC1zaGFkb3c6IHZhcigtLWdsb3cpOwogIH0KCiAgLmF1dGgtdGl0bGUgewogICAgZm9udC1mYW1pbHk6ICdPcmJpdHJvbicsIG1vbm9zcGFjZTsKICAgIGZvbnQtc2l6ZTogMThweDsKICAgIGNvbG9yOiB2YXIoLS1hY2NlbnQpOwogICAgbGV0dGVyLXNwYWNpbmc6IDRweDsKICAgIHRleHQtYWxpZ246IGNlbnRlcjsKICAgIG1hcmdpbi1ib3R0b206IDI4cHg7CiAgfQoKICAuYXV0aC1ib3ggaW5wdXQgewogICAgd2lkdGg6IDEwMCU7CiAgICBiYWNrZ3JvdW5kOiB2YXIoLS1iZyk7CiAgICBib3JkZXI6IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIpOwogICAgY29sb3I6IHZhcigtLXRleHQpOwogICAgZm9udC1mYW1pbHk6IGluaGVyaXQ7CiAgICBmb250LXNpemU6IDE0cHg7CiAgICBwYWRkaW5nOiAxMnB4IDE0cHg7CiAgICBvdXRsaW5lOiBub25lOwogICAgdHJhbnNpdGlvbjogYm9yZGVyLWNvbG9yIC4yczsKICB9CgogIC5hdXRoLWJveCBpbnB1dDpmb2N1cyB7IGJvcmRlci1jb2xvcjogdmFyKC0tYWNjZW50KTsgfQoKICAuYnRuIHsKICAgIHdpZHRoOiAxMDAlOwogICAgbWFyZ2luLXRvcDogMTZweDsKICAgIGJhY2tncm91bmQ6IHRyYW5zcGFyZW50OwogICAgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYWNjZW50KTsKICAgIGNvbG9yOiB2YXIoLS1hY2NlbnQpOwogICAgZm9udC1mYW1pbHk6ICdPcmJpdHJvbicsIG1vbm9zcGFjZTsKICAgIGZvbnQtc2l6ZTogMTJweDsKICAgIGxldHRlci1zcGFjaW5nOiAzcHg7CiAgICBwYWRkaW5nOiAxM3B4OwogICAgY3Vyc29yOiBwb2ludGVyOwogICAgdHJhbnNpdGlvbjogYWxsIC4yczsKICB9CgogIC5idG46aG92ZXIgewogICAgYmFja2dyb3VuZDogdmFyKC0tYWNjZW50KTsKICAgIGNvbG9yOiB2YXIoLS1iZyk7CiAgICBib3gtc2hhZG93OiB2YXIoLS1nbG93KTsKICB9CgogIC5idG4tZGFuZ2VyIHsKICAgIGJvcmRlci1jb2xvcjogdmFyKC0tcmVkKTsKICAgIGNvbG9yOiB2YXIoLS1yZWQpOwogIH0KCiAgLmJ0bi1kYW5nZXI6aG92ZXIgewogICAgYmFja2dyb3VuZDogdmFyKC0tcmVkKTsKICAgIGNvbG9yOiAjZmZmOwogICAgYm94LXNoYWRvdzogMCAwIDIwcHggcmdiYSgyNTUsNTYsOTYsLjQpOwogIH0KCiAgLmJ0bi1vcmJpdCB7CiAgICBib3JkZXItY29sb3I6IHZhcigtLWFjY2VudDIpOwogICAgY29sb3I6IHZhcigtLWFjY2VudDIpOwogICAgZm9udC1zaXplOiAxMXB4OwogICAgbGV0dGVyLXNwYWNpbmc6IDJweDsKICAgIHBhZGRpbmc6IDE2cHg7CiAgICBwb3NpdGlvbjogcmVsYXRpdmU7CiAgICBvdmVyZmxvdzogaGlkZGVuOwogIH0KCiAgLmJ0bi1vcmJpdDpob3ZlciB7CiAgICBiYWNrZ3JvdW5kOiB2YXIoLS1hY2NlbnQyKTsKICAgIGNvbG9yOiAjZmZmOwogICAgYm94LXNoYWRvdzogdmFyKC0tZ2xvdzIpOwogIH0KCiAgLmJ0bi1vcmJpdC5sb2FkaW5nOjphZnRlciB7CiAgICBjb250ZW50OiAnJzsKICAgIHBvc2l0aW9uOiBhYnNvbHV0ZTsKICAgIGxlZnQ6IDA7IHRvcDogMDsgaGVpZ2h0OiAzcHg7IHdpZHRoOiAwOwogICAgYmFja2dyb3VuZDogdmFyKC0tYWNjZW50Mik7CiAgICBhbmltYXRpb246IGxvYWQtYmFyIDEuNXMgZWFzZSBmb3J3YXJkczsKICB9CgogIEBrZXlmcmFtZXMgbG9hZC1iYXIgeyB0byB7IHdpZHRoOiAxMDAlOyB9IH0KCiAgI2F1dGgtZXJyb3IgewogICAgY29sb3I6IHZhcigtLXJlZCk7CiAgICBmb250LXNpemU6IDEycHg7CiAgICB0ZXh0LWFsaWduOiBjZW50ZXI7CiAgICBtaW4taGVpZ2h0OiAxOHB4OwogIH0KCiAgLyog4pSA4pSAIEdyaWQgbGF5b3V0IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgCAqLwogIC5kYXNoYm9hcmQgewogICAgZGlzcGxheTogZ3JpZDsKICAgIGdyaWQtdGVtcGxhdGUtY29sdW1uczogcmVwZWF0KDEyLCAxZnIpOwogICAgZ2FwOiAxNnB4OwogIH0KCiAgLmNhcmQgewogICAgYmFja2dyb3VuZDogdmFyKC0tc3VyZmFjZSk7CiAgICBib3JkZXI6IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIpOwogICAgcGFkZGluZzogMjBweCAyNHB4OwogICAgcG9zaXRpb246IHJlbGF0aXZlOwogICAgdHJhbnNpdGlvbjogYm9yZGVyLWNvbG9yIC4zczsKICB9CgogIC5jYXJkOmhvdmVyIHsgYm9yZGVyLWNvbG9yOiByZ2JhKDAsMjEyLDI1NSwuMjUpOyB9CgogIC5jYXJkLWxhYmVsIHsKICAgIGZvbnQtc2l6ZTogMTBweDsKICAgIGxldHRlci1zcGFjaW5nOiAzcHg7CiAgICBjb2xvcjogdmFyKC0tZGltKTsKICAgIHRleHQtdHJhbnNmb3JtOiB1cHBlcmNhc2U7CiAgICBtYXJnaW4tYm90dG9tOiAxMnB4OwogICAgZGlzcGxheTogZmxleDsKICAgIGFsaWduLWl0ZW1zOiBjZW50ZXI7CiAgICBnYXA6IDhweDsKICB9CgogIC5jYXJkLWxhYmVsOjpiZWZvcmUgewogICAgY29udGVudDogJyc7CiAgICBkaXNwbGF5OiBpbmxpbmUtYmxvY2s7CiAgICB3aWR0aDogMjBweDsgaGVpZ2h0OiAxcHg7CiAgICBiYWNrZ3JvdW5kOiB2YXIoLS1hY2NlbnQpOwogICAgb3BhY2l0eTogLjU7CiAgfQoKICAvKiDilIDilIAgSGVhbHRoIGNhcmQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSAICovCiAgLmNvbC00ICB7IGdyaWQtY29sdW1uOiBzcGFuIDQ7IH0KICAuY29sLTUgIHsgZ3JpZC1jb2x1bW46IHNwYW4gNTsgfQogIC5jb2wtNiAgeyBncmlkLWNvbHVtbjogc3BhbiA2OyB9CiAgLmNvbC03ICB7IGdyaWQtY29sdW1uOiBzcGFuIDc7IH0KICAuY29sLTggIHsgZ3JpZC1jb2x1bW46IHNwYW4gODsgfQogIC5jb2wtMTIgeyBncmlkLWNvbHVtbjogc3BhbiAxMjsgfQoKICBAbWVkaWEgKG1heC13aWR0aDogOTAwcHgpIHsKICAgIC5jb2wtNCwuY29sLTUsLmNvbC02LC5jb2wtNywuY29sLTggeyBncmlkLWNvbHVtbjogc3BhbiAxMjsgfQogIH0KCiAgLmhlYWx0aC1yaW5nIHsKICAgIHdpZHRoOiAxMjBweDsgaGVpZ2h0OiAxMjBweDsKICAgIG1hcmdpbjogMCBhdXRvIDE2cHg7CiAgICBwb3NpdGlvbjogcmVsYXRpdmU7CiAgfQoKICAuaGVhbHRoLXJpbmcgc3ZnIHsgdHJhbnNmb3JtOiByb3RhdGUoLTkwZGVnKTsgfQoKICAuaGVhbHRoLXJpbmcgLnJpbmctYmcgIHsgZmlsbDogbm9uZTsgc3Ryb2tlOiB2YXIoLS1ib3JkZXIpOyBzdHJva2Utd2lkdGg6IDg7IH0KICAuaGVhbHRoLXJpbmcgLnJpbmctdmFsIHsgZmlsbDogbm9uZTsgc3Ryb2tlOiB2YXIoLS1ncmVlbik7ICBzdHJva2Utd2lkdGg6IDg7CiAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0cm9rZS1saW5lY2FwOiByb3VuZDsKICAgICAgICAgICAgICAgICAgICAgICAgICAgc3Ryb2tlLWRhc2hhcnJheTogMjgzOwogICAgICAgICAgICAgICAgICAgICAgICAgICBzdHJva2UtZGFzaG9mZnNldDogMjgzOwogICAgICAgICAgICAgICAgICAgICAgICAgICB0cmFuc2l0aW9uOiBzdHJva2UtZGFzaG9mZnNldCAxcyBlYXNlLCBzdHJva2UgLjVzOyB9CgogIC5oZWFsdGgtY2VudGVyIHsKICAgIHBvc2l0aW9uOiBhYnNvbHV0ZTsKICAgIGluc2V0OiAwOwogICAgZGlzcGxheTogZmxleDsKICAgIGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47CiAgICBhbGlnbi1pdGVtczogY2VudGVyOwogICAganVzdGlmeS1jb250ZW50OiBjZW50ZXI7CiAgfQoKICAuaGVhbHRoLXBjdCB7CiAgICBmb250LWZhbWlseTogJ09yYml0cm9uJywgbW9ub3NwYWNlOwogICAgZm9udC1zaXplOiAyNHB4OwogICAgZm9udC13ZWlnaHQ6IDcwMDsKICAgIGNvbG9yOiB2YXIoLS1ncmVlbik7CiAgICBsaW5lLWhlaWdodDogMTsKICAgIHRleHQtc2hhZG93OiAwIDAgMTJweCB2YXIoLS1ncmVlbik7CiAgfQoKICAuaGVhbHRoLWxhYmVsIHsgZm9udC1zaXplOiA5cHg7IGNvbG9yOiB2YXIoLS1kaW0pOyBsZXR0ZXItc3BhY2luZzogMnB4OyB9CgogIC8qIOKUgOKUgCBEUEkgR2F1Z2Ug4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSAICovCiAgLmRwaS1nYXVnZS13cmFwIHsKICAgIHRleHQtYWxpZ246IGNlbnRlcjsKICB9CgogIC5kcGktYmFyLWJnIHsKICAgIGhlaWdodDogMTJweDsKICAgIGJhY2tncm91bmQ6IHZhcigtLWJvcmRlcik7CiAgICBib3JkZXItcmFkaXVzOiAycHg7CiAgICBvdmVyZmxvdzogaGlkZGVuOwogICAgbWFyZ2luOiAxNnB4IDAgOHB4OwogIH0KCiAgLmRwaS1iYXItZmlsbCB7CiAgICBoZWlnaHQ6IDEwMCU7CiAgICB3aWR0aDogMCU7CiAgICBiYWNrZ3JvdW5kOiBsaW5lYXItZ3JhZGllbnQoOTBkZWcsIHZhcigtLWdyZWVuKSwgdmFyKC0teWVsbG93KSwgdmFyKC0tcmVkKSk7CiAgICBib3JkZXItcmFkaXVzOiAycHg7CiAgICB0cmFuc2l0aW9uOiB3aWR0aCAxcyBlYXNlOwogIH0KCiAgLmRwaS1zY29yZS1udW0gewogICAgZm9udC1mYW1pbHk6ICdPcmJpdHJvbicsIG1vbm9zcGFjZTsKICAgIGZvbnQtc2l6ZTogMzZweDsKICAgIGZvbnQtd2VpZ2h0OiA5MDA7CiAgICBsaW5lLWhlaWdodDogMTsKICB9CgogIC5kcGktc3RhdHVzLXRleHQgeyBmb250LXNpemU6IDExcHg7IGNvbG9yOiB2YXIoLS1kaW0pOyBtYXJnaW4tdG9wOiA2cHg7IH0KCiAgLmRwaS1kZXRhaWxzIHsKICAgIGRpc3BsYXk6IGdyaWQ7CiAgICBncmlkLXRlbXBsYXRlLWNvbHVtbnM6IDFmciAxZnI7CiAgICBnYXA6IDEwcHg7CiAgICBtYXJnaW4tdG9wOiAxNHB4OwogIH0KCiAgLmRwaS1zdGF0IHsKICAgIGJhY2tncm91bmQ6IHZhcigtLWJnKTsKICAgIGJvcmRlcjogMXB4IHNvbGlkIHZhcigtLWJvcmRlcik7CiAgICBwYWRkaW5nOiAxMHB4OwogICAgdGV4dC1hbGlnbjogY2VudGVyOwogIH0KCiAgLmRwaS1zdGF0LXZhbCB7IGZvbnQtZmFtaWx5OiAnT3JiaXRyb24nLCBtb25vc3BhY2U7IGZvbnQtc2l6ZTogMTZweDsgY29sb3I6IHZhcigtLWFjY2VudCk7IH0KICAuZHBpLXN0YXQtbGJsIHsgZm9udC1zaXplOiA5cHg7IGNvbG9yOiB2YXIoLS1kaW0pOyBtYXJnaW4tdG9wOiAzcHg7IH0KCiAgLyog4pSA4pSAIENvbm5lY3Rpb24gaW5mbyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAgKi8KICAuaW5mby1yb3cgewogICAgZGlzcGxheTogZmxleDsKICAgIGp1c3RpZnktY29udGVudDogc3BhY2UtYmV0d2VlbjsKICAgIGFsaWduLWl0ZW1zOiBjZW50ZXI7CiAgICBwYWRkaW5nOiAxMHB4IDA7CiAgICBib3JkZXItYm90dG9tOiAxcHggc29saWQgdmFyKC0tYm9yZGVyKTsKICAgIGZvbnQtc2l6ZTogMTNweDsKICB9CgogIC5pbmZvLXJvdzpsYXN0LWNoaWxkIHsgYm9yZGVyLWJvdHRvbTogbm9uZTsgfQogIC5pbmZvLWtleSAgIHsgY29sb3I6IHZhcigtLWRpbSk7IGZvbnQtc2l6ZTogMTFweDsgbGV0dGVyLXNwYWNpbmc6IDFweDsgfQogIC5pbmZvLXZhbHVlIHsgY29sb3I6IHZhcigtLWFjY2VudCk7IGZvbnQtZmFtaWx5OiAnU2hhcmUgVGVjaCBNb25vJywgbW9ub3NwYWNlOyB9CiAgLmluZm8tdmFsdWUuZ3JlZW4geyBjb2xvcjogdmFyKC0tZ3JlZW4pOyB9CgogIC8qIOKUgOKUgCBUYWJzIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgCAqLwogIC50YWJzIHsgZGlzcGxheTogZmxleDsgZ2FwOiAycHg7IG1hcmdpbi1ib3R0b206IDIwcHg7IH0KCiAgLnRhYi1idG4gewogICAgYmFja2dyb3VuZDogdHJhbnNwYXJlbnQ7CiAgICBib3JkZXI6IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIpOwogICAgY29sb3I6IHZhcigtLWRpbSk7CiAgICBmb250LWZhbWlseTogaW5oZXJpdDsKICAgIGZvbnQtc2l6ZTogMTFweDsKICAgIGxldHRlci1zcGFjaW5nOiAycHg7CiAgICBwYWRkaW5nOiA4cHggMThweDsKICAgIGN1cnNvcjogcG9pbnRlcjsKICAgIHRyYW5zaXRpb246IGFsbCAuMnM7CiAgfQoKICAudGFiLWJ0bi5hY3RpdmUgewogICAgYm9yZGVyLWNvbG9yOiB2YXIoLS1hY2NlbnQpOwogICAgY29sb3I6IHZhcigtLWFjY2VudCk7CiAgICBiYWNrZ3JvdW5kOiByZ2JhKDAsMjEyLDI1NSwuMDUpOwogIH0KCiAgLnRhYi1wYW5lIHsgZGlzcGxheTogbm9uZTsgfQogIC50YWItcGFuZS5hY3RpdmUgeyBkaXNwbGF5OiBibG9jazsgfQoKICAvKiDilIDilIAgVkxFU1MgbGluayDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAgKi8KICAubGluay1ib3ggewogICAgYmFja2dyb3VuZDogdmFyKC0tYmcpOwogICAgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYm9yZGVyKTsKICAgIHBhZGRpbmc6IDE0cHggMTZweDsKICAgIGZvbnQtc2l6ZTogMTFweDsKICAgIGNvbG9yOiB2YXIoLS1ncmVlbik7CiAgICB3b3JkLWJyZWFrOiBicmVhay1hbGw7CiAgICBsaW5lLWhlaWdodDogMS42OwogICAgbWFyZ2luLWJvdHRvbTogMTJweDsKICAgIGN1cnNvcjogcG9pbnRlcjsKICAgIHRyYW5zaXRpb246IGJvcmRlci1jb2xvciAuMnM7CiAgICBwb3NpdGlvbjogcmVsYXRpdmU7CiAgfQoKICAubGluay1ib3g6aG92ZXIgeyBib3JkZXItY29sb3I6IHZhcigtLWdyZWVuKTsgfQoKICAubGluay1jb3B5LWhpbnQgewogICAgcG9zaXRpb246IGFic29sdXRlOwogICAgdG9wOiA2cHg7IHJpZ2h0OiAxMHB4OwogICAgZm9udC1zaXplOiA5cHg7CiAgICBjb2xvcjogdmFyKC0tZGltKTsKICAgIGxldHRlci1zcGFjaW5nOiAxcHg7CiAgfQoKICAuY29waWVkLXRvYXN0IHsKICAgIHBvc2l0aW9uOiBmaXhlZDsKICAgIGJvdHRvbTogMzJweDsgcmlnaHQ6IDMycHg7CiAgICBiYWNrZ3JvdW5kOiB2YXIoLS1ncmVlbik7CiAgICBjb2xvcjogdmFyKC0tYmcpOwogICAgZm9udC1mYW1pbHk6ICdPcmJpdHJvbicsIG1vbm9zcGFjZTsKICAgIGZvbnQtc2l6ZTogMTFweDsKICAgIGxldHRlci1zcGFjaW5nOiAycHg7CiAgICBwYWRkaW5nOiAxMnB4IDIwcHg7CiAgICBvcGFjaXR5OiAwOwogICAgdHJhbnNmb3JtOiB0cmFuc2xhdGVZKDEwcHgpOwogICAgdHJhbnNpdGlvbjogYWxsIC4zczsKICAgIHotaW5kZXg6IDIwMDsKICB9CgogIC5jb3BpZWQtdG9hc3Quc2hvdyB7IG9wYWNpdHk6IDE7IHRyYW5zZm9ybTogdHJhbnNsYXRlWSgwKTsgfQoKICAvKiDilIDilIAgUVIg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSAICovCiAgLnFyLXdyYXAgewogICAgZGlzcGxheTogZmxleDsKICAgIGFsaWduLWl0ZW1zOiBjZW50ZXI7CiAgICBqdXN0aWZ5LWNvbnRlbnQ6IGNlbnRlcjsKICAgIGdhcDogMzJweDsKICAgIGZsZXgtd3JhcDogd3JhcDsKICAgIHBhZGRpbmc6IDhweCAwOwogIH0KCiAgLnFyLWl0ZW0geyB0ZXh0LWFsaWduOiBjZW50ZXI7IH0KCiAgLnFyLWlubmVyIHsKICAgIHdpZHRoOiAxNjBweDsgaGVpZ2h0OiAxNjBweDsKICAgIGJhY2tncm91bmQ6ICNmZmY7CiAgICBkaXNwbGF5OiBmbGV4OwogICAgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgIGp1c3RpZnktY29udGVudDogY2VudGVyOwogICAgbWFyZ2luOiAwIGF1dG8gMTBweDsKICAgIHBhZGRpbmc6IDhweDsKICB9CgogIC5xci1pbm5lciBjYW52YXMgeyB3aWR0aDogMTQ0cHggIWltcG9ydGFudDsgaGVpZ2h0OiAxNDRweCAhaW1wb3J0YW50OyB9CgogIC5xci10YWcgewogICAgZm9udC1zaXplOiAxMHB4OwogICAgbGV0dGVyLXNwYWNpbmc6IDJweDsKICAgIGNvbG9yOiB2YXIoLS1kaW0pOwogIH0KCiAgLyog4pSA4pSAIExvZ3Mg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSAICovCiAgLmxvZy1ib3ggewogICAgYmFja2dyb3VuZDogdmFyKC0tYmcpOwogICAgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYm9yZGVyKTsKICAgIHBhZGRpbmc6IDE0cHg7CiAgICBmb250LXNpemU6IDExcHg7CiAgICBjb2xvcjogIzRhOTsKICAgIGhlaWdodDogMjYwcHg7CiAgICBvdmVyZmxvdy15OiBhdXRvOwogICAgbGluZS1oZWlnaHQ6IDEuNzsKICB9CgogIC5sb2ctYm94IC5lcnIgeyBjb2xvcjogdmFyKC0tcmVkKTsgfQogIC5sb2ctYm94IC53YXJuIHsgY29sb3I6IHZhcigtLXllbGxvdyk7IH0KCiAgLyog4pSA4pSAIE9yYml0IGJ1dHRvbiDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAgKi8KICAub3JiaXQtc2VjdGlvbiB7CiAgICB0ZXh0LWFsaWduOiBjZW50ZXI7CiAgICBwYWRkaW5nOiA4cHggMDsKICB9CgogIC5vcmJpdC13YXJuIHsKICAgIGZvbnQtc2l6ZTogMTFweDsKICAgIGNvbG9yOiB2YXIoLS1kaW0pOwogICAgbWFyZ2luLXRvcDogMTRweDsKICAgIGxpbmUtaGVpZ2h0OiAxLjY7CiAgfQoKICAub3JiaXQtcmVzdWx0IHsKICAgIG1hcmdpbi10b3A6IDE2cHg7CiAgICBiYWNrZ3JvdW5kOiByZ2JhKDEyMyw0NywyNTUsLjEpOwogICAgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYWNjZW50Mik7CiAgICBwYWRkaW5nOiAxNHB4OwogICAgZm9udC1zaXplOiAxMXB4OwogICAgY29sb3I6IHZhcigtLWFjY2VudDIpOwogICAgbGluZS1oZWlnaHQ6IDEuODsKICAgIGRpc3BsYXk6IG5vbmU7CiAgfQoKICAvKiDilIDilIAgUm90YXRpb24gY291bnRkb3duIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgCAqLwogIC5uZXh0LXJvdGF0aW9uIHsKICAgIGZvbnQtZmFtaWx5OiAnT3JiaXRyb24nLCBtb25vc3BhY2U7CiAgICBmb250LXNpemU6IDIwcHg7CiAgICBjb2xvcjogdmFyKC0teWVsbG93KTsKICAgIGxldHRlci1zcGFjaW5nOiAzcHg7CiAgICB0ZXh0LXNoYWRvdzogMCAwIDEycHggcmdiYSgyNTUsMjIxLDg3LC40KTsKICB9CgogIC8qIOKUgOKUgCBVcHRpbWUgLyBmb290ZXIgYmFyIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgCAqLwogIC5mb290ZXItYmFyIHsKICAgIG1hcmdpbi10b3A6IDMycHg7CiAgICBib3JkZXItdG9wOiAxcHggc29saWQgdmFyKC0tYm9yZGVyKTsKICAgIHBhZGRpbmctdG9wOiAxNnB4OwogICAgZGlzcGxheTogZmxleDsKICAgIGdhcDogMzJweDsKICAgIGZvbnQtc2l6ZTogMTFweDsKICAgIGNvbG9yOiB2YXIoLS1kaW0pOwogICAgZmxleC13cmFwOiB3cmFwOwogIH0KCiAgLmZvb3Rlci1iYXIgc3BhbiB7IGNvbG9yOiB2YXIoLS1hY2NlbnQpOyB9CgogIC8qIOKUgOKUgCBCbGluayBjdXJzb3Ig4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSAICovCiAgLmJsaW5rIHsgYW5pbWF0aW9uOiBibGluayAxcyBzdGVwLWVuZCBpbmZpbml0ZTsgfQogIEBrZXlmcmFtZXMgYmxpbmsgeyA1MCUgeyBvcGFjaXR5OiAwOyB9IH0KCiAgLyog4pSA4pSAIFNjcm9sbGJhciDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAgKi8KICA6Oi13ZWJraXQtc2Nyb2xsYmFyIHsgd2lkdGg6IDZweDsgfQogIDo6LXdlYmtpdC1zY3JvbGxiYXItdHJhY2sgeyBiYWNrZ3JvdW5kOiB2YXIoLS1iZyk7IH0KICA6Oi13ZWJraXQtc2Nyb2xsYmFyLXRodW1iIHsgYmFja2dyb3VuZDogdmFyKC0tYm9yZGVyKTsgYm9yZGVyLXJhZGl1czogM3B4OyB9CiAgOjotd2Via2l0LXNjcm9sbGJhci10aHVtYjpob3ZlciB7IGJhY2tncm91bmQ6IHZhcigtLWRpbSk7IH0KPC9zdHlsZT4KPC9oZWFkPgo8Ym9keT4KCjwhLS0g4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQCiAgICAgQVVUSCBPVkVSTEFZCuKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkCAtLT4KPGRpdiBpZD0iYXV0aC1vdmVybGF5Ij4KICA8ZGl2IGNsYXNzPSJhdXRoLWJveCI+CiAgICA8ZGl2IGNsYXNzPSJhdXRoLXRpdGxlIj4vLyBFQ0xJUFMgQVVUSDwvZGl2PgogICAgPGlucHV0IGlkPSJhdXRoLXBhc3MiIHR5cGU9InBhc3N3b3JkIiBwbGFjZWhvbGRlcj0i0JLQktCV0JTQmNCi0JUg0J/QkNCg0J7Qm9CsIiBhdXRvY29tcGxldGU9Im9mZiI+CiAgICA8YnV0dG9uIGNsYXNzPSJidG4iIG9uY2xpY2s9ImRvQXV0aCgpIj7QktCe0JnQotCYINCSINCh0JjQodCi0JXQnNCjPC9idXR0b24+CiAgICA8ZGl2IGlkPSJhdXRoLWVycm9yIj48L2Rpdj4KICA8L2Rpdj4KICA8ZGl2IHN0eWxlPSJmb250LXNpemU6MTFweDtjb2xvcjp2YXIoLS1kaW0pO2xldHRlci1zcGFjaW5nOjJweDsiPkVDTElQUyB2MS4wIMK3IENPTlRST0wgTk9ERTxzcGFuIGNsYXNzPSJibGluayI+Xzwvc3Bhbj48L2Rpdj4KPC9kaXY+Cgo8IS0tIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkAogICAgIE1BSU4gREFTSEJPQVJECuKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkCAtLT4KPGRpdiBpZD0ibWFpbiIgc3R5bGU9ImRpc3BsYXk6bm9uZSI+CjxkaXYgY2xhc3M9ImNvbnRhaW5lciI+CgogIDwhLS0gSGVhZGVyIC0tPgogIDxoZWFkZXI+CiAgICA8ZGl2IGNsYXNzPSJsb2dvIj4KICAgICAgPGRpdiBjbGFzcz0ibG9nby1kb3QiPjwvZGl2PgogICAgICBFQ0xJUFMKICAgIDwvZGl2PgogICAgPGRpdiBjbGFzcz0iaGVhZGVyLW1ldGEiPgogICAgICA8ZGl2PlNFUlZFUiBJUDogPHNwYW4gaWQ9InNlcnZlci1pcCI+4oCUPC9zcGFuPjwvZGl2PgogICAgICA8ZGl2PlVUQzogPHNwYW4gaWQ9ImNsb2NrIj7igJQ8L3NwYW4+PC9kaXY+CiAgICAgIDxkaXY+VVBUSU1FOiA8c3BhbiBpZD0idXB0aW1lIj7igJQ8L3NwYW4+PC9kaXY+CiAgICA8L2Rpdj4KICA8L2hlYWRlcj4KCiAgPCEtLSBEYXNoYm9hcmQgZ3JpZCAtLT4KICA8ZGl2IGNsYXNzPSJkYXNoYm9hcmQiPgoKICAgIDwhLS0g4pSA4pSAIFN5c3RlbSBIZWFsdGgg4pSA4pSAIC0tPgogICAgPGRpdiBjbGFzcz0iY2FyZCBjb2wtNCI+CiAgICAgIDxkaXYgY2xhc3M9ImNhcmQtbGFiZWwiPlN5c3RlbSBIZWFsdGg8L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0iaGVhbHRoLXJpbmciPgogICAgICAgIDxzdmcgdmlld0JveD0iMCAwIDEwMCAxMDAiIHdpZHRoPSIxMjAiIGhlaWdodD0iMTIwIj4KICAgICAgICAgIDxjaXJjbGUgY2xhc3M9InJpbmctYmciICBjeD0iNTAiIGN5PSI1MCIgcj0iNDUiLz4KICAgICAgICAgIDxjaXJjbGUgY2xhc3M9InJpbmctdmFsIiBjeD0iNTAiIGN5PSI1MCIgcj0iNDUiIGlkPSJoZWFsdGgtcmluZyIvPgogICAgICAgIDwvc3ZnPgogICAgICAgIDxkaXYgY2xhc3M9ImhlYWx0aC1jZW50ZXIiPgogICAgICAgICAgPGRpdiBjbGFzcz0iaGVhbHRoLXBjdCIgaWQ9ImhlYWx0aC1wY3QiPuKAlDwvZGl2PgogICAgICAgICAgPGRpdiBjbGFzcz0iaGVhbHRoLWxhYmVsIj5IRUFMVEg8L2Rpdj4KICAgICAgICA8L2Rpdj4KICAgICAgPC9kaXY+CiAgICAgIDxkaXYgc3R5bGU9InRleHQtYWxpZ246Y2VudGVyO2ZvbnQtc2l6ZToxMnB4O2NvbG9yOnZhcigtLWRpbSk7bWFyZ2luLXRvcDo0cHg7IiBpZD0iaGVhbHRoLXRleHQiPtCX0LDQs9GA0YPQt9C60LDigKY8L2Rpdj4KICAgIDwvZGl2PgoKICAgIDwhLS0g4pSA4pSAIERQSSBBbGVydCBXaWRnZXQg4pSA4pSAIC0tPgogICAgPGRpdiBjbGFzcz0iY2FyZCBjb2wtOCI+CiAgICAgIDxkaXYgY2xhc3M9ImNhcmQtbGFiZWwiPkRQSSBJbnRlcmZlcmVuY2UgU2NvcmU8L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0iZHBpLWdhdWdlLXdyYXAiPgogICAgICAgIDxkaXYgY2xhc3M9ImRwaS1zY29yZS1udW0iIGlkPSJkcGktc2NvcmUiIHN0eWxlPSJjb2xvcjp2YXIoLS1ncmVlbikiPuKAlDwvZGl2PgogICAgICAgIDxkaXYgY2xhc3M9ImRwaS1iYXItYmciPjxkaXYgY2xhc3M9ImRwaS1iYXItZmlsbCIgaWQ9ImRwaS1iYXIiPjwvZGl2PjwvZGl2PgogICAgICAgIDxkaXYgY2xhc3M9ImRwaS1zdGF0dXMtdGV4dCIgaWQ9ImRwaS1zdGF0dXMtdGV4dCI+0JjQt9C80LXRgNC10L3QuNC14oCmPC9kaXY+CiAgICAgICAgPGRpdiBjbGFzcz0iZHBpLWRldGFpbHMiPgogICAgICAgICAgPGRpdiBjbGFzcz0iZHBpLXN0YXQiPgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJkcGktc3RhdC12YWwiIGlkPSJkcGktYmxvY2tlZCI+4oCUPC9kaXY+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9ImRwaS1zdGF0LWxibCI+0JfQkNCR0JvQntCaLiDQodCQ0JnQotCrICjQvNGBKTwvZGl2PgogICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJkcGktc3RhdCI+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9ImRwaS1zdGF0LXZhbCIgaWQ9ImRwaS1kaXJlY3QiPuKAlDwvZGl2PgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJkcGktc3RhdC1sYmwiPtCf0KDQr9Cc0KvQlSDQodCQ0JnQotCrICjQvNGBKTwvZGl2PgogICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJkcGktc3RhdCI+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9ImRwaS1zdGF0LXZhbCIgaWQ9ImRwaS10aW1lb3V0cyI+4oCUPC9kaXY+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9ImRwaS1zdGF0LWxibCI+0KLQkNCZ0JzQkNCj0KLQqzwvZGl2PgogICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJkcGktc3RhdCI+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9ImRwaS1zdGF0LXZhbCIgaWQ9ImRwaS11cGRhdGVkIj7igJQ8L2Rpdj4KICAgICAgICAgICAgPGRpdiBjbGFzcz0iZHBpLXN0YXQtbGJsIj7QntCR0J3QntCS0JvQldCd0J48L2Rpdj4KICAgICAgICAgIDwvZGl2PgogICAgICAgIDwvZGl2PgogICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biIgc3R5bGU9Im1hcmdpbi10b3A6MTRweDtmb250LXNpemU6MTBweDtsZXR0ZXItc3BhY2luZzoycHg7IiBvbmNsaWNrPSJyZWZyZXNoRFBJKCkiPuKGuyDQntCR0J3QntCS0JjQotCsIERQSTwvYnV0dG9uPgogICAgICA8L2Rpdj4KICAgIDwvZGl2PgoKICAgIDwhLS0g4pSA4pSAIENvbm5lY3Rpb24gSW5mbyDilIDilIAgLS0+CiAgICA8ZGl2IGNsYXNzPSJjYXJkIGNvbC01Ij4KICAgICAgPGRpdiBjbGFzcz0iY2FyZC1sYWJlbCI+0J/QsNGA0LDQvNC10YLRgNGLINC/0L7QtNC60LvRjtGH0LXQvdC40Y88L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0iaW5mby1yb3ciPgogICAgICAgIDxkaXYgY2xhc3M9ImluZm8ta2V5Ij5TTkk8L2Rpdj4KICAgICAgICA8ZGl2IGNsYXNzPSJpbmZvLXZhbHVlIiBpZD0iaW5mby1zbmkiPuKAlDwvZGl2PgogICAgICA8L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0iaW5mby1yb3ciPgogICAgICAgIDxkaXYgY2xhc3M9ImluZm8ta2V5Ij5TSE9SVCBJRDwvZGl2PgogICAgICAgIDxkaXYgY2xhc3M9ImluZm8tdmFsdWUiIGlkPSJpbmZvLXNpZCI+4oCUPC9kaXY+CiAgICAgIDwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJpbmZvLXJvdyI+CiAgICAgICAgPGRpdiBjbGFzcz0iaW5mby1rZXkiPlBPUlQgVENQPC9kaXY+CiAgICAgICAgPGRpdiBjbGFzcz0iaW5mby12YWx1ZSBncmVlbiI+NDQzPC9kaXY+CiAgICAgIDwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJpbmZvLXJvdyI+CiAgICAgICAgPGRpdiBjbGFzcz0iaW5mby1rZXkiPlBPUlQgZ1JQQzwvZGl2PgogICAgICAgIDxkaXYgY2xhc3M9ImluZm8tdmFsdWUgZ3JlZW4iPjg0NDM8L2Rpdj4KICAgICAgPC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9ImluZm8tcm93Ij4KICAgICAgICA8ZGl2IGNsYXNzPSJpbmZvLWtleSI+0KHQm9CV0JTQo9Cu0KnQkNCvINCg0J7QotCQ0KbQmNCvPC9kaXY+CiAgICAgICAgPGRpdiBjbGFzcz0ibmV4dC1yb3RhdGlvbiIgaWQ9Im5leHQtcm90YXRpb24iPuKAlDwvZGl2PgogICAgICA8L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0iaW5mby1yb3ciPgogICAgICAgIDxkaXYgY2xhc3M9ImluZm8ta2V5Ij7Qn9Ce0KHQm9CV0JTQndCv0K8g0KDQntCi0JDQptCY0K88L2Rpdj4KICAgICAgICA8ZGl2IGNsYXNzPSJpbmZvLXZhbHVlIiBpZD0iaW5mby1yb3RhdGVkIiBzdHlsZT0iZm9udC1zaXplOjExcHgiPuKAlDwvZGl2PgogICAgICA8L2Rpdj4KICAgIDwvZGl2PgoKICAgIDwhLS0g4pSA4pSAIEVtZXJnZW5jeSBPcmJpdCDilIDilIAgLS0+CiAgICA8ZGl2IGNsYXNzPSJjYXJkIGNvbC03Ij4KICAgICAgPGRpdiBjbGFzcz0iY2FyZC1sYWJlbCI+0K3QutGB0YLRgNC10L3QvdCw0Y8g0L7RgNCx0LjRgtCwPC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9Im9yYml0LXNlY3Rpb24iPgogICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biBidG4tb3JiaXQiIHN0eWxlPSJ3aWR0aDoxMDAlO2ZvbnQtc2l6ZToxM3B4O3BhZGRpbmc6MjBweDtsZXR0ZXItc3BhY2luZzo0cHg7IiBpZD0ib3JiaXQtYnRuIiBvbmNsaWNrPSJlbWVyZ2VuY3lPcmJpdCgpIj4KICAgICAgICAgIPCfmoAgRU1FUkdFTkNZIE9SQklUCiAgICAgICAgPC9idXR0b24+CiAgICAgICAgPGRpdiBjbGFzcz0ib3JiaXQtd2FybiI+CiAgICAgICAgICDQndC10LzQtdC00LvQtdC90L3QsNGPINGB0LzQtdC90LAg0LLRgdC10YUg0LrQu9GO0YfQtdC5LCBTaG9ydElEINC4IFNOSS48YnI+CiAgICAgICAgICDQktGB0LUg0LDQutGC0LjQstC90YvQtSDRgdC+0LXQtNC40L3QtdC90LjRjyDQsdGD0LTRg9GCINC/0LXRgNC10L/QvtC00LrQu9GO0YfQtdC90Ysg0LDQstGC0L7QvNCw0YLQuNGH0LXRgdC60LguPGJyPgogICAgICAgICAgPHNwYW4gc3R5bGU9ImNvbG9yOnZhcigtLXllbGxvdyk7Ij7QmNGB0L/QvtC70YzQt9GD0LnRgtC1INC/0YDQuCDQvtCx0L3QsNGA0YPQttC10L3QuNC4IERQSS3QsdC70L7QutC40YDQvtCy0LrQuC48L3NwYW4+CiAgICAgICAgPC9kaXY+CiAgICAgICAgPGRpdiBjbGFzcz0ib3JiaXQtcmVzdWx0IiBpZD0ib3JiaXQtcmVzdWx0Ij48L2Rpdj4KICAgICAgPC9kaXY+CiAgICA8L2Rpdj4KCiAgICA8IS0tIOKUgOKUgCBWTEVTUyBMaW5rcyArIFFSIOKUgOKUgCAtLT4KICAgIDxkaXYgY2xhc3M9ImNhcmQgY29sLTEyIj4KICAgICAgPGRpdiBjbGFzcz0iY2FyZC1sYWJlbCI+VkxFU1Mg0KHRgdGL0LvQutC4INC4IFFSLdC60L7QtNGLPC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9InRhYnMiPgogICAgICAgIDxidXR0b24gY2xhc3M9InRhYi1idG4gYWN0aXZlIiBvbmNsaWNrPSJzd2l0Y2hUYWIoJ3RjcCcpIj5UQ1AgUE9SVCA0NDM8L2J1dHRvbj4KICAgICAgICA8YnV0dG9uIGNsYXNzPSJ0YWItYnRuIiBvbmNsaWNrPSJzd2l0Y2hUYWIoJ2dycGMnKSI+Z1JQQyBQT1JUIDg0NDM8L2J1dHRvbj4KICAgICAgICA8YnV0dG9uIGNsYXNzPSJ0YWItYnRuIiBvbmNsaWNrPSJzd2l0Y2hUYWIoJ3FyJykiPlFSINCa0J7QlNCrPC9idXR0b24+CiAgICAgIDwvZGl2PgoKICAgICAgPGRpdiBjbGFzcz0idGFiLXBhbmUgYWN0aXZlIiBpZD0idGFiLXRjcCI+CiAgICAgICAgPGRpdiBjbGFzcz0ibGluay1ib3giIGlkPSJsaW5rLXRjcCIgb25jbGljaz0iY29weUxpbmsoJ3RjcCcpIj4KICAgICAgICAgIDxzcGFuIGNsYXNzPSJsaW5rLWNvcHktaGludCI+0J3QkNCW0JzQmNCi0JUg0JTQm9CvINCa0J7Qn9CY0KDQntCS0JDQndCY0K88L3NwYW4+CiAgICAgICAgICA8c3BhbiBpZD0ibGluay10Y3AtdGV4dCI+0JfQsNCz0YDRg9C30LrQsOKApjwvc3Bhbj4KICAgICAgICA8L2Rpdj4KICAgICAgICA8ZGl2IHN0eWxlPSJmb250LXNpemU6MTFweDtjb2xvcjp2YXIoLS1kaW0pO2xpbmUtaGVpZ2h0OjEuODttYXJnaW4tdG9wOjRweDsiPgogICAgICAgICAg4pqhINCf0YDQvtGC0L7QutC+0Ls6IFZMRVNTICsgUmVhbGl0eSAoVENQKSDCtyDQn9C+0YLQvtC6OiB4dGxzLXJwcngtdmlzaW9uIMK3IHVUTFM6IFNhZmFyaQogICAgICAgIDwvZGl2PgogICAgICA8L2Rpdj4KCiAgICAgIDxkaXYgY2xhc3M9InRhYi1wYW5lIiBpZD0idGFiLWdycGMiPgogICAgICAgIDxkaXYgY2xhc3M9ImxpbmstYm94IiBpZD0ibGluay1ncnBjIiBvbmNsaWNrPSJjb3B5TGluaygnZ3JwYycpIj4KICAgICAgICAgIDxzcGFuIGNsYXNzPSJsaW5rLWNvcHktaGludCI+0J3QkNCW0JzQmNCi0JUg0JTQm9CvINCa0J7Qn9CY0KDQntCS0JDQndCY0K88L3NwYW4+CiAgICAgICAgICA8c3BhbiBpZD0ibGluay1ncnBjLXRleHQiPtCX0LDQs9GA0YPQt9C60LDigKY8L3NwYW4+CiAgICAgICAgPC9kaXY+CiAgICAgICAgPGRpdiBzdHlsZT0iZm9udC1zaXplOjExcHg7Y29sb3I6dmFyKC0tZGltKTtsaW5lLWhlaWdodDoxLjg7bWFyZ2luLXRvcDo0cHg7Ij4KICAgICAgICAgIOKaoSDQn9GA0L7RgtC+0LrQvtC7OiBWTEVTUyArIFJlYWxpdHkgKGdSUEMpIMK3INCg0LXQttC40Lw6IG11bHRpUGF0aCDCtyB1VExTOiBDaHJvbWUKICAgICAgICA8L2Rpdj4KICAgICAgPC9kaXY+CgogICAgICA8ZGl2IGNsYXNzPSJ0YWItcGFuZSIgaWQ9InRhYi1xciI+CiAgICAgICAgPGRpdiBjbGFzcz0icXItd3JhcCIgaWQ9InFyLXdyYXAiPgogICAgICAgICAgPGRpdiBjbGFzcz0icXItaXRlbSI+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9InFyLWlubmVyIj48ZGl2IGlkPSJxci10Y3AiPjwvZGl2PjwvZGl2PgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJxci10YWciPlRDUCDCtyBQT1JUIDQ0MzwvZGl2PgogICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJxci1pdGVtIj4KICAgICAgICAgICAgPGRpdiBjbGFzcz0icXItaW5uZXIiPjxkaXYgaWQ9InFyLWdycGMiPjwvZGl2PjwvZGl2PgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJxci10YWciPmdSUEMgwrcgUE9SVCA4NDQzPC9kaXY+CiAgICAgICAgICA8L2Rpdj4KICAgICAgICA8L2Rpdj4KICAgICAgICA8ZGl2IHN0eWxlPSJ0ZXh0LWFsaWduOmNlbnRlcjtmb250LXNpemU6MTFweDtjb2xvcjp2YXIoLS1kaW0pO21hcmdpbi10b3A6OHB4OyI+CiAgICAgICAgICDQntGC0YHQutCw0L3QuNGA0YPQudGC0LUg0LIgU2hhZG93cm9ja2V0IC8gVjJyYXlORyAvIE5la29Cb3gKICAgICAgICA8L2Rpdj4KICAgICAgPC9kaXY+CiAgICA8L2Rpdj4KCiAgICA8IS0tIOKUgOKUgCBMb2dzIOKUgOKUgCAtLT4KICAgIDxkaXYgY2xhc3M9ImNhcmQgY29sLTEyIj4KICAgICAgPGRpdiBjbGFzcz0iY2FyZC1sYWJlbCIgc3R5bGU9Imp1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2Rpc3BsYXk6ZmxleDsiPgogICAgICAgIDxzcGFuPtCb0L7Qs9C4IFhyYXk8L3NwYW4+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0idGFiLWJ0biIgb25jbGljaz0ibG9hZExvZ3MoKSIgc3R5bGU9InBhZGRpbmc6NHB4IDEycHg7Zm9udC1zaXplOjlweDsiPuKGuyDQntCR0J3QntCS0JjQotCsPC9idXR0b24+CiAgICAgIDwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJ0YWJzIj4KICAgICAgICA8YnV0dG9uIGNsYXNzPSJ0YWItYnRuIGFjdGl2ZSIgb25jbGljaz0ic3dpdGNoTG9nVGFiKCdhY2Nlc3MnKSI+QUNDRVNTPC9idXR0b24+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0idGFiLWJ0biIgb25jbGljaz0ic3dpdGNoTG9nVGFiKCdlcnJvcicpIj5FUlJPUjwvYnV0dG9uPgogICAgICA8L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0ibG9nLWJveCIgaWQ9ImxvZy1ib3giPtCX0LDQs9GA0YPQt9C60LAg0LvQvtCz0L7QsuKApjwvZGl2PgogICAgPC9kaXY+CgogIDwvZGl2PjwhLS0gL2Rhc2hib2FyZCAtLT4KCiAgPGRpdiBjbGFzcz0iZm9vdGVyLWJhciI+CiAgICA8ZGl2PkVDTElQUyBWUE4gwrcgPHNwYW4+djEuMC4wPC9zcGFuPjwvZGl2PgogICAgPGRpdj5FTkdJTkU6IDxzcGFuPlhyYXktY29yZTwvc3Bhbj48L2Rpdj4KICAgIDxkaXY+UFJPVE86IDxzcGFuPlZMRVNTK1JlYWxpdHk8L3NwYW4+PC9kaXY+CiAgICA8ZGl2Pk9CRlM6IDxzcGFuPnVUTFMgKyBUQ1AgRnJhZ21lbnRhdGlvbjwvc3Bhbj48L2Rpdj4KICAgIDxkaXY+PHNwYW4gY2xhc3M9ImJsaW5rIj7il488L3NwYW4+IE9OTElORTwvZGl2PgogIDwvZGl2PgoKPC9kaXY+PCEtLSAvY29udGFpbmVyIC0tPgo8L2Rpdj48IS0tIC9tYWluIC0tPgoKPGRpdiBjbGFzcz0iY29waWVkLXRvYXN0IiBpZD0idG9hc3QiPtCh0JrQntCf0JjQoNCe0JLQkNCd0J48L2Rpdj4KCjxzY3JpcHQ+Ci8vIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAovLyBBdXRoCi8vIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApsZXQgQVVUSF9IRUFERVIgPSAnJzsKCmZ1bmN0aW9uIG1ha2VCYXNpYyhwYXNzKSB7CiAgcmV0dXJuICdCYXNpYyAnICsgYnRvYSgnZWNsaXBzOicgKyBwYXNzKTsKfQoKYXN5bmMgZnVuY3Rpb24gZG9BdXRoKCkgewogIGNvbnN0IHBhc3MgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnYXV0aC1wYXNzJykudmFsdWUudHJpbSgpOwogIGlmICghcGFzcykgcmV0dXJuOwogIGNvbnN0IGhlYWRlciA9IG1ha2VCYXNpYyhwYXNzKTsKICB0cnkgewogICAgY29uc3QgciA9IGF3YWl0IGZldGNoKCcvYXBpL3N0YXR1cycsIHsgaGVhZGVyczogeyBBdXRob3JpemF0aW9uOiBoZWFkZXIgfSB9KTsKICAgIGlmIChyLm9rKSB7CiAgICAgIEFVVEhfSEVBREVSID0gaGVhZGVyOwogICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnYXV0aC1vdmVybGF5Jykuc3R5bGUuZGlzcGxheSA9ICdub25lJzsKICAgICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ21haW4nKS5zdHlsZS5kaXNwbGF5ID0gJ2Jsb2NrJzsKICAgICAgaW5pdERhc2hib2FyZCgpOwogICAgfSBlbHNlIHsKICAgICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2F1dGgtZXJyb3InKS50ZXh0Q29udGVudCA9ICcvLyDQlNCe0KHQotCj0J8g0JfQkNCf0KDQldCp0IHQnSc7CiAgICB9CiAgfSBjYXRjaChlKSB7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnYXV0aC1lcnJvcicpLnRleHRDb250ZW50ID0gJy8vINCe0KjQmNCR0JrQkCDQodCe0JXQlNCY0J3QldCd0JjQryc7CiAgfQp9Cgpkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnYXV0aC1wYXNzJykuYWRkRXZlbnRMaXN0ZW5lcigna2V5ZG93bicsIGUgPT4gewogIGlmIChlLmtleSA9PT0gJ0VudGVyJykgZG9BdXRoKCk7Cn0pOwoKLy8g4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACi8vIEFQSSBjYWxscwovLyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKYXN5bmMgZnVuY3Rpb24gYXBpKHBhdGgsIG1ldGhvZD0nR0VUJykgewogIGNvbnN0IHIgPSBhd2FpdCBmZXRjaChwYXRoLCB7IG1ldGhvZCwgaGVhZGVyczogeyBBdXRob3JpemF0aW9uOiBBVVRIX0hFQURFUiB9IH0pOwogIGlmICghci5vaykgdGhyb3cgbmV3IEVycm9yKHIuc3RhdHVzKTsKICByZXR1cm4gci5qc29uKCk7Cn0KCi8vIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAovLyBJbml0Ci8vIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApmdW5jdGlvbiBpbml0RGFzaGJvYXJkKCkgewogIHVwZGF0ZUNsb2NrKCk7CiAgc2V0SW50ZXJ2YWwodXBkYXRlQ2xvY2ssIDEwMDApOwogIGxvYWRTdGF0dXMoKTsKICBsb2FkTGlua3MoKTsKICBsb2FkTG9ncygpOwogIHNldEludGVydmFsKGxvYWRTdGF0dXMsIDMwMDAwKTsKICBzZXRJbnRlcnZhbChsb2FkTGlua3MsIDYwMDAwKTsKfQoKZnVuY3Rpb24gdXBkYXRlQ2xvY2soKSB7CiAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2Nsb2NrJykudGV4dENvbnRlbnQgPSBuZXcgRGF0ZSgpLnRvVVRDU3RyaW5nKCkuc2xpY2UoMTcsMjUpOwp9CgpmdW5jdGlvbiBmbXRVcHRpbWUoc2VjKSB7CiAgY29uc3QgZCA9IE1hdGguZmxvb3Ioc2VjIC8gODY0MDApOwogIGNvbnN0IGggPSBNYXRoLmZsb29yKChzZWMgJSA4NjQwMCkgLyAzNjAwKTsKICBjb25zdCBtID0gTWF0aC5mbG9vcigoc2VjICUgMzYwMCkgLyA2MCk7CiAgcmV0dXJuIChkID4gMCA/IGQgKyAnZCAnIDogJycpICsgaCArICdoICcgKyBtICsgJ20nOwp9Cgphc3luYyBmdW5jdGlvbiBsb2FkU3RhdHVzKCkgewogIHRyeSB7CiAgICBjb25zdCBzID0gYXdhaXQgYXBpKCcvYXBpL3N0YXR1cycpOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3NlcnZlci1pcCcpLnRleHRDb250ZW50ID0gcy5zZXJ2ZXJfaXAgfHwgJ+KAlCc7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgndXB0aW1lJykudGV4dENvbnRlbnQgPSBzLnVwdGltZV9zZWMgPyBmbXRVcHRpbWUocy51cHRpbWVfc2VjKSA6ICfigJQnOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2luZm8tc25pJykudGV4dENvbnRlbnQgPSBzLnNuaSB8fCAn4oCUJzsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdpbmZvLXNpZCcpLnRleHRDb250ZW50ID0gcy5zaG9ydF9pZCB8fCAn4oCUJzsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdpbmZvLXJvdGF0ZWQnKS50ZXh0Q29udGVudCA9IHMucm90YXRlZF9hdCA/IHMucm90YXRlZF9hdC5zbGljZSgwLDE5KS5yZXBsYWNlKCdUJywnICcpIDogJ+KAlCc7CgogICAgLy8gTmV4dCByb3RhdGlvbiAoYXNzdW1lIDI0aCBjeWNsZSBmcm9tIHJvdGF0ZWRfYXQpCiAgICBpZiAocy5yb3RhdGVkX2F0KSB7CiAgICAgIGNvbnN0IG5leHQgPSBuZXcgRGF0ZShuZXcgRGF0ZShzLnJvdGF0ZWRfYXQpLmdldFRpbWUoKSArIDI0KjM2MDAqMTAwMCk7CiAgICAgIGNvbnN0IGRpZmYgPSBNYXRoLm1heCgwLCBuZXh0IC0gRGF0ZS5ub3coKSk7CiAgICAgIGNvbnN0IGhoID0gTWF0aC5mbG9vcihkaWZmLzM2MDAwMDApOwogICAgICBjb25zdCBtbSA9IE1hdGguZmxvb3IoKGRpZmYlMzYwMDAwMCkvNjAwMDApOwogICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbmV4dC1yb3RhdGlvbicpLnRleHRDb250ZW50ID0gaGggKyAnaCAnICsgbW0gKyAnbSc7CiAgICB9CgogICAgLy8gSGVhbHRoIHNjb3JlIChpbnZlcnNlIG9mIERQSSBzY29yZSkKICAgIHVwZGF0ZURQSShzLmRwaSk7CgogICAgLy8gSGVhbHRoIHJpbmcKICAgIGNvbnN0IHNjb3JlID0gcy5kcGkgPyBNYXRoLm1heCgwLCAxMDAgLSBzLmRwaS5zY29yZSkgOiAxMDA7CiAgICBzZXRIZWFsdGhSaW5nKHNjb3JlKTsKICB9IGNhdGNoKGUpIHsKICAgIGNvbnNvbGUuZXJyb3IoZSk7CiAgfQp9CgpmdW5jdGlvbiBzZXRIZWFsdGhSaW5nKHBjdCkgewogIGNvbnN0IHJpbmcgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnaGVhbHRoLXJpbmcnKTsKICBjb25zdCBjaXJjdW1mZXJlbmNlID0gMjgzOwogIGNvbnN0IG9mZnNldCA9IGNpcmN1bWZlcmVuY2UgLSAocGN0IC8gMTAwKSAqIGNpcmN1bWZlcmVuY2U7CiAgcmluZy5zdHlsZS5zdHJva2VEYXNob2Zmc2V0ID0gb2Zmc2V0OwogIGNvbnN0IGNvbG9yID0gcGN0ID4gNzAgPyAndmFyKC0tZ3JlZW4pJyA6IHBjdCA+IDQwID8gJ3ZhcigtLXllbGxvdyknIDogJ3ZhcigtLXJlZCknOwogIHJpbmcuc3R5bGUuc3Ryb2tlID0gY29sb3I7CiAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2hlYWx0aC1wY3QnKS50ZXh0Q29udGVudCA9IHBjdCArICclJzsKICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnaGVhbHRoLXBjdCcpLnN0eWxlLmNvbG9yID0gY29sb3I7CiAgY29uc3QgdGV4dHMgPSBbJ9Ca0KDQmNCi0JjQp9Cd0J4nLCAn0KPQk9Cg0J7Ql9CQJywgJ9Cd0J7QoNCc0JAnLCAn0J7QotCb0JjQp9Cd0J4nLCAn0JjQlNCV0JDQm9Cs0J3QniddOwogIGNvbnN0IGlkeCA9IE1hdGgubWluKDQsIE1hdGguZmxvb3IocGN0IC8gMjEpKTsKICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnaGVhbHRoLXRleHQnKS50ZXh0Q29udGVudCA9IHRleHRzW2lkeF07Cn0KCmZ1bmN0aW9uIHVwZGF0ZURQSShkcGkpIHsKICBpZiAoIWRwaSB8fCAhZHBpLnVwZGF0ZWRfYXQpIHJldHVybjsKICBjb25zdCBzY29yZSA9IGRwaS5zY29yZSB8fCAwOwogIGNvbnN0IGVsID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2RwaS1zY29yZScpOwogIGVsLnRleHRDb250ZW50ID0gc2NvcmU7CiAgZWwuc3R5bGUuY29sb3IgPSBzY29yZSA8IDMwID8gJ3ZhcigtLWdyZWVuKScgOiBzY29yZSA8IDYwID8gJ3ZhcigtLXllbGxvdyknIDogJ3ZhcigtLXJlZCknOwogIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdkcGktYmFyJykuc3R5bGUud2lkdGggPSBzY29yZSArICclJzsKCiAgY29uc3Qgc3RhdHVzZXMgPSBbJ9Cn0JjQodCi0J4g4oCUIERQSSDQndCVINCe0JHQndCQ0KDQo9CW0JXQnScsICfQodCb0JDQkdCe0JUg0JLQnNCV0KjQkNCi0JXQm9Cs0KHQotCS0J4nLCAn0KPQnNCV0KDQldCd0J3QntCVINCX0JDQnNCV0JTQm9CV0J3QmNCVJywgJ9Ch0JjQm9Cs0J3QkNCvINCR0JvQntCa0JjQoNCe0JLQmtCQJ107CiAgY29uc3QgaWR4ID0gc2NvcmUgPCAyNSA/IDAgOiBzY29yZSA8IDUwID8gMSA6IHNjb3JlIDwgNzUgPyAyIDogMzsKICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnZHBpLXN0YXR1cy10ZXh0JykudGV4dENvbnRlbnQgPSBzdGF0dXNlc1tpZHhdOwoKICBjb25zdCBkZXQgPSBkcGkuZGV0YWlscyB8fCB7fTsKICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnZHBpLWJsb2NrZWQnKS50ZXh0Q29udGVudCA9IGRldC5hdmdfYmxvY2tlZF9tcyA/IE1hdGgucm91bmQoZGV0LmF2Z19ibG9ja2VkX21zKSA6ICfigJQnOwogIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdkcGktZGlyZWN0JykudGV4dENvbnRlbnQgID0gZGV0LmF2Z19kaXJlY3RfbXMgID8gTWF0aC5yb3VuZChkZXQuYXZnX2RpcmVjdF9tcykgIDogJ+KAlCc7CiAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2RwaS10aW1lb3V0cycpLnRleHRDb250ZW50ID0gZGV0LmJsb2NrZWRfdGltZW91dHMgPz8gJ+KAlCc7CiAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2RwaS11cGRhdGVkJykudGV4dENvbnRlbnQgID0gZHBpLnVwZGF0ZWRfYXQgPyBkcGkudXBkYXRlZF9hdC5zbGljZSgxMSwxOSkgOiAn4oCUJzsKfQoKYXN5bmMgZnVuY3Rpb24gcmVmcmVzaERQSSgpIHsKICBhd2FpdCBhcGkoJy9hcGkvZHBpL3JlZnJlc2gnLCAnUE9TVCcpOwogIHNldFRpbWVvdXQobG9hZFN0YXR1cywgMzAwMCk7Cn0KCi8vIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAovLyBMaW5rcyAmIFFSCi8vIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApsZXQgbGlua3MgPSB7fTsKbGV0IHFyUmVuZGVyZWQgPSBmYWxzZTsKCmFzeW5jIGZ1bmN0aW9uIGxvYWRMaW5rcygpIHsKICB0cnkgewogICAgbGlua3MgPSBhd2FpdCBhcGkoJy9hcGkvbGlua3MnKTsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsaW5rLXRjcC10ZXh0JykudGV4dENvbnRlbnQgID0gbGlua3MudGNwOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xpbmstZ3JwYy10ZXh0JykudGV4dENvbnRlbnQgPSBsaW5rcy5ncnBjOwogICAgcmVuZGVyUVIoKTsKICB9IGNhdGNoKGUpIHsKICAgIGNvbnNvbGUuZXJyb3IoZSk7CiAgfQp9CgpmdW5jdGlvbiByZW5kZXJRUigpIHsKICBpZiAoIWxpbmtzLnRjcCkgcmV0dXJuOwogIFsndGNwJywnZ3JwYyddLmZvckVhY2godCA9PiB7CiAgICBjb25zdCBlbCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdxci0nICsgdCk7CiAgICBlbC5pbm5lckhUTUwgPSAnJzsKICAgIG5ldyBRUkNvZGUoZWwsIHsKICAgICAgdGV4dDogbGlua3NbdF0sCiAgICAgIHdpZHRoOiAxNDQsIGhlaWdodDogMTQ0LAogICAgICBjb2xvckRhcms6ICcjMDAwMDAwJywgY29sb3JMaWdodDogJyNmZmZmZmYnLAogICAgICBjb3JyZWN0TGV2ZWw6IFFSQ29kZS5Db3JyZWN0TGV2ZWwuTQogICAgfSk7CiAgfSk7Cn0KCmZ1bmN0aW9uIGNvcHlMaW5rKHR5cGUpIHsKICBjb25zdCB0ZXh0ID0gbGlua3NbdHlwZV07CiAgaWYgKCF0ZXh0KSByZXR1cm47CiAgbmF2aWdhdG9yLmNsaXBib2FyZC53cml0ZVRleHQodGV4dCkudGhlbigoKSA9PiBzaG93VG9hc3QoKSk7Cn0KCmZ1bmN0aW9uIHNob3dUb2FzdCgpIHsKICBjb25zdCB0ID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3RvYXN0Jyk7CiAgdC5jbGFzc0xpc3QuYWRkKCdzaG93Jyk7CiAgc2V0VGltZW91dCgoKSA9PiB0LmNsYXNzTGlzdC5yZW1vdmUoJ3Nob3cnKSwgMjAwMCk7Cn0KCi8vIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAovLyBUYWJzCi8vIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApmdW5jdGlvbiBzd2l0Y2hUYWIobmFtZSkgewogIGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJy50YWItcGFuZScpLmZvckVhY2gocCA9PiBwLmNsYXNzTGlzdC5yZW1vdmUoJ2FjdGl2ZScpKTsKICBkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCcudGFicyAudGFiLWJ0bicpLmZvckVhY2goYiA9PiBiLmNsYXNzTGlzdC5yZW1vdmUoJ2FjdGl2ZScpKTsKICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgndGFiLScgKyBuYW1lKS5jbGFzc0xpc3QuYWRkKCdhY3RpdmUnKTsKICBldmVudC50YXJnZXQuY2xhc3NMaXN0LmFkZCgnYWN0aXZlJyk7Cn0KCmxldCBjdXJyZW50TG9nVGFiID0gJ2FjY2Vzcyc7CmxldCBsb2dzRGF0YSA9IHt9OwoKZnVuY3Rpb24gc3dpdGNoTG9nVGFiKG5hbWUpIHsKICBjdXJyZW50TG9nVGFiID0gbmFtZTsKICBkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCcudGFicycpWzFdLnF1ZXJ5U2VsZWN0b3JBbGwoJy50YWItYnRuJykuZm9yRWFjaChiID0+IGIuY2xhc3NMaXN0LnJlbW92ZSgnYWN0aXZlJykpOwogIGV2ZW50LnRhcmdldC5jbGFzc0xpc3QuYWRkKCdhY3RpdmUnKTsKICByZW5kZXJMb2dzKCk7Cn0KCmFzeW5jIGZ1bmN0aW9uIGxvYWRMb2dzKCkgewogIHRyeSB7CiAgICBsb2dzRGF0YSA9IGF3YWl0IGFwaSgnL2FwaS9sb2dzP2xpbmVzPTgwJyk7CiAgICByZW5kZXJMb2dzKCk7CiAgfSBjYXRjaChlKSB7fQp9CgpmdW5jdGlvbiByZW5kZXJMb2dzKCkgewogIGNvbnN0IGJveCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsb2ctYm94Jyk7CiAgY29uc3QgbGluZXMgPSBsb2dzRGF0YVtjdXJyZW50TG9nVGFiXSB8fCBbXTsKICBpZiAoIWxpbmVzLmxlbmd0aCkgeyBib3gudGV4dENvbnRlbnQgPSAnLy8g0J3QtdGCINC30LDQv9C40YHQtdC5JzsgcmV0dXJuOyB9CiAgYm94LmlubmVySFRNTCA9IGxpbmVzLm1hcChsID0+IHsKICAgIGNvbnN0IGNscyA9IGwuaW5jbHVkZXMoJ1tFcnJvcl0nKSB8fCBsLmluY2x1ZGVzKCdlcnJvcicpID8gJ2VycicKICAgICAgICAgICAgICA6IGwuaW5jbHVkZXMoJ1tXYXJuaW5nXScpID8gJ3dhcm4nIDogJyc7CiAgICByZXR1cm4gYDxkaXYgY2xhc3M9IiR7Y2xzfSI+JHtlc2NIdG1sKGwpfTwvZGl2PmA7CiAgfSkuam9pbignJyk7CiAgYm94LnNjcm9sbFRvcCA9IGJveC5zY3JvbGxIZWlnaHQ7Cn0KCmZ1bmN0aW9uIGVzY0h0bWwocykgewogIHJldHVybiBzLnJlcGxhY2UoLyYvZywnJmFtcDsnKS5yZXBsYWNlKC88L2csJyZsdDsnKS5yZXBsYWNlKC8+L2csJyZndDsnKTsKfQoKLy8g4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACi8vIEVtZXJnZW5jeSBPcmJpdAovLyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKYXN5bmMgZnVuY3Rpb24gZW1lcmdlbmN5T3JiaXQoKSB7CiAgY29uc3QgYnRuID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ29yYml0LWJ0bicpOwogIGNvbnN0IHJlcyA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdvcmJpdC1yZXN1bHQnKTsKICBidG4uY2xhc3NMaXN0LmFkZCgnbG9hZGluZycpOwogIGJ0bi5kaXNhYmxlZCA9IHRydWU7CiAgYnRuLnRleHRDb250ZW50ID0gJ+KPsyDQktCr0J/QntCb0J3Qr9CV0KLQodCvINCg0J7QotCQ0KbQmNCv4oCmJzsKICByZXMuc3R5bGUuZGlzcGxheSA9ICdub25lJzsKCiAgdHJ5IHsKICAgIGNvbnN0IGRhdGEgPSBhd2FpdCBhcGkoJy9hcGkvcm90YXRlJywgJ1BPU1QnKTsKICAgIGJ0bi50ZXh0Q29udGVudCA9ICfinIUg0J7QoNCR0JjQotCQINCh0JzQldCd0JXQndCQJzsKICAgIHJlcy5zdHlsZS5kaXNwbGF5ID0gJ2Jsb2NrJzsKICAgIHJlcy5pbm5lckhUTUwgPSBgCiAgICAgIC8vINCg0J7QotCQ0KbQmNCvINCS0KvQn9Ce0JvQndCV0J3QkDxicj4KICAgICAgTkVXX1NOSSAgICAgIDogJHtkYXRhLm5ld19zbml9PGJyPgogICAgICBORVdfU0hPUlRfSUQgOiAke2RhdGEubmV3X3Nob3J0X2lkfTxicj4KICAgICAgVElNRVNUQU1QICAgIDogJHtkYXRhLnJvdGF0ZWRfYXR9PGJyPgogICAgYDsKICAgIGxpbmtzID0geyB0Y3A6IGRhdGEudGNwX2xpbmssIGdycGM6IGRhdGEuZ3JwY19saW5rIH07CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbGluay10Y3AtdGV4dCcpLnRleHRDb250ZW50ICA9IGRhdGEudGNwX2xpbms7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbGluay1ncnBjLXRleHQnKS50ZXh0Q29udGVudCA9IGRhdGEuZ3JwY19saW5rOwogICAgcmVuZGVyUVIoKTsKICAgIGF3YWl0IGxvYWRTdGF0dXMoKTsKCiAgICBzZXRUaW1lb3V0KCgpID0+IHsKICAgICAgYnRuLnRleHRDb250ZW50ID0gJ/CfmoAgRU1FUkdFTkNZIE9SQklUJzsKICAgICAgYnRuLmRpc2FibGVkID0gZmFsc2U7CiAgICAgIGJ0bi5jbGFzc0xpc3QucmVtb3ZlKCdsb2FkaW5nJyk7CiAgICB9LCA1MDAwKTsKICB9IGNhdGNoKGUpIHsKICAgIGJ0bi50ZXh0Q29udGVudCA9ICfinYwg0J7QqNCY0JHQmtCQIOKAlCDQn9Ce0JLQotCe0KAg0KfQldCg0JXQlyA10YEnOwogICAgc2V0VGltZW91dCgoKSA9PiB7CiAgICAgIGJ0bi50ZXh0Q29udGVudCA9ICfwn5qAIEVNRVJHRU5DWSBPUkJJVCc7CiAgICAgIGJ0bi5kaXNhYmxlZCA9IGZhbHNlOwogICAgICBidG4uY2xhc3NMaXN0LnJlbW92ZSgnbG9hZGluZycpOwogICAgfSwgNTAwMCk7CiAgfQp9Cjwvc2NyaXB0Pgo8L2JvZHk+CjwvaHRtbD4K"   "${INSTALL_DIR}/frontend/index.html"

# requirements.txt
cat > "${INSTALL_DIR}/backend/requirements.txt" << 'REQEOF'
fastapi==0.111.0
uvicorn[standard]==0.30.1
httpx==0.27.0
qrcode[pil]==7.4.2
apscheduler==3.10.4
psutil==5.9.8
Pillow==10.3.0
pydantic==2.7.1
REQEOF
ok "Создан: backend/requirements.txt"

# Dockerfile — запускаем от root чтобы не было проблем с правами на volume
cat > "${INSTALL_DIR}/backend/Dockerfile" << 'DKREOF'
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl gcc && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
RUN mkdir -p /app/data /etc/xray /var/log/xray
EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
DKREOF
ok "Создан: backend/Dockerfile"

# Начальный конфиг xray
cat > "${INSTALL_DIR}/xray_config/config.json" << 'XCFG'
{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom"}]}
XCFG
ok "Создан: xray_config/config.json"

# ════════════════════════════════════════════════════════════════════
step "СОЗДАНИЕ .env"

cat > "${INSTALL_DIR}/.env" << ENVEOF
ECLIPSE_PASSWORD=${UI_PASSWORD}
SERVER_IP=${SERVER_IP}
PRIVATE_KEY=${PRIVATE_KEY}
PUBLIC_KEY=${PUBLIC_KEY}
DATA_PATH=/app/data
ENVEOF
chmod 600 "${INSTALL_DIR}/.env"
ok ".env создан: ${INSTALL_DIR}/.env  (права 600)"

# Права на папки которые монтируются в контейнер
chmod 777 "${INSTALL_DIR}/data"
chmod 777 "${INSTALL_DIR}/xray_config"
chmod 777 "${INSTALL_DIR}/xray_logs"
ok "Права на data/xray_config/xray_logs: OK"

# ════════════════════════════════════════════════════════════════════
step "ЗАПУСК DOCKER СТЕКА"

cd "${INSTALL_DIR}"

run_spin "Pull: teddysun/xray"       docker pull teddysun/xray:latest
run_spin "Pull: nginx:alpine"        docker pull nginx:alpine
run_spin "Pull: python:3.12-slim"    docker pull python:3.12-slim
run_spin "Build: backend"            docker compose --env-file .env build --no-cache

inf "Запуск контейнеров…"
docker compose --env-file .env up -d >>$LOG 2>&1 \
  || { echo ""; tail -30 "$LOG" | sed 's/^/    /'; die "docker compose up завершился с ошибкой"; }
ok "Контейнеры запущены"

# ════════════════════════════════════════════════════════════════════
step "ПРОВЕРКА ЗАПУСКА (до 90 секунд)"

echo ""
ALL_OK=false

for attempt in $(seq 1 18); do
  sleep 5
  SECS=$((attempt*5))

  ST_X=$(docker inspect --format='{{.State.Status}}' eclipse_xray    2>/dev/null || echo "—")
  ST_B=$(docker inspect --format='{{.State.Status}}' eclipse_backend 2>/dev/null || echo "—")
  ST_N=$(docker inspect --format='{{.State.Status}}' eclipse_nginx   2>/dev/null || echo "—")

  H_API=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:8080/health 2>/dev/null || echo "—")
  H_WEB=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1/ 2>/dev/null || echo "—")

  xi="${ST_X}"; [[ "$ST_X" == "running" ]] && xi="${G}✔${NC}"
  bi="${ST_B}"; [[ "$ST_B" == "running" ]] && bi="${G}✔${NC}"
  ni="${ST_N}"; [[ "$ST_N" == "running" ]] && ni="${G}✔${NC}"
  ai="${H_API}"; [[ "$H_API" == "200" ]] && ai="${G}200✔${NC}"
  wi="${H_WEB}"; [[ "$H_WEB" == "200" ]] && wi="${G}200✔${NC}"

  printf "  ${DIM}[%3ds]${NC}  xray=%-12b  backend=%-12b  nginx=%-12b  api=%-10b  web=%b\n" \
    "$SECS" "$xi" "$bi" "$ni" "$ai" "$wi"

  if [[ "$ST_X" == "running" && "$ST_B" == "running" && "$ST_N" == "running" \
     && "$H_API" == "200" && "$H_WEB" == "200" ]]; then
    ALL_OK=true; break
  fi
done

echo ""
# Детальный статус
for label_cont in "Xray-core:eclipse_xray" "FastAPI:eclipse_backend" "Nginx:eclipse_nginx"; do
  label="${label_cont%%:*}"; cont="${label_cont##*:}"
  st=$(docker inspect --format='{{.State.Status}}' "$cont" 2>/dev/null || echo "не найден")
  if [[ "$st" == "running" ]]; then
    ok "${label}: ${G}${B}RUNNING${NC}"
  else
    warn "${label}: ${R}${B}${st}${NC}"
    echo -e "  ${DIM}  Логи ${cont}:${NC}"
    docker logs --tail 20 "$cont" 2>&1 | sed 's/^/      /' || true
  fi
done

FA=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:8080/health 2>/dev/null || echo "—")
FW=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1/           2>/dev/null || echo "—")
[[ "$FA" == "200" ]] && ok "API /health: ${G}${B}HTTP 200 ✔${NC}" || warn "API: HTTP ${FA}"
[[ "$FW" == "200" ]] && ok "Веб-интерфейс: ${G}${B}HTTP 200 ✔${NC}" || warn "Веб: HTTP ${FW}"

# ════════════════════════════════════════════════════════════════════
# ИТОГ
# ════════════════════════════════════════════════════════════════════
echo ""
if $ALL_OK; then
  echo -e "${G}${B}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${G}${B}║          ✅  ECLIPSE VPN УСПЕШНО УСТАНОВЛЕН!           ║${NC}"
  echo -e "${G}${B}╚════════════════════════════════════════════════════════╝${NC}"
else
  echo -e "${Y}${B}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${Y}${B}║    ⚠  УСТАНОВКА ЗАВЕРШЕНА — ПРОВЕРЬТЕ ПРЕДУПРЕЖДЕНИЯ  ║${NC}"
  echo -e "${Y}${B}╚════════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "${Y}${B}  ┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${Y}${B}  │              КАК ЗАЙТИ В ВЕБ-ИНТЕРФЕЙС              │${NC}"
echo -e "${Y}${B}  └─────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  Открой в браузере:"
echo ""
echo -e "  ${B}${C}     ➜  http://${SERVER_IP}/${NC}"
echo ""
echo -e "  Логин:   ${B}eclipse${NC}"
echo -e "  Пароль:  ${B}[введённый при установке]${NC}"
echo ""
echo -e "${B}  ┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${B}  │              ПАРАМЕТРЫ VPN                          │${NC}"
echo -e "${B}  └─────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  Сервер:    ${C}${SERVER_IP}${NC}"
echo -e "  TCP  443:  ${C}VLESS + Reality  (xtls-rprx-vision, Safari)${NC}"
echo -e "  gRPC 8443: ${C}VLESS + Reality  (multiPath, Chrome)${NC}"
echo -e "  PublicKey: ${C}${PUBLIC_KEY}${NC}"
echo ""
echo -e "  ${DIM}QR-коды и VLESS-ссылки → в веб-интерфейсе${NC}"
echo ""
echo -e "${B}  ┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${B}  │              УПРАВЛЕНИЕ                             │${NC}"
echo -e "${B}  └─────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${C}cd ${INSTALL_DIR}${NC}"
echo -e "  Статус:     ${C}docker compose ps${NC}"
echo -e "  Логи:       ${C}docker compose logs -f${NC}"
echo -e "  Перезапуск: ${C}docker compose restart${NC}"
echo -e "  Остановить: ${C}docker compose down${NC}"
echo ""
echo -e "  .env файл:     ${C}cat ${INSTALL_DIR}/.env${NC}"
echo -e "  Лог установки: ${C}cat ${LOG}${NC}"
echo ""

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo -e "${Y}${B}  Предупреждения:${NC}"
  for e in "${ERRORS[@]}"; do echo -e "  ${Y}•${NC} ${e}"; done
  echo ""
fi

echo -e "${G}${B}════════════════════════════════════════════════════════${NC}"
echo ""
