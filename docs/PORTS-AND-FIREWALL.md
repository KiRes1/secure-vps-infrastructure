# 🌐 Порты и файрвол

Карта открытых портов и правила UFW/iptables.

## Содержание

1. [Карта портов](#1-карта-портов)
2. [Правила UFW](#2-правила-ufw)
3. [Проверка портов](#3-проверка-портов)
4. [Изменение правил](#4-изменение-правил)

---

## 1. Карта портов

### RU-сервер

| Порт | Протокол | Интерфейс | Сервис | Назначение |
|------|----------|-----------|--------|------------|
| **22** | TCP | 0.0.0.0 | SSH | Управление сервером |
| **443** | TCP | 0.0.0.0 | Xray (VLESS Reality) | Клиентские подключения |
| **2096** | TCP | 0.0.0.0 | Nginx (HTTPS) | Сайт + подписки |
| 23432 | TCP | **127.0.0.1** | 3x-ui Panel | Панель управления RU |
| 2097 | TCP | **127.0.0.1** | Subscription Service | Внутренний сервис подписок |

### NL-сервер

| Порт | Протокол | Интерфейс | Сервис | Назначение |
|------|----------|-----------|--------|------------|
| **22** | TCP | 0.0.0.0 | SSH | Управление сервером |
| **443** | TCP | 0.0.0.0 (только от RU) | Xray (VLESS Reality) | Приём каскадного трафика |
| 9843 | TCP | **127.0.0.1** | 3x-ui Panel | Панель управления NL |

**Жирным** выделены порты, доступные из интернета.

---

## 2. Правила UFW

### RU-сервер

```bash
# Дефолтные политики
ufw default deny incoming
ufw default allow outgoing

# Открыть нужные порты
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 2096/tcp

# Закрыть порты панелей (уже на 127.0.0.1, дополнительная защита)
ufw deny 23432/tcp
ufw deny 2097/tcp

# Включить файрвол
ufw enable
```

Проверка:

```bash
ufw status numbered
```

Ожидаемый вывод:

```
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 443/tcp                    ALLOW IN    Anywhere
[ 3] 2096/tcp                   ALLOW IN    Anywhere
[ 4] 23432/tcp                  DENY IN     Anywhere
[ 5] 2097/tcp                   DENY IN     Anywhere
```

### NL-сервер

```bash
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp

# Порт 443 только для RU-сервера
ufw allow from <RU_IP> to any port 443 proto tcp
ufw deny 443/tcp

ufw deny 9843/tcp

ufw enable
```

Проверка:

```bash
ufw status numbered
```

Ожидаемый вывод:

```
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 443/tcp                    ALLOW IN    <RU_IP>
[ 3] 443/tcp                    DENY IN     Anywhere
[ 4] 9843/tcp                   DENY IN     Anywhere
```

---

## 3. Проверка портов

### Какие порты реально слушают:

```bash
ss -lntup
```

### Что доступно из интернета (проверить локально):

```bash
# Сканирование с другого сервера
nmap -p 22,443,2096,23432,2097,9843 <IP>
```

### Проверить конкретный порт:

```bash
ss -lntp | grep :<порт>
```

Пример:

```bash
ss -lntp | grep :443
# Должно быть: 0.0.0.0:443  (слушает все интерфейсы)

ss -lntp | grep :23432
# Должно быть: 127.0.0.1:23432  (только localhost)
```

---

## 4. Изменение правил

### Добавить порт:

```bash
ufw allow <порт>/tcp
```

### Удалить порт:

```bash
ufw delete allow <порт>/tcp
```

Или по номеру правила:

```bash
ufw status numbered
ufw delete <номер>
```

### Закрыть порт:

```bash
ufw deny <порт>/tcp
```

### Разрешить только с определённого IP:

```bash
ufw allow from <IP> to any port <порт> proto tcp
```

---

## 5. iptables (прямые правила)

Если UFW не используется, прямые правила iptables:

```bash
# Базовые правила
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Открыть порты
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 2096 -j ACCEPT

# Закрыть порты панелей
iptables -A INPUT -p tcp --dport 23432 -j DROP
iptables -A INPUT -p tcp --dport 2097 -j DROP

# Всё остальное — запретить
iptables -A INPUT -j DROP

# Сохранить
iptables-save > /etc/iptables/rules.v4
```

---

## 6. Почему порты панелей закрыты

| Порт | Почему закрыт |
|------|---------------|
| 23432 (RU панель) | Привязана к 127.0.0.1, доступ через SSH-туннель |
| 9843 (NL панель) | Привязана к 127.0.0.1, доступ через SSH-туннель |
| 2097 (подписка) | Проксируется через Nginx на 2096, прямой доступ не нужен |

**Принцип минимальных привилегий:** если порт не нужен снаружи — он должен быть закрыт или привязан к localhost.

---

## 7. Памятка

```
Интернет → Сервер

Разрешено:
  :22   → SSH (только по ключу)
  :443  → Xray (клиентские подключения)
  :2096 → Nginx (HTTPS сайт и подписки)

Запрещено/скрыто:
  :23432 → Панель RU (только через SSH-туннель)
  :9843  → Панель NL (только через SSH-туннель)
  :2097  → Подписка (только через Nginx)
```

---

*Все IP и порты заменены на плейсхолдеры.*