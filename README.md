# Программа для сбора логов с компьютeров сети

Скрипт автоматически:
- сканирует вашу локальную сеть;
- определяет ОС (Windows/Linux);
- собирает системные и событийные логи;
- сохраняет их на ваш компьютер;
- загрузит логи Windows и Linux в БД;
- отобразит на сайте.
  

> Поддерживает **Windows** (через WinRM) и **Linux** (через SSH, включая Astra Linux).

---

##  Требования

### На компьютере, с которого запускается скрипт (**ваш ПК**):
- Windows 10/11 или Windows Server 2016+;
- PowerShell (встроен по умолчанию);
- **Запуск от имени администратора**;
- Доступ в интернет (для установки компонентов).

### На целевых машинах:
- **Windows**: должен быть включён **WinRM** (см. ниже);
- **Linux**: должен быть включён **SSH с парольной аутентификацией**.

---

## Подготовка вашего компьютера

> Выполните всё в **PowerShell от имени администратора**.

### Установите OpenSSH Client (входит в Windows)
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```
### Установка Chocolatey (По желанию)
```powershell
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Без sshpass вы будете вводить пароль 2–3 раза на каждую Linux-машину
```
## Подготовка целевых машин

### Для Windows-машин

```powershell
# 1. Быстрая настройка WinRM
winrm quickconfig -quiet

# 2. Разрешить незашифрованный трафик (только для доверенной сети!)
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# 3. Включить базовую аутентификацию (логин/пароль)
winrm set winrm/config/service/auth '@{Basic="true"}'

# 4. Убедиться, что служба запущена
Start-Service WinRM
Set-Service WinRM -StartupType Automati

# 5. Настройка типа сети
# Сеть изменена с «Общедоступной» на «Частную», в противном случае WinRM блокируется:

Set-NetConnectionProfile -InterfaceIndex <номер> -NetworkCategory Private

# Номер интерфейса можно узнать с помощью:
Get-NetIPConfiguration
```
### Для Linux-машин (Astra, Ubuntu и др.)

```bash
sudo systemctl enable --now ssh

sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

sudo systemctl restart sshd
```
## Работа скрипта

### Запуск скрипта

- Запустите run_log_pipeline.bat;
- Введите: IP любой машины из вашей подсети (например, 192.178.1.100);
- Имя админа;
- Пароль.

### Результаты скрипта

- CSV-файлы — открывайте в Excel двойным кликом (кириллица поддерживается);
- TXT-файлы (systeminfo, ipconfig) — открывайте в Блокноте или в VS Code с кодировкой Windows-1251;
- system_logs.db - где хранятся логи от Windows и Linux машин;
- запустится сайт, в котором можно с помоью фильтров смотреть логи с целевых хостов.

## Возможные проблемы

### Проблема	

> «WinRM connection failed»	

### Решение

> Убедитесь, что на целевой Windows выполнены команды из раздела «Для Windows-машин»

### Проблема

> «Требует пароль SSH»

### Решение

> Установите sshpass или вводите пароль вручную

### Проблема

> «Кракозябры в TXT»	

### Решение

> Открывайте в Блокноте или укажите кодировку Windows-1251
