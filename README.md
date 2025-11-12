<h1>n8n Auto-Install</h1>

Автоматическая установка self-hosted версии <a href="https://n8n.io">n8n</a> в Docker на Ubuntu 22.04+ за несколько минут.
Скрипт разворачивает Traefik в качестве обратного прокси, настраивает HTTPS от Let's Encrypt и запускает n8n в production-режиме.

<h2>Возможности</h2>

 - Проверка DNS и подготовка окружения
 - Установка Docker и Docker Compose (через официальный установщик)
 - Создание `.env` и `docker-compose.yml` c Traefik + n8n
 - Автоматический выпуск SSL-сертификата для нужного домена
 - Подготовка каталога для локальных файлов n8n

<h2>Требования</h2>

 - ОС: Ubuntu 22.04+
 - Права: root или sudo
 - Домен/поддомен, указывающий на IP вашего сервера (например, n8n.example.com)

<h2>Установка</h2>

<h3>1. Скачайте установочный скрипт</h3>

```
wget https://raw.githubusercontent.com/darky623/n8n_autoinstall/refs/heads/main/install_n8n.sh
```

<h3>2. Настройте переменные</h3>

Откройте файл в редакторе:

```
nano install_n8n.sh
```

В начале файла укажите свои значения:

```
DOMAIN_NAME="example.com"
SUBDOMAIN="n8n"
SSL_EMAIL="user@example.com"
GENERIC_TIMEZONE="Europe/Moscow"
```

> Если хотите использовать домен без поддомена, оставьте `SUBDOMAIN=""`.

Сохраните изменения (Ctrl + X → Y → Enter).

<h3>3. Запустите установку</h3>

```
sudo bash install_n8n.sh
```

<h2>Что делает скрипт</h2>

 - проверяет привязку DNS выбранного домена;
 - устанавливает Docker и docker compose-plugin (если не установлены);
 - создаёт каталог `/opt/n8n` с подготовленным `.env`;
 - генерирует `docker-compose.yml` для Traefik и n8n;
 - открывает порты 80/443 (при наличии UFW);
 - запускает стек `docker compose up -d`.

<h2>После установки</h2>

Через несколько минут n8n будет доступен по адресу:

```
https://<ваш_поддомен>.<ваш_домен>
```

Если сертификат не выпустился, убедитесь, что DNS-запись указывает на ваш сервер, а порты 80 и 443 открыты. Чтобы просмотреть статус контейнеров, выполните:

```
cd /opt/n8n
sudo docker compose ps
```
