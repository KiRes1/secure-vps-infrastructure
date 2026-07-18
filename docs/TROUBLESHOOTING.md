# 🔧 Диагностика и решение проблем

Типовые проблемы и методы их решения.

## Содержание

1. [SSH не перезапускается](#1-ssh-не-перезапускается)
2. [Клиент не подключается](#2-клиент-не-подключается)
3. [Подписка недоступна](#3-подписка-недоступна)
4. [Панель не открывается](#4-панель-не-открывается)
5. [Сертификат истёк](#5-сертификат-истёк)
6. [NL-сервер недоступен](#6-nl-сервер-недоступен)
7. [Российские сайты идут через NL](#7-российские-сайты-идут-через-nl)
8. [Иностранные сайты идут через RU](#8-иностранные-сайты-идут-через-ru)

---

## 1. SSH не перезапускается

### Симптомы

```bash
systemctl restart ssh.service
# Job for ssh.service failed because the control process exited with error code.
```

```bash
systemctl status ssh.service
# Active: failed (Result: exit-code)
# Process: ExecStartPre=/usr/sbin/sshd -t (code=exited, status=255/EXCEPTION)
```

### Причина

Ошибка в `/etc/ssh/sshd_config`. `sshd -t` (проверка конфига перед запуском) провалилась.

### Решение

**Шаг 1: Точная диагностика**

```bash
sshd -t
```

Пример вывода ошибки:

```
/etc/ssh/sshd_config line 1: no argument after keyword "W"
/etc/ssh/sshd_config: terminating, 1 bad configuration options
```

**Шаг 2: Найти проблемную строку**

```bash
head -1 /etc/ssh/sshd_config
```

**Шаг 3: Исправить**

```bash
nano /etc/ssh/sshd_config
```

Удалить/исправить ошибочную строку.

**Шаг 4: Проверить и перезапустить**

```bash
sshd -t                    # если вывод пустой — конфиг валидный
systemctl restart sshd
systemctl status sshd
```

### ⚠️ Критически важно

**Не закрывайте текущую SSH-сессию**, пока служба не запущена и не проверена в новом окне!

Иначе доступ к серверу будет потерян — восстановление только через VNC/Web-консоль провайдера.

### Другие причины ошибки sshd -t

| Ошибка | Причина | Исправление |
|--------|---------|-------------|
| `no argument after keyword` | Случайный символ/неполная директива | Удалить/исправить строку |
| `unsupported option` | Опечатка в директиве | Проверить написание |
| `No such file or directory` | Неверный путь (Banner, AuthorizedKeysFile) | Исправить путь |
| `port already in use` | Порт занят | `ss -tlnp \| grep :22` |
| `bad permissions` | Неверные права на ключи хоста | `chmod 600 /etc/ssh/ssh_host_*` |

---

## 2. Клиент не подключается

### Симптомы

- Пинг `n/a` в приложении
- Ошибка таймаута
- `Connection refused`

### Диагностика на сервере

```bash
# Порт слушает?
ss -lntp | grep 443

# x-ui запущен?
systemctl status x-ui

# Файрвол открыт?
ufw status | grep 443
```

### Возможные причины и решения

| Причина | Решение |
|---------|---------|
| Порт слушает `127.0.0.1` вместо `0.0.0.0` | Проверить inbound в панели |
| Файрвол блокирует порт | `ufw allow 443/tcp` |
| x-ui не запущен | `systemctl start x-ui` |
| В конфиге указан `localhost` | Исправить Домен прослушивания в панели |
| DNS на устройстве клиента | Установить `1.1.1.1` |
| Клиент отключён в панели | Проверить галочку Enable |

---

## 3. Подписка недоступна

### Симптомы

- `Failed to fetch`
- `404 Not Found`
- `502 Bad Gateway`

### Диагностика

```bash
# Внутренний сервис слушает?
ss -lntp | grep 2097

# Nginx запущен?
systemctl status nginx

# Прокси работает локально?
curl -I http://127.0.0.1:2097/<URI_путь>/<subId>

# Nginx проксирует?
curl -I https://<IP>:2096/<URI_путь>/<subId>
```

### Решения

| Проблема | Решение |
|----------|---------|
| 404 Not Found | Проверить URI-путь и subId |
| 502 Bad Gateway | `systemctl restart x-ui` |
| Connection refused | Проверить Nginx и файрвол |
| Сертификат недействителен | `certbot renew` |

---

## 4. Панель не открывается

### Симптомы

- `ERR_CONNECTION_REFUSED`
- Предупреждение о сертификате
- Белая страница

### Диагностика

```bash
# Панель слушает?
ss -lntp | grep <порт_панели>

# x-ui запущен?
systemctl status x-ui

# Туннель работает? (на Windows)
netstat -ano | findstr :<локальный_порт>
```

### Решения

| Проблема | Решение |
|----------|---------|
| Панель на `127.0.0.1`, нет туннеля | Запустить SSH-туннель |
| Туннель упал | Перезапустить туннель |
| Предупреждение сертификата | «Дополнительно» → «Перейти на сайт» |
| Неверный webBasePath | Проверить путь в `x-ui setting -show` |
| Используется http вместо https | `https://127.0.0.1:<порт>/...` |

---

## 5. Сертификат истёк

### Симптомы

- `NET::ERR_CERT_DATE_INVALID`
- Предупреждение в браузере

### Диагностика

```bash
# Проверить даты сертификата
openssl s_client -connect <IP>:2096 -servername <IP> </dev/null 2>/dev/null | openssl x509 -noout -dates

# Статус certbot
certbot certificates
```

### Решение

```bash
# Тестовый запуск
certbot renew --dry-run

# Продление
certbot renew

# Перезагрузить Nginx
systemctl restart nginx
```

### Проверка автообновления

```bash
systemctl status certbot.timer
systemctl list-timers | grep certbot
```

---

## 6. NL-сервер недоступен

### Симптомы

- Иностранные сайты не открываются
- Российские сайты работают

### Диагностика (с RU-сервера)

```bash
# NL доступен по сети?
ping -c 3 <NL_IP>

# Порт 443 на NL открыт?
curl -I --connect-timeout 5 https://<NL_IP>:443

# x-ui на NL запущен?
ssh root@<NL_IP> systemctl status x-ui
```

### Решения

| Проблема | Решение |
|----------|---------|
| NL не пингуется | Проверить VPS провайдера NL |
| Порт 443 закрыт | `ufw allow 443/tcp` на NL |
| x-ui не запущен | `systemctl start x-ui` на NL |
| Файрвол блокирует RU | `ufw allow from <RU_IP> to any port 443` на NL |

---

## 7. Российские сайты идут через NL

### Симптомы

`2ip.ru` показывает NL IP вместо RU

### Причина

Сломана маршрутизация на RU-сервере.

### Проверить

1. Правила routing в панели (RU → direct должно быть **выше** правила на NL)
2. `domainStrategy: IPIfNonMatch`
3. Sniffing включён на inbound

---

## 8. Иностранные сайты идут через RU

### Симптомы

`ifconfig.me` показывает RU IP вместо NL

### Причина

Трафик не попадает в outbound на NL.

### Проверить

1. Outbound на NL активен (Enabled)
2. NL-сервер доступен с RU (п.6)
3. UUID/ключи Reality совпадают на RU и NL

---

## Read-only диагностические команды

Безопасные команды, которые **не меняют** конфигурацию:

```bash
# Статус сервисов
systemctl status x-ui --no-pager
systemctl status nginx --no-pager
systemctl status sshd --no-pager

# Логи
journalctl -u x-ui -n 100 --no-pager
journalctl -u nginx -n 50 --no-pager

# Порты и соединения
ss -lntup
ufw status numbered

# Проверка конфигов (read-only)
nginx -t
sshd -t

# База данных
sqlite3 /etc/x-ui/x-ui.db 'pragma integrity_check;'

# Сертификат
curl -I https://<IP>:2096/
openssl s_client -connect <IP>:2096 -servername <IP> </dev/null 2>/dev/null | openssl x509 -noout -dates

# Маршрутизация
curl --connect-timeout 5 https://2ip.ru
curl --connect-timeout 5 https://ifconfig.me
```

---

*Все IP, порты и идентификаторы заменены на плейсхолдеры.*