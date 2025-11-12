#!/usr/bin/env bash
# Авторазвёртывание n8n с Traefik и Let's Encrypt на Ubuntu 22.04+
set -euo pipefail

### === НАСТРОЙКИ ===
DOMAIN_NAME="example.com"        # ← базовый домен (например, example.com)
SUBDOMAIN="n8n"                  # ← поддомен, на котором будет доступен n8n
SSL_EMAIL="user@example.com"     # ← email для Let's Encrypt
GENERIC_TIMEZONE="Europe/Moscow" # ← часовой пояс, напр. "Europe/Moscow"
STACK_DIR="/opt/n8n"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
ENV_FILE="${STACK_DIR}/.env"

if [[ -n "${SUBDOMAIN}" ]]; then
  FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN_NAME}"
else
  FULL_DOMAIN="${DOMAIN_NAME}"
fi

### === ПРОВЕРКИ ===
if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root: sudo bash $0"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y curl
fi

echo "[1/8] Проверяю DNS → ${FULL_DOMAIN} должен указывать на этот сервер…"
PUB_IP="$(curl -fsSL https://api.ipify.org || true)"
DNS_IP="$(getent ahosts "${FULL_DOMAIN}" | awk 'NR==1{print $1}' || true)"
echo "Публичный IP: ${PUB_IP:-unknown}; DNS(${FULL_DOMAIN}): ${DNS_IP:-unknown}"
if [[ -n "${PUB_IP}" && -n "${DNS_IP}" && "${PUB_IP}" != "${DNS_IP}" ]]; then
  echo "⚠️  ВНИМАНИЕ: ${FULL_DOMAIN} сейчас не указывает на ${PUB_IP}. Let's Encrypt может не сработать."
fi

echo "[2/8] Устанавливаю Docker Engine…"
if ! command -v docker >/dev/null 2>&1; then
  TMP_DIR="$(mktemp -d)"
  curl -fsSL https://get.docker.com -o "${TMP_DIR}/get-docker.sh"
  sh "${TMP_DIR}/get-docker.sh"
  rm -rf "${TMP_DIR}"
  systemctl enable --now docker
else
  echo "Docker уже установлен."
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "[3/8] Добавляю docker compose-plugin…"
  apt-get update -y
  apt-get install -y docker-compose-plugin
else
  echo "[3/8] Docker Compose уже доступен."
fi

echo "[4/8] Готовлю каталог стека: ${STACK_DIR}"
mkdir -p "${STACK_DIR}/local-files"
cd "${STACK_DIR}"

echo "[5/8] Создаю .env с параметрами развертывания…"
cat > "${ENV_FILE}" <<EOF
# === ОСНОВНЫЕ НАСТРОЙКИ ===
DOMAIN_NAME=${DOMAIN_NAME}
SUBDOMAIN=${SUBDOMAIN}
GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
SSL_EMAIL=${SSL_EMAIL}
EOF

echo "[6/8] Создаю docker-compose.yml…"
cat > "${COMPOSE_FILE}" <<'YML'
services:
  traefik:
    image: "traefik:latest"
    restart: always
    command:
      - "--api=true"
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--log.level=INFO"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro

  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    restart: always
    depends_on:
      - traefik
    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n-http.rule=Host(`${SUBDOMAIN}.${DOMAIN_NAME}`)
      - traefik.http.routers.n8n-http.entrypoints=web
      - traefik.http.routers.n8n-http.middlewares=n8n-redirect
      - traefik.http.middlewares.n8n-redirect.redirectscheme.scheme=https
      - traefik.http.middlewares.n8n-redirect.redirectscheme.permanent=true
      - traefik.http.routers.n8n.rule=Host(`${SUBDOMAIN}.${DOMAIN_NAME}`)
      - traefik.http.routers.n8n.entrypoints=websecure
      - traefik.http.routers.n8n.tls=true
      - traefik.http.routers.n8n.tls.certresolver=letsencrypt
      - traefik.http.services.n8n.loadbalancer.server.port=5678
      - traefik.http.middlewares.n8n-headers.headers.sslredirect=true
      - traefik.http.middlewares.n8n-headers.headers.stsseconds=31536000
      - traefik.http.middlewares.n8n-headers.headers.browserxssfilter=true
      - traefik.http.middlewares.n8n-headers.headers.contenttypenosniff=true
      - traefik.http.middlewares.n8n-headers.headers.forcestsheader=true
      - traefik.http.middlewares.n8n-headers.headers.stsincludesubdomains=true
      - traefik.http.middlewares.n8n-headers.headers.stspreload=true
      - traefik.http.routers.n8n.middlewares=n8n-headers
    environment:
      - N8N_HOST=${SUBDOMAIN}.${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${SUBDOMAIN}.${DOMAIN_NAME}/
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files

volumes:
  n8n_data:
  traefik_data:
YML

echo "[7/8] Открываю firewall (если UFW установлен)…"
if command -v ufw >/dev/null 2>&1; then
  ufw allow 80/tcp   || true
  ufw allow 443/tcp  || true
fi

echo "[8/8] Запускаю стек n8n…"
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d

echo "Проверяю состояние контейнеров…"
docker compose -f "${COMPOSE_FILE}" ps
echo
echo "✅ Готово! Открой https://${FULL_DOMAIN}"
echo ""
echo "📝 Примечания:"
echo "   - Получение SSL-сертификата может занять 1-2 минуты"
echo "   - Если видите ошибку 404 или нет сертификата, проверьте логи:"
echo "     docker compose -f ${COMPOSE_FILE} logs traefik"
echo "     docker compose -f ${COMPOSE_FILE} logs n8n"
echo "   - Убедитесь, что DNS ${FULL_DOMAIN} указывает на ${PUB_IP:-этот сервер}"
echo "   - Порты 80 и 443 должны быть открыты в firewall"
