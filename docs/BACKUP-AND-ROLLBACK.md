# 💾 Бэкапы и восстановление

Резервное копирование конфигурации и откат изменений.

## Содержание

1. [Что нужно бэкапить](#1-что-нужно-бэкапить)
2. [Создание бэкапа](#2-создание-бэкапа)
3. [Восстановление из бэкапа](#3-восстановление-из-бэкапа)
4. [Снапшоты VPS](#4-снапшоты-vps)
5. [Регулярные бэкапы](#5-регулярные-бэкапы)
6. [Чек-лист перед изменениями](#6-чек-лист-перед-изменениями)

---

## 1. Что нужно бэкапить

| Компонент | Путь | Важность |
|-----------|------|----------|
| База данных 3x-ui | `/etc/x-ui/x-ui.db` | 🔴 Критично |
| Конфиг Xray | `/usr/local/x-ui/bin/config.json` | 🔴 Критично |
| SSH конфиг | `/etc/ssh/sshd_config` | 🟡 Важно |
| SSH authorized_keys | `/root/.ssh/authorized_keys` | 🔴 Критично |
| Nginx конфиги | `/etc/nginx/sites-available/` | 🟡 Важно |
| Файрвол | Дамп UFW/iptables | 🟡 Важно |
| Сертификаты | `/etc/letsencrypt/` | 🟡 Важно |
| Systemd unit | `/etc/systemd/system/x-ui.service` | 🟢 Полезно |

---

## 2. Создание бэкапа

### Автоматический скрипт бэкапа:

```bash
#!/bin/bash
set -e

BACKUP_DIR="/root/backup-$(date +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_DIR"

echo "=== Создание бэкапа в $BACKUP_DIR ==="

# База данных
cp /etc/x-ui/x-ui.db "$BACKUP_DIR/"

# Конфиг Xray
cp /usr/local/x-ui/bin/config.json "$BACKUP_DIR/"

# SSH
cp /etc/ssh/sshd_config "$BACKUP_DIR/"
cp /root/.ssh/authorized_keys "$BACKUP_DIR/"

# Nginx
cp -r /etc/nginx/sites-available "$BACKUP_DIR/"

# Файрвол
ufw status numbered > "$BACKUP_DIR/firewall.txt"

# Сертификаты (пути)
ls -la /etc/letsencrypt/live/ > "$BACKUP_DIR/certificates.txt"

# Статус сервисов
systemctl status x-ui --no-pager > "$BACKUP_DIR/x-ui-status.txt"
systemctl status nginx --no-pager > "$BACKUP_DIR/nginx-status.txt" 2>/dev/null || true

# Манифест и контрольные суммы
cd "$BACKUP_DIR"
sha256sum * > MANIFEST.sha256

echo "=== Бэкап создан: $BACKUP_DIR ==="
ls -la "$BACKUP_DIR"
```

Сохранить как `/root/backup.sh`:

```bash
chmod +x /root/backup.sh
/root/backup.sh
```

---

## 3. Восстановление из бэкапа

### Полное восстановление:

```bash
#!/bin/bash
set -e

BACKUP_DIR="$1"

if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
    echo "Укажите директорию бэкапа: $0 /root/backup-20260713T120000Z"
    exit 1
fi

echo "=== Восстановление из $BACKUP_DIR ==="

# Остановить сервисы
systemctl stop x-ui
systemctl stop nginx 2>/dev/null || true

# База данных
cp "$BACKUP_DIR/x-ui.db" /etc/x-ui/

# Конфиг Xray
cp "$BACKUP_DIR/config.json" /usr/local/x-ui/bin/

# SSH
cp "$BACKUP_DIR/sshd_config" /etc/ssh/
cp "$BACKUP_DIR/authorized_keys" /root/.ssh/

# Nginx
cp "$BACKUP_DIR/sites-available/"* /etc/nginx/sites-available/

# Права
chmod 600 /root/.ssh/authorized_keys
chmod 700 /root/.ssh

# Запустить сервисы
systemctl start x-ui
systemctl start nginx 2>/dev/null || true

# Проверить
systemctl status x-ui --no-pager
nginx -t

echo "=== Восстановление завершено ==="
```

Сохранить как `/root/rollback.sh`:

```bash
chmod +x /root/rollback.sh
```

### Использование:

```bash
/root/rollback.sh /root/backup-20260713T120000Z
```

---

## 4. Снапшоты VPS

Почти все провайдеры предоставляют возможность сделать снапшот (snapshot) виртуального сервера.

**Это самый надёжный способ.**

### До изменений:

1. Зайти в панель управления VPS
2. Найти раздел Snapshots / Снапшоты
3. Создать снапшот
4. Дождаться завершения

### Откат:

1. Остановить VPS
2. Восстановить из снапшота
3. Запустить VPS

---

## 5. Регулярные бэкапы

### Через cron (ежедневно):

```bash
crontab -e
```

Добавить:

```
0 3 * * * /root/backup.sh
```

Бэкап будет создаваться каждый день в 3:00 ночи.

### Ротация старых бэкапов:

```bash
# Удалить бэкапы старше 30 дней
find /root/backup-* -maxdepth 0 -type d -mtime +30 -exec rm -rf {} \;
```

---

## 6. Чек-лист перед изменениями

Перед любыми изменениями на сервере:

- [ ] Сделать снапшот VPS у провайдера
- [ ] Запустить `/root/backup.sh`
- [ ] Проверить целостность базы:
  ```bash
  sqlite3 /etc/x-ui/x-ui.db 'pragma integrity_check;'
  ```
- [ ] Записать в MANIFEST какие изменения планируются
- [ ] Открыть вторую SSH-сессию (не закрывать текущую)

### После изменений:

- [ ] Проверить статус сервисов
- [ ] Проверить подключение клиентов
- [ ] Проверить маршрутизацию
- [ ] Если всё хорошо — удалить старые снапшоты

---

## Экстренное восстановление

Если сервер не загружается или SSH недоступен:

1. Зайти в панель VPS-провайдера
2. Использовать VNC/Web-консоль
3. Восстановить из снапшота
4. Или загрузиться в rescue-режим и скопировать файлы из бэкапа

---

*Все пути и идентификаторы заменены на плейсхолдеры.*