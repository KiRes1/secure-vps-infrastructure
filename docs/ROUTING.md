# 🧭 Каскадная маршрутизация RU → NL

Настройка разделения трафика: российские сайты напрямую, иностранные — через NL-сервер.

## Содержание

1. [Архитектура каскада](#1-архитектура-каскада)
2. [Настройка RU-сервера](#2-настройка-ru-сервера)
3. [Настройка NL-сервера](#3-настройка-nl-сервера)
4. [Проверка маршрутизации](#4-проверка-маршрутизации)
5. [Типовые проблемы](#5-типовые-проблемы)

---

## 1. Архитектура каскада

```
Клиент
  │
  │ VLESS TCP Reality :443
  ▼
┌─────────────────────────────┐
│         RU-сервер            │
│                              │
│  Входящий трафик             │
│      │                       │
│      ├── geoip:ru ──→ direct │  (российские IP)
│      ├── domain:ru ─→ direct │  (российские домены)
│      ├── private ──→ blocked │  (локальные адреса)
│      ├── torrent ──→ blocked │  (торренты)
│      │                       │
│      └── всё остальное       │
│              │               │
│              ▼               │
│         outbound NL          │
│         VLESS Reality        │
│         на NL_IP:443         │
└──────────────┬──────────────┘
               │
               │ VLESS TCP Reality :443
               ▼
┌─────────────────────────────┐
│         NL-сервер            │
│                              │
│  Inbound VLESS Reality :443  │
│      │                       │
│      └── direct/freedom ──→  │  выпуск в интернет
│                              │
└─────────────────────────────┘
```

---

## 2. Настройка RU-сервера

### 2.1 Inbound (клиентский)

В панели 3x-ui:

| Параметр | Значение |
|----------|----------|
| Протокол | VLESS |
| Порт | 443 |
| Network | TCP |
| Security | Reality |
| Flow | xtls-rprx-vision |
| **Sniffing** | **Включено** (http,tls,quic) |
| **RouteOnly** | **true** |

### 2.2 Routing Rules

Добавить правила в порядке приоритета:

| # | Тип | Значение | Действие |
|---|-----|----------|----------|
| 1 | domain | `domain:ru` | direct |
| 2 | geoip | `geoip:ru` | direct |
| 3 | ip | `geoip:private` | block |
| 4 | protocol | `bittorrent` | block |
| 5 | — | всё остальное | NL-outbound |

**domainStrategy:** `IPIfNonMatch`

### 2.3 Outbound на NL

| Параметр | Значение |
|----------|----------|
| Протокол | VLESS |
| Адрес | `<NL_IP>` |
| Порт | 443 |
| Network | TCP |
| Security | Reality |
| Flow | xtls-rprx-vision |
| UUID | UUID клиента на NL |
| Public Key | Public Key NL inbound |
| Short ID | Short ID NL inbound |
| SNI | SNI NL inbound |
| Fingerprint | firefox |

---

## 3. Настройка NL-сервера

### 3.1 Inbound (приём каскада)

| Параметр | Значение |
|----------|----------|
| Протокол | VLESS |
| Порт | 443 |
| Network | TCP |
| Security | Reality |
| Flow | xtls-rprx-vision |

**Важно:** на этом inbound только **один клиент** — служебный клиент для RU-сервера.

### 3.2 Файрвол

Ограничить доступ к порту 443 только с RU-сервера:

```bash
ufw allow from <RU_IP> to any port 443 proto tcp
ufw deny 443/tcp
```

### 3.3 Default Outbound

Установлен в **direct/freedom** — весь принятый трафик уходит напрямую в интернет.

---

## 4. Проверка маршрутизации

### На сервере (через curl):

```bash
# Должны показать RU IP
curl --connect-timeout 5 https://2ip.ru
curl --connect-timeout 5 -L https://yandex.ru 2>&1 | grep -i location

# Должны показать NL IP
curl --connect-timeout 5 https://ifconfig.me
curl --connect-timeout 5 https://cloudflare.com/cdn-cgi/trace
```

### Через клиентское приложение:

1. Подключиться к VPN
2. Открыть `https://2ip.ru` — должен быть RU IP
3. Открыть `https://ifconfig.me` — должен быть NL IP
4. Открыть `https://yandex.ru` — должен открываться (RU)
5. Открыть `https://google.com` — должен открываться (через NL)

---

## 5. Типовые проблемы

### Российские сайты идут через NL

**Причина:** сломан routing или domainStrategy.

**Проверить:**
- Правила routing в панели (RU → direct выше, чем правило на NL)
- domainStrategy: `IPIfNonMatch`
- Sniffing включён на inbound

### Иностранные сайты идут напрямую через RU

**Причина:** трафик не попадает в outbound на NL.

**Проверить:**
- Outbound на NL активен (Enabled)
- NL-сервер доступен с RU: `ping <NL_IP>`
- Порт 443 на NL открыт для RU: `curl -I --connect-timeout 5 https://<NL_IP>:443`
- UUID/ключи совпадают на RU и NL

### NL-сервер недоступен

**Проверить с RU:**
```bash
ping <NL_IP>
ss -lntp | grep 443  # на обоих серверах
```

**Проверить на NL:**
```bash
ufw status | grep 443
systemctl status x-ui
```

### Весь трафик блокируется

**Причина:** правило private или bittorrent слишком широкое.

**Проверить:**
- Убрать временно правила block
- Проверить по одному

---

## Схема проверки маршрутизации

| Сайт | Ожидаемый IP | Маршрут |
|------|-------------|---------|
| 2ip.ru | RU | direct |
| yandex.ru | RU | direct |
| vk.com | RU | direct |
| gosuslugi.ru | RU | direct |
| ifconfig.me | NL | через NL |
| google.com | NL | через NL |
| github.com | NL | через NL |
| cloudflare.com | NL | через NL |

---

*Все IP-адреса и идентификаторы заменены на плейсхолдеры.*