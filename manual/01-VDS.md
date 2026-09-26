# Xray на VDS

Инструкция для нового Ubuntu 24.04 LTS / Debian 12 с systemd, доступом sudo и публичным IPv4. Если на сервере уже есть Xray или занят TCP 443, не заменяйте конфигурацию и не останавливайте чужой сервис: добавьте отдельный согласованный порт/экземпляр и укажите тот же порт у клиента.

## 1. Установка

Подключитесь по SSH своим существующим способом. Не выполняйте серверные команды на локальном компьютере.

```bash
sudo apt update
sudo apt install -y curl unzip openssl nano
sudo ss -ltnp 'sport = :443'
systemctl status xray --no-pager
```

На новом сервере отсутствие службы xray — нормально. Если порт 443 свободен и существующей установки нет, скачайте официальный установщик в файл, просмотрите его и запустите:

```bash
curl -fL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o install-xray.sh
less install-xray.sh
sudo bash install-xray.sh install
/usr/local/bin/xray version
sudo systemctl stop xray
```

Установщик создаёт службу `xray` и каталог `/usr/local/etc/xray`. Здесь она останавливается до заполнения конфигурации. Если скачивание завершилось ошибкой, дальше не продолжайте.

## 2. Параметры подключения

Сгенерируйте значения на сервере:

```bash
/usr/local/bin/xray uuid
/usr/local/bin/xray x25519
openssl rand -hex 8
```

UUID и short ID понадобятся обеим сторонам. Из результата `x25519` приватный ключ идёт только в конфигурацию сервера. Публичное значение в разных версиях может называться `Public key` либо `Password`; это значение клиента, не строка `Hash32`.

Выберите `REALITY_HOST`: доступный с VDS HTTPS-хост с TLS 1.3 и HTTP/2. Проверяйте конкретный хост с сервера; имя должно соответствовать его сертификату. Подходящий для вашей сети target не гарантируется универсальным примером.

```bash
REALITY_HOST='ЗАМЕНИТЕ_НА_ПОДХОДЯЩИЙ_ХОСТ'
openssl s_client -connect "${REALITY_HOST}:443" -servername "$REALITY_HOST" -tls1_3 -alpn h2 </dev/null
```

В выводе нужны успешный TLS 1.3, `ALPN protocol: h2` и корректная цепочка сертификатов. Подробности выбора target — в официальном README https://github.com/XTLS/REALITY .

## 3. Конфигурация

Сохраните содержимое `server.template.json` в `/usr/local/etc/xray/config.json` через редактор. Если установщик создал файл — сначала сделайте копию.

```bash
sudo cp -a /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.before-tutorial
sudo nano /usr/local/etc/xray/config.json
```

Замените `REPLACE_UUID`, `REPLACE_PRIVATE_KEY`, `REPLACE_SHORT_ID` и оба вхождения `REPLACE_REALITY_HOST`. Не переносите комментарии и разметку Markdown в JSON.

Ограничьте чтение файла пользователем службы и проверьте конфигурацию:

```bash
XRAY_USER=$(systemctl show xray -p User --value)
test -n "$XRAY_USER" || XRAY_USER=root
XRAY_GROUP=$(id -gn "$XRAY_USER")
sudo chown root:"$XRAY_GROUP" /usr/local/etc/xray/config.json
sudo chmod 640 /usr/local/etc/xray/config.json
sudo -u "$XRAY_USER" /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

Продолжайте только при успешной проверке. В действующем firewall сервера и сетевом firewall провайдера разрешите входящий TCP 443. Для уже включённого UFW:

```bash
sudo ufw status verbose
sudo ufw allow 443/tcp
```

Не включайте UFW вслепую, не меняйте SSH-правила. Открывать SOCKS-порты 1080–1082 наружу не нужно. В этой схеме UDP приложения переносится внутри соединения VLESS; отдельный публичный UDP 443 для выбранного транспорта не требуется.

```bash
sudo systemctl enable --now xray
sudo systemctl status xray --no-pager
sudo journalctl -u xray -n 30 --no-pager
sudo ss -ltnp 'sport = :443'
```

## 4. Данные клиента

В `client.template.json` замените:

- `REPLACE_SERVER_IPV4` — публичный IPv4 VDS;
- `REPLACE_UUID` — UUID клиента из серверного конфига;
- `REPLACE_REALITY_HOST` — то же имя, что в serverNames;
- `REPLACE_PUBLIC_KEY` — публичное значение пары x25519;
- `REPLACE_SHORT_ID` — short ID сервера.

Сохраните как `client.json`. Приватный ключ REALITY клиенту не нужен. Поля `dest`, `publicKey`, `network: tcp` и `vnext` используются в совместимом формате шаблона; перед эксплуатацией проверьте его установленной версией Xray.

## Отключение новой установки

```bash
sudo systemctl disable --now xray
```

Если вы добавили правило UFW 443 исключительно для этой настройки, удалить именно его можно `sudo ufw delete allow 443/tcp`. Существующие правила других сервисов не удаляйте. Приватные конфигурации не включайте в публичный архив.
