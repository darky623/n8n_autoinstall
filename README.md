n8n Автоустановка
=================

Скрипт `install_n8n.sh` автоматизирует развёртывание n8n на сервере с Ubuntu, настраивает Docker, Postgres, обратный прокси на Nginx и выпускает TLS‑сертификат Let's Encrypt.

## Требования

- Свежая Ubuntu 22.04/24.04 с root‑доступом или sudo.
- Порт 80 (HTTP) и 443 (HTTPS) должен быть открыт извне.
- Зарегистрированный домен, указывающий на IP сервера.
- Установленный `curl` и возможность выходить в интернет.

## Что делает скрипт

- Обновляет пакеты и ставит зависимости (`Docker`, `docker compose`, `Nginx`, `certbot`).
- Создаёт директории данных в `/opt/n8n`.
- Формирует `.env` с параметрами подключения к базе и хосту.
- Генерирует `docker-compose.yml` для контейнеров `postgres` и `n8n`.
- Запускает стек командой `docker compose up -d`.
- Настраивает Nginx как reverse proxy к `127.0.0.1:5678`.
- Выпускает сертификат Let’s Encrypt для указанного домена.
- Создаёт `systemd` unit `n8n.service` для автозапуска n8n.

## Переменные и настройка

Перед запуском отредактируйте блок «CONFIG» в начале скрипта:

| Переменная          | Описание                                  | Значение по умолчанию      |
|---------------------|-------------------------------------------|-----------------------------|
| `DOMAIN`            | Ваш домен (обязательно указать)          | `yourdomain.com`           |
| `N8N_PORT`          | Внутренний порт сервиса n8n              | `5678`                     |
| `POSTGRES_DB`       | Имя базы Postgres                        | `n8n`                      |
| `POSTGRES_USER`     | Пользователь базы                        | `n8n`                      |
| `POSTGRES_PASSWORD` | Пароль базы (генерируется автоматически) | случайный hex из `openssl` |
| `POSTGRES_PORT`     | Порт Postgres внутри docker сети         | `5432`                     |

Если нужны дополнительные параметры n8n, добавьте их в блок генерации `.env`.

## Запуск

1. Скачайте установочный скрипт
```
wget https://raw.githubusercontent.com/darky623/n8n_autoinstall/refs/heads/main/install_n8n.sh
```
3. Отредактируйте настройки
Откройте файл в nano:
```
nano install_n8n.sh
```
В начале файла укажите свои значения:
```
DOMAIN="n8n.ddns.net"
```
Сохраните и закройте файл (Ctrl + X -> Y -> Enter).

3. Запустите установку
```
sudo bash install_n8n.sh
```
После завершения скрипт выведет домен и данные для подключения к Postgres.

## Создаваемые файлы и пути

- `/.env` и `docker-compose.yml` в `/opt/n8n`.
- Данные Postgres: `/opt/n8n/postgres`.
- Данные n8n: `/opt/n8n/n8n`.
- Конфиг Nginx: `/etc/nginx/sites-available/n8n.conf` (симлинк в `sites-enabled`).
- Unit-файл: `/etc/systemd/system/n8n.service`.

## Управление сервисом

```bash
sudo systemctl status n8n
sudo systemctl restart n8n
sudo docker compose -f /opt/n8n/docker-compose.yml logs -f
```

## Обновление n8n

```bash
cd /opt/n8n
sudo docker compose pull
sudo systemctl restart n8n
```

## Типичные проблемы

- **Certbot не получает сертификат**: проверьте DNS записи домена и открыты ли порты 80/443.
- **Контейнер не стартует из-за порта**: убедитесь, что `5678` свободен на `localhost`.
- **n8n недоступен снаружи**: проверьте firewall (`ufw`, `iptables`), а также корректность конфигурации Nginx.

## Удаление

```bash
sudo systemctl stop n8n
sudo systemctl disable n8n
sudo docker compose -f /opt/n8n/docker-compose.yml down -v
sudo rm -rf /opt/n8n
sudo rm /etc/nginx/sites-available/n8n.conf /etc/nginx/sites-enabled/n8n.conf
sudo systemctl reload nginx
sudo rm /etc/systemd/system/n8n.service
sudo systemctl daemon-reload
```


