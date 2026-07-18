# 📖 Пошаговое руководство

Полный цикл настройки безопасной серверной инфраструктуры с нуля.

## Содержание

1. [Начальная настройка серверов](#1-начальная-настройка-серверов)
2. [Установка 3x-ui и Xray](#2-установка-3x-ui-и-xray)
3. [Настройка VLESS Reality](#3-настройка-vless-reality)
4. [Отключение парольной аутентификации SSH](#4-отключение-парольной-аутентификации-ssh)
5. [Скрытие панелей за SSH-туннелем](#5-скрытие-панелей-за-ssh-туннелем)
6. [Настройка подписки](#6-настройка-подписки)
7. [Настройка Reverse Proxy (Nginx + HTTPS)](#7-настройка-reverse-proxy-nginx--https)
8. [Каскадная маршрутизация RU → NL](#8-каскадная-маршрутизация-ru--nl)
9. [Файрвол и закрытие портов](#9-файрвол-и-закрытие-портов)
10. [Бэкапы и восстановление](#10-бэкапы-и-восстановление)
11. [Финальная проверка](#11-финальная-проверка)

---

## 1. Начальная настройка серверов

### Обновление системы

```bash
apt update && apt upgrade -y
apt install curl wget nano ufw sqlite3 -y
```

### Установка часового пояса

```bash
timedatectl set-timezone Europe/Moscow
```

---

## 2. Установка 3x-ui и Xray

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

После установки:
- Панель доступна по порту (по умолчанию 2053 или другой)
- Логин и пароль задаются при установке

---

## 3. Настройка VLESS Reality

### На RU-сервере:

1. Зайти в панель 3x-ui
2. Добавить Inbound:
   - Протокол: **VLESS**
   - Порт: **443**
   - Network: **TCP**
   - Security: **Reality**
   - Flow: **xtls-rprx-vision**
   - SNI: `www.cloudflare.com` (или другой)
   - Fingerprint: `firefox`
3. Сгенерировать ключи Reality (кнопка Generate)
4. Добавить первого клиента

### На NL-сервере:

Аналогично, но inbound будет принимать только каскадный трафик от RU.

---

## 4. Отключение парольной аутентификации SSH

### Генерация SSH-ключа (на локальном компьютере):

```powershell
ssh-keygen -t ed25519 -f C:\Users\<user>\.ssh\id_keyname
```

### Копирование ключа на сервер:

```powershell
ssh-copy-id -i C:\Users\<user>\.ssh\id_keyname.pub root@<IP>
```

### Настройка сервера:

```bash
nano /etc/ssh/sshd_config
```

Установить:
```
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

Проверить и применить:

```bash
sshd -t
systemctl restart sshd
```

⚠️ **Не закрывать текущую сессию до проверки входа по ключу в новом окне!**

### Решение проблем:

Если `sshd -t` выдаёт ошибку (например, `no argument after keyword`):

```bash
sshd -t                    # посмотреть точную ошибку
head -1 /etc/ssh/sshd_config  # проверить проблемную строку
nano /etc/ssh/sshd_config     # исправить
sshd -t                    # проверить снова
systemctl restart sshd
```

---

## 5. Скрытие панелей за SSH-туннелем

### На сервере:

```bash
/usr/local/x-ui/x-ui setting -listenIP 127.0.0.1
systemctl restart x-ui
```

Проверить:

```bash
ss -lntp | grep <порт_панели>
```

Должно быть: `127.0.0.1:<порт>`, а не `0.0.0.0:<порт>`

### На локальном компьютере (Windows PowerShell):

```powershell
ssh -N -T -L 33333:127.0.0.1:<порт_панели> root@<IP>
```

Окно не закрывать.

### Открыть панель в браузере:

```
https://127.0.0.1:33333/<webBasePath>/
```

---

## 6. Настройка подписки

### В панели 3x-ui:

**Настройки панели → Подписка**

| Параметр | Значение |
|----------|----------|
| Прослушивание IP | `0.0.0.0` (для внешнего доступа) или `127.0.0.1` (только через reverse proxy) |
| Домен прослушивания | Внешний IP сервера или домен |
| Порт подписки | Нестандартный (например, 2097) |
| URI-путь | Уникальный (например, `/mysub_xk39fh28dh37dh/`) |

⚠️ **Не использовать `/sub/`** — он широко известен.

### Исправление localhost в ссылках:

Если ссылки генерируются с `localhost`:

1. Заполнить поле **Домен прослушивания** → внешний IP сервера
2. Сохранить
3. `systemctl restart x-ui`
4. Скопировать ссылку клиента заново

---

## 7. Настройка Reverse Proxy (Nginx + HTTPS)

### Установка:

```bash
apt install nginx certbot python3-certbot-nginx -y
```

### Конфигурация Nginx:

```bash
nano /etc/nginx/sites-available/subscription
```

```nginx
server {
    listen 2096 ssl;
    server_name <IP_или_домен>;

    ssl_certificate     /etc/letsencrypt/live/<домен>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<домен>/privkey.pem;

    location /mysub_.../ {
        proxy_pass http://127.0.0.1:2097;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
```

### Получение SSL-сертификата:

```bash
certbot --nginx -d <домен>
```

### Закрытие прямого порта подписки:

```bash
ufw delete allow 2097/tcp
```

Теперь подписка доступна только через HTTPS на порту 2096.

---

## 8. Каскадная маршрутизация RU → NL

### На RU-сервере:

В панели 3x-ui:

1. **Inbound** (порт 443):
   - Sniffing: `http,tls,quic`
   - RouteOnly: `true`

2. **Routing Rules**:
   - `geoip:ru` → direct
   - `domain:ru` → direct
   - `private` → blocked
   - `bittorrent` → blocked
   - Всё остальное → NL-outbound

3. **Outbound** на NL:
   - Протокол: VLESS Reality
   - Адрес: `<NL_IP>`
   - Порт: 443

### На NL-сервере:

- Inbound VLESS Reality на 443
- Параметры Reality совпадают с outbound на RU
- Default outbound: direct/freedom
- Файрвол: разрешить 443 только от RU-сервера

### Проверка маршрутизации:

```bash
# Должны показать RU IP
curl --connect-timeout 5 https://2ip.ru
curl --connect-timeout 5 https://yandex.ru

# Должны показать NL IP
curl --connect-timeout 5 https://ifconfig.me
curl --connect-timeout 5 https://cloudflare.com/cdn-cgi/trace
```

---

## 9. Файрвол и закрытие портов

```bash
# Базовые правила
ufw default deny incoming
ufw default allow outgoing

# Открыть нужные порты
ufw allow 22/tcp        # SSH
ufw allow 443/tcp       # Xray
ufw allow 2096/tcp      # Nginx HTTPS

# Закрыть панели (уже привязаны к 127.0.0.1)
ufw deny 23432/tcp      # RU панель
ufw deny 9843/tcp       # NL панель

# Включить файрвол
ufw enable
ufw status numbered
```

---

## 10. Бэкапы и восстановление

### Создание бэкапа перед изменениями:

```bash
mkdir -p /root/backup-$(date +%Y%m%dT%H%M%SZ)
cd /root/backup-<дата>

# База данных
cp /etc/x-ui/x-ui.db .

# Конфиги
cp /usr/local/x-ui/bin/config.json .
cp /etc/nginx/sites-available/* .
cp /etc/ssh/sshd_config .

# Файрвол
ufw status numbered > firewall.txt

# Манифест
ls -la > MANIFEST.txt
```

### Восстановление:

```bash
systemctl stop x-ui
cp backup-dir/x-ui.db /etc/x-ui/
cp backup-dir/config.json /usr/local/x-ui/bin/
systemctl start x-ui
```

---

## 11. Финальная проверка

```bash
# Статус сервисов
systemctl status x-ui --no-pager
systemctl status nginx --no-pager
systemctl status sshd --no-pager

# Порты
ss -lntup

# Файрвол
ufw status

# Сертификат
openssl s_client -connect <IP>:2096 -servername <IP> </dev/null 2>/dev/null | openssl x509 -noout -dates

# Подписка
curl -I https://<IP>:2096/<URI>/

# База данных
sqlite3 /etc/x-ui/x-ui.db 'pragma integrity_check;'

# Вход по SSH-ключу (из нового окна)
ssh -i <путь_к_ключу> root@<IP>