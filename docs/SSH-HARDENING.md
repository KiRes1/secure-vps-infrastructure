# 🔑 Укрепление SSH

Отключение парольной аутентификации и настройка доступа только по ключам.

## Содержание

1. [Генерация SSH-ключа](#1-генерация-ssh-ключа)
2. [Копирование ключа на сервер](#2-копирование-ключа-на-сервер)
3. [Проверка входа по ключу](#3-проверка-входа-по-ключу)
4. [Отключение парольной аутентификации](#4-отключение-парольной-аутентификации)
5. [Дополнительные меры безопасности](#5-дополнительные-меры-безопасности)
6. [Диагностика и восстановление](#6-диагностика-и-восстановление)

---

## 1. Генерация SSH-ключа

### На Windows (PowerShell):

```powershell
ssh-keygen -t ed25519 -f C:\Users\<user>\.ssh\id_mykey -C "my-comment"
```

Система запросит passphrase — **обязательно установите** её. Это добавляет второй фактор защиты.

Результат:
- `C:\Users\<user>\.ssh\id_mykey` — приватный ключ (НИКОМУ НЕ ПЕРЕДАВАТЬ)
- `C:\Users\<user>\.ssh\id_mykey.pub` — публичный ключ (копируется на сервер)

### Проверить fingerprint ключа:

```powershell
ssh-keygen -lf C:\Users\<user>\.ssh\id_mykey.pub
```

---

## 2. Копирование ключа на сервер

### Способ 1: ssh-copy-id (если работает)

```powershell
ssh-copy-id -i C:\Users\<user>\.ssh\id_mykey.pub root@<IP>
```

Ввести пароль сервера (последний раз).

### Способ 2: Вручную

На локальном компьютере скопировать содержимое публичного ключа:

```powershell
type C:\Users\<user>\.ssh\id_mykey.pub
```

На сервере:

```bash
mkdir -p /root/.ssh
nano /root/.ssh/authorized_keys
```

Вставить скопированный ключ новой строкой, сохранить.

Установить правильные права:

```bash
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
```

---

## 3. Проверка входа по ключу

**Не закрывая текущую сессию**, открыть новое окно PowerShell:

```powershell
ssh -i C:\Users\<user>\.ssh\id_mykey root@<IP>
```

Если вход успешен — можно отключать пароли.

### Настройка SSH Config (для удобства):

Создать/отредактировать `C:\Users\<user>\.ssh\config`:

```
Host my-server
    HostName <IP>
    User root
    IdentityFile C:\Users\<user>\.ssh\id_mykey
    IdentitiesOnly yes
```

Теперь можно подключаться просто:

```powershell
ssh my-server
```

---

## 4. Отключение парольной аутентификации

### Шаг 1: Редактирование конфига

```bash
nano /etc/ssh/sshd_config
```

Найти и установить/раскомментировать:

```ini
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PubkeyAuthentication yes
PermitEmptyPasswords no
```

### Шаг 2: Проверка дополнительных конфигов

На некоторых системах (особенно с cloud-init) есть дополнительные файлы:

```bash
grep -ri "passwordauthentication" /etc/ssh/sshd_config.d/
```

Если какой-то файл содержит `PasswordAuthentication yes`:

```bash
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/<имя_файла>
```

### Шаг 3: Проверка конфига

```bash
sshd -t
```

Если вывод пустой — конфиг валидный.

Если ошибка — см. раздел [Диагностика и восстановление](#6-диагностика-и-восстановление).

### Шаг 4: Применение

```bash
systemctl restart sshd
```

### Шаг 5: Финальная проверка

**В новом окне** (текущую сессию не закрывать):

```powershell
ssh root@<IP>
```

Должно быть: `Permission denied (publickey)`

```powershell
ssh -i C:\Users\<user>\.ssh\id_mykey root@<IP>
```

Должен впустить.

---

## 5. Дополнительные меры безопасности

### Проверка других ключей на сервере:

```bash
cat /root/.ssh/authorized_keys
```

Убедиться, что там только нужные ключи.

### Проверка прав:

```bash
ls -la /root/.ssh/
```

Должно быть:
```
drwx------ /root/.ssh/
-rw------- /root/.ssh/authorized_keys
```

### Настройка Fail2Ban (рекомендуется):

```bash
apt install fail2ban -y
systemctl enable fail2ban
systemctl start fail2ban
```

---

## 6. Диагностика и восстановление

### Ошибка: `sshd -t` завершается с ошибкой

#### Пример: `no argument after keyword "W"`

**Причина:** случайный символ или неполная директива в начале файла.

**Решение:**

```bash
sshd -t                     # посмотреть точную ошибку
head -1 /etc/ssh/sshd_config   # посмотреть проблемную строку
nano /etc/ssh/sshd_config      # удалить/исправить строку
sshd -t                     # проверить снова
systemctl restart sshd
```

#### Другие типовые ошибки:

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `unsupported option` | Опечатка в директиве | Проверить написание |
| `No such file or directory` | Неверный путь к файлу | Исправить путь |
| `port already in use` | Порт занят | `ss -tlnp \| grep :22` |
| `bad permissions` | Неверные права на ключи | `chmod 600 /etc/ssh/ssh_host_*` |

### Восстановление доступа при потере SSH:

Если SSH не запускается и сессия закрыта:

1. Зайти через VNC/Web-консоль провайдера
2. Исправить `/etc/ssh/sshd_config`
3. `systemctl restart sshd`

---

## ⚠️ Критически важные правила

1. **Никогда не закрывайте рабочую сессию**, пока не проверили вход в новом окне
2. **Всегда делайте бэкап** перед изменениями: `cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak`
3. **Проверяйте `sshd -t`** перед каждым `systemctl restart`
4. **Используйте passphrase** для SSH-ключей
5. **Не храните приватные ключи** на сервере

---

*Все IP-адреса заменены на плейсхолдеры.*