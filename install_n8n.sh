#!/bin/bash

set -e

### -----------------------------
### CONFIG
### -----------------------------

DOMAIN="yourdomain.com"   # <=== УКАЖИ СВОЙ ДОМЕН
N8N_PORT="5678"
POSTGRES_DB="n8n"
POSTGRES_USER="n8n"
POSTGRES_PASSWORD="$(openssl rand -hex 16)"
POSTGRES_PORT="5432"

DATA_DIR="/opt/n8n"
ENV_FILE="$DATA_DIR/.env"

### -----------------------------
echo "=== Установка зависимостей (Docker, Certbot, Nginx)… ==="
### -----------------------------

apt update
apt install -y ca-certificates curl gnupg lsb-release nginx certbot python3-certbot-nginx

### -----------------------------
echo "=== Установка Docker ==="
### -----------------------------

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

### -----------------------------
echo "=== Создание директорий ==="
### -----------------------------

mkdir -p $DATA_DIR/postgres
mkdir -p $DATA_DIR/n8n

### -----------------------------
echo "=== Генерация .env ==="
### -----------------------------

cat > $ENV_FILE <<EOF
# Basic
DOMAIN=$DOMAIN
N8N_PORT=$N8N_PORT

# Postgres
DB_TYPE=postgresdb
DB_POSTGRESDB_DATABASE=$POSTGRES_DB
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=$POSTGRES_PORT
DB_POSTGRESDB_USER=$POSTGRES_USER
DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD

# n8n
N8N_BASIC_AUTH_ACTIVE=false
N8N_PROTOCOL=https
N8N_HOST=$DOMAIN
WEBHOOK_URL=https://$DOMAIN/
EOF

chmod 600 $ENV_FILE

### -----------------------------
echo "=== Создание docker-compose.yml ==="
### -----------------------------

cat > $DATA_DIR/docker-compose.yml <<EOF
services:

  postgres:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_DB: $POSTGRES_DB
      POSTGRES_USER: $POSTGRES_USER
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD
    volumes:
      - ./postgres:/var/lib/postgresql/data

  n8n:
    image: n8nio/n8n:latest
    restart: always
    env_file:
      - .env
    ports:
      - "127.0.0.1:5678:5678"
    depends_on:
      - postgres
    volumes:
      - ./n8n:/home/node/.n8n
EOF

### -----------------------------
echo "=== Запуск docker-compose ==="
### -----------------------------

cd $DATA_DIR
docker compose up -d

### -----------------------------
echo "=== Настройка Nginx reverse proxy ==="
### -----------------------------

cat > /etc/nginx/sites-available/n8n.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf /etc/nginx/sites-available/n8n.conf /etc/nginx/sites-enabled/n8n.conf
nginx -t && systemctl reload nginx

### -----------------------------
echo "=== Выпуск Let's Encrypt сертификата ==="
### -----------------------------

certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

### -----------------------------
echo "=== Добавляем systemd unit для автозапуска ==="
### -----------------------------

cat > /etc/systemd/system/n8n.service <<EOF
[Unit]
Description=n8n workflow automation
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=$DATA_DIR
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now n8n

### -----------------------------
echo "=== УСТАНОВКА ЗАВЕРШЕНА ==="
echo "Домен: https://$DOMAIN"
echo "Данные PostgreSQL:"
echo "  База: $POSTGRES_DB"
echo "  Пользователь: $POSTGRES_USER"
echo "  Пароль: $POSTGRES_PASSWORD"
### -----------------------------
