# 🔄 Reverse Proxy (Nginx + HTTPS)

Безопасная раздача подписок через Nginx с SSL-шифрованием.

## Содержание

1. [Зачем нужен Reverse Proxy](#1-зачем-нужен-reverse-proxy)
2. [Установка Nginx и Certbot](#2-установка-nginx-и-certbot)
3. [Конфигурация Nginx](#3-конфигурация-nginx)
4. [Получение SSL-сертификата](#4-получение-ssl-сертификата)
5. [Закрытие прямого порта подписки](#5-закрытие-прямого-порта-подписки)
6. [Проверка работы](#6-проверка-работы)
7. [Автопродление сертификата](#7-автопродление-сертификата)
8. [Диагностика проблем](#8-диагностика-проблем)

---

## 1. Зачем нужен Reverse Proxy

**Было (небезопасно):**

```
Клиент → HTTP :2097/sub/... → Subscription Service
                                ↑ незашифрованный трафик
                                ↑ стандартный путь /sub/
```

**Стало (безопасно):**

```
Клиент → HTTPS :2096/уникальный_путь/... → Nginx → 127.0.0.1:2097
         ↑ зашифрованный трафик              ↑ проверяет TLS
         ↑ нестандартный путь                ↑ проксирует внутрь
```

**Преимущества:**
- Трафик зашифрован (HTTPS)
- Прямой порт подписки (2097) закрыт снаружи
- Можно добавить rate limiting, фильтрацию
- Сайт-заглушка на основном пути маскирует наличие подписки

---

## 2. Установка Nginx и Certbot

```bash
apt update
apt install nginx certbot python3-certbot-nginx -y
```

Проверить, что Nginx запущен:

```bash
systemctl status nginx
```

---

## 3. Конфигурация Nginx

### Создание конфига:

```bash
nano /etc/nginx/sites-available/subscription
```

### Содержимое конфига:

```nginx
server {
    listen 2096 ssl;
    server_name <IP_или_домен>;

    # SSL-сертификаты (будут добавлены certbot автоматически)
    ssl_certificate     /etc/letsencrypt/live/<домен>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<домен>/privkey.pem;

    # Настройки SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Проксирование подписки
    location /<уникальный_URI_путь>/ {
        proxy_pass http://127.0.0.1:2097;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Таймауты
        proxy_connect_timeout 30s;
        proxy_read_timeout 30s;
        proxy_send_timeout 30s;
    }

    # Сайт-заглушка (маскировка)
    location / {
        root /var/www/html;
        index index.html;
    }
}
```

### Создание сайта-заглушки:

```bash
nano /var/www/html/index.html
```

```html
<!DOCTYPE html>
<html>
<head><title>Site</title></head>
<body><h1>Welcome</h1></body>
</html>
```

### Активация сайта:

```bash
ln -s /etc/nginx/sites-available/subscription /etc/nginx/sites-enabled/
nginx -t
systemctl restart nginx
```

---

## 4. Получение SSL-сертификата

### Если есть домен:

```bash
certbot --nginx -d <ваш_домен>
```

Certbot автоматически:
1. Подтвердит владение доменом
2. Выпустит сертификат Let's Encrypt
3. Обновит конфиг Nginx
4. Настроит автоматическое продление

### Если домена нет (сертификат на IP):

Для IP-адреса Let's Encrypt сертификаты не выпускает. Варианты:

1. **Купить домен** (рекомендуется) — от $1/год
2. **Самоподписанный сертификат** (не рекомендуется для прода)
3. **ZeroSSL** — выпускает сертификаты на IP (бесплатно, 90 дней)

---

## 5. Закрытие прямого порта подписки

После настройки Nginx прямой порт подписки больше не нужен снаружи:

```bash
# Закрыть порт в UFW
ufw delete allow 2097/tcp

# Проверить, что порт слушает только localhost
ss -lntp | grep 2097
# Должно быть: 127.0.0.1:2097
```

Если порт слушает `0.0.0.0:2097`, привязать к localhost:

В панели 3x-ui: **Настройки панели → Подписка → Прослушивание IP** → `127.0.0.1`

```bash
systemctl restart x-ui
ss -lntp | grep 2097
```

---

## 6. Проверка работы

```bash
# Nginx конфиг валидный?
nginx -t

# Nginx слушает порт 2096?
ss -lntp | grep 2096

# Сайт открывается?
curl -I https://<IP>:2096/

# Подписка проксируется?
curl -I https://<IP>:2096/<URI_путь>/<subId>

# Сертификат валидный?
openssl s_client -connect <IP>:2096 -servername <IP> </dev/null 2>/dev/null | openssl x509 -noout -dates
```

---

## 7. Автопродление сертификата

Certbot автоматически создаёт systemd timer:

```bash
# Проверить статус таймера
systemctl status certbot.timer

# Проверить расписание
systemctl list-timers | grep certbot

# Тестовый запуск продления
certbot renew --dry-run
```

После продления сертификата Nginx нужно перезагрузить. Certbot делает это автоматически (хук в конфиге).

Если хук не сработал:

```bash
certbot renew --deploy-hook "systemctl restart nginx"
```

---

## 8. Диагностика проблем

### Nginx не запускается

```bash
nginx -t                  # проверить конфиг
journalctl -u nginx -n 50 # посмотреть логи
ss -tlnp | grep :2096     # порт занят?
```

### Сертификат не выпускается

```bash
# Проверить, что домен указывает на сервер
dig <домен> +short

# Проверить доступность порта 80
curl -I http://<домен>/.well-known/acme-challenge/

# Логи certbot
certbot --nginx -d <домен> --dry-run
```

### Подписка возвращает 502

```bash
# x-ui запущен?
systemctl status x-ui

# Сервис подписки слушает?
ss -lntp | grep 2097

# Прокси работает напрямую?
curl -I http://127.0.0.1:2097/<URI_путь>/<subId>
```

### Срок сертификата истекает

```bash
# Проверить дату
openssl s_client -connect <IP>:2096 -servername <IP> </dev/null 2>/dev/null | openssl x509 -noout -dates

# Принудительное продление
certbot renew --force-renewal
```

---

## Схема запроса

```
Браузер/Клиент
    │
    │ HTTPS :2096/уникальный_путь/subId
    ▼
┌─────────────────┐
│     Nginx        │
│  Порт 2096 (TLS) │
│                 │
│ Проверка TLS    │
│ Проксирование   │──→ http://127.0.0.1:2097/уникальный_путь/subId
└─────────────────┘              │
                                  ▼
                        ┌─────────────────┐
                        │  x-ui (внутр.)   │
                        │  Порт 2097       │
                        │  Subscription    │
                        │  Service         │
                        └─────────────────┘
```

---

*Все IP, порты и пути заменены на плейсхолдеры.*