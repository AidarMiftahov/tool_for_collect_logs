# Network Log Collection Tool

The script automatically:
- scans your local network;
- detects the operating system (Windows/Linux);
- collects system and event logs;
- saves them to your computer;
- loads Windows and Linux logs into a database;
- displays them on a web interface.
  

> Supports Windows (via WinRM) and Linux (via SSH, including Astra Linux). 

---

##  Requirements

### On your local machine (your PC):
- Windows 10/11 or Windows Server 2016+;
- PowerShell (built-in by default);
- **Run as Administrator**;
- Internet access (required for installing components).

### On target machines:
- **Windows**: **WinRM** must be enabled (see below);
- **Linux**: **SSH with password authentication** must be enabled.

---

## Preparing Your Computer

> Perform all steps in **PowerShell as Administrator**.

### Install OpenSSH Client (included with Windows)
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```
### Install Chocolatey (optional)

```powershell
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Without sshpass, you will need to manually enter the password 2–3 times per Linux machine
```
## Preparing Target Machines

### For Windows machines

```powershell
# 1. Quick WinRM configuration
winrm quickconfig -quiet

# 2. Allow unencrypted traffic (only for trusted networks!)
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# 3. Enable basic authentication (username/password)
winrm set winrm/config/service/auth '@{Basic="true"}'

# 4. Ensure the WinRM service is running
Start-Service WinRM
Set-Service WinRM -StartupType Automati

# 5. Set network profile to Private
# Change network type from "Public" to "Private"; otherwise, WinRM will be blocked:
Set-NetConnectionProfile -InterfaceIndex <номер> -NetworkCategory Private

# Find the interface number using:
Get-NetIPConfiguration
```
### For Linux machines (Astra, Ubuntu, etc.)

```bash
sudo systemctl enable --now ssh

sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

sudo systemctl restart sshd
```
## Programm

### Launching the program

- Run run_log_pipeline.bat;
- Enter an IP address from your subnet (e.g., 192.178.1.100);
- Provide the administrator username;
- Provide the password.

### Script output

- CSV files – open in Excel with double-click (Cyrillic characters supported);
- TXT files (systeminfo, ipconfig, etc.) – open in Notepad or VS Code using Windows-1251 encoding;
- system_logs.db – SQLite database containing logs from Windows and Linux machines;
- A local web interface will launch automatically, allowing you to filter and view logs from target hosts.

## Common Issues

### Issue

> «WinRM connection failed»

### Solution

> Ensure all commands in the “For Windows machines” section have been executed on the target Windows host.

### Issue

> «SSH password required»

### Solution

> Install sshpass, or enter the password manually when prompted. 

### Issue

> «Garbled text (mojibake) in TXT files»	

### Solution

> Open files in Notepad, or explicitly specify Windows-1251 encoding (e.g., in VS Code).


---

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
## Программа

### Запуск программы

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
