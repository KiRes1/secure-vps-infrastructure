#!/bin/bash
# ============================================
# Read-only скрипт диагностики сервера
# Не меняет конфигурацию, не перезапускает сервисы
# Безопасен для запуска в любое время
# ============================================

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================="
echo "   Read-only диагностика сервера"
echo "   $(date)"
echo "   $(hostname)"
echo "========================================="

# ------------------------------------------
# 1. Системная информация
# ------------------------------------------
echo ""
echo "=== СИСТЕМНАЯ ИНФОРМАЦИЯ ==="
echo "ОС: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"

# ------------------------------------------
# 2. Статус сервисов
# ------------------------------------------
echo ""
echo "=== СТАТУС СЕРВИСОВ ==="

check_service() {
    local service=$1
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} $service активен"
        return 0
    else
        echo -e "${RED}[FAIL]${NC} $service не активен"
        return 1
    fi
}

check_service x-ui
check_service nginx 2>/dev/null || echo "  (Nginx не установлен или не требуется)"
check_service sshd
check_service fail2ban 2>/dev/null || echo "  (Fail2Ban не установлен)"

# ------------------------------------------
# 3. Порты и слушатели
# ------------------------------------------
echo ""
echo "=== ПОРТЫ (LISTEN) ==="
ss -lntup 2>/dev/null | grep LISTEN || echo "Нет открытых портов"

# ------------------------------------------
# 4. Файрвол
# ------------------------------------------
echo ""
echo "=== ФАЙРВОЛ ==="
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "active"; then
        echo -e "${GREEN}[OK]${NC} UFW активен"
        ufw status numbered
    else
        echo -e "${YELLOW}[WARN]${NC} UFW не активен"
    fi
else
    echo "UFW не установлен"
fi

# ------------------------------------------
# 5. Проверка конфигов
# ------------------------------------------
echo ""
echo "=== ПРОВЕРКА КОНФИГОВ ==="

# SSH
if sshd -t 2>&1; then
    echo -e "${GREEN}[OK]${NC} SSH конфиг валидный"
else
    echo -e "${RED}[FAIL]${NC} SSH конфиг содержит ошибки"
fi

# Nginx
if command -v nginx &> /dev/null; then
    if nginx -t 2>&1; then
        echo -e "${GREEN}[OK]${NC} Nginx конфиг валидный"
    else
        echo -e "${RED}[FAIL]${NC} Nginx конфиг содержит ошибки"
    fi
fi

# ------------------------------------------
# 6. База данных SQLite
# ------------------------------------------
echo ""
echo "=== БАЗА ДАННЫХ ==="

DB_PATH=""
if [ -f "/etc/x-ui/x-ui.db" ]; then
    DB_PATH="/etc/x-ui/x-ui.db"
elif [ -f "/usr/local/x-ui/x-ui.db" ]; then
    DB_PATH="/usr/local/x-ui/x-ui.db"
fi

if [ -n "$DB_PATH" ] && command -v sqlite3 &> /dev/null; then
    echo "База: $DB_PATH"
    INTEGRITY=$(sqlite3 "$DB_PATH" 'pragma integrity_check;' 2>&1)
    if [ "$INTEGRITY" = "ok" ]; then
        echo -e "${GREEN}[OK]${NC} Integrity check: $INTEGRITY"
    else
        echo -e "${RED}[FAIL]${NC} Integrity check: $INTEGRITY"
    fi
    
    # Количество клиентов (без вывода UUID)
    CLIENT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM client;" 2>/dev/null || echo "?")
    echo "Клиентов в базе: $CLIENT_COUNT"
else
    echo "База данных не найдена или sqlite3 не установлен"
fi

# ------------------------------------------
# 7. Сертификаты
# ------------------------------------------
echo ""
echo "=== СЕРТИФИКАТЫ ==="

if command -v certbot &> /dev/null; then
    echo "Certbot установлен"
    certbot certificates 2>/dev/null | grep -E "Certificate Name|Domains:|Expiry Date" || echo "Сертификаты не найдены"
else
    echo "Certbot не установлен"
fi

# Проверка HTTPS на порту 2096 (если Nginx)
if command -v curl &> /dev/null && ss -lntp 2>/dev/null | grep -q ":2096"; then
    echo ""
    echo "Проверка HTTPS на порту 2096:"
    if curl -I --connect-timeout 5 -s https://localhost:2096/ 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        echo -e "${GREEN}[OK]${NC} Сайт отвечает"
    else
        echo -e "${YELLOW}[WARN]${NC} Сайт не отвечает или отвечает с ошибкой"
    fi
fi

# ------------------------------------------
# 8. Проверка SSH безопасности
# ------------------------------------------
echo ""
echo "=== SSH БЕЗОПАСНОСТЬ ==="

if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null || grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Парольная аутентификация отключена"
else
    echo -e "${RED}[FAIL]${NC} Парольная аутентификация может быть включена"
fi

# Проверка cloud-init
if grep -ri "passwordauthentication.*yes" /etc/ssh/sshd_config.d/ 2>/dev/null; then
    echo -e "${RED}[FAIL]${NC} Cloud-init содержит PasswordAuthentication yes"
fi

# Ключи
echo ""
echo "SSH ключи в authorized_keys:"
if [ -f "/root/.ssh/authorized_keys" ]; then
    KEY_COUNT=$(grep -c "^ssh-" /root/.ssh/authorized_keys 2>/dev/null || echo "0")
    echo "Количество ключей: $KEY_COUNT"
    echo "Fingerprints:"
    while read -r line; do
        if echo "$line" | grep -q "^ssh-"; then
            COMMENT=$(echo "$line" | awk '{print $NF}')
            echo "  - $COMMENT"
        fi
    done < /root/.ssh/authorized_keys
else
    echo -e "${RED}[FAIL]${NC} authorized_keys не найден"
fi

# ------------------------------------------
# 9. Бэкапы
# ------------------------------------------
echo ""
echo "=== БЭКАПЫ ==="
BACKUP_DIRS=$(ls -d /root/backup-* 2>/dev/null | wc -l)
if [ "$BACKUP_DIRS" -gt 0 ]; then
    echo -e "${GREEN}[OK]${NC} Найдено бэкапов: $BACKUP_DIRS"
    ls -ld /root/backup-* 2>/dev/null | tail -5
else
    echo -e "${YELLOW}[WARN]${NC} Бэкапы не найдены в /root/backup-*"
fi

# ------------------------------------------
# 10. Использование диска
# ------------------------------------------
echo ""
echo "=== ДИСК ==="
df -h / | tail -1 | awk '{print "Занято: " $3 "/" $2 " (" $5 ")"}'

echo ""
echo "========================================="
echo "   Диагностика завершена"
echo "   $(date)"
echo "========================================="