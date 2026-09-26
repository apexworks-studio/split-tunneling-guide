# Раздельное туннелирование — полная инструкция

Windows: tun2socks → Xray → VDS. Linux: Xray → VDS.

Команды разделены по компьютеру и серверу. Не выполняйте весь документ как один скрипт.


---

# Раздельное туннелирование: комплект ручной настройки

APEX WORKS • 26 сентября 2026

1. Сначала выполните `01-VDS.md` на новом сервере либо получите совместимые параметры существующего Xray.
2. Затем выберите `02-Windows.md` или `03-Linux.md`.
3. Готовое задание агенту — `04-Agent.md`.

Windows: выбранные IPv4 → tun2socks → Xray → VDS. Linux: программы с настройкой прокси → Xray → VDS; доменные правила выбирают туннель или прямой выход.

Файлы `*.template.json` — шаблоны, перед запуском замените все `REPLACE_...`. Никаких действующих ключей или доступов в комплекте нет. Настройка VDS не требует копировать на него приватный SSH-ключ.

Три локальных входа Xray:

| Порт | Назначение |
|---|---|
| 127.0.0.1:1080 | SOCKS для приложений: выбранные домены через VDS, остальные напрямую |
| 127.0.0.1:1081 | HTTP-прокси для приложений с теми же правилами |
| 127.0.0.1:1082 | Только tun2socks: принятые публичные адреса всегда через VDS |

Отдельный порт 1082 предотвращает возврат выбранного TUN-трафика в прямой выход Xray и повторный захват тем же IP-маршрутом. Не заменяйте его в Windows-скрипте на 1080.

Ручной пример — начальная управляемая настройка, без автоматического запуска после перезагрузки. Windows-скрипт обновляет адреса только при новом запуске. IPv6, глобальный DNS-перехват и прозрачный перехват всех приложений Linux здесь не настроены. Это не kill switch: после удаления маршрутов приложения снова используют обычную сеть.

Проверка `xray run -test` подтверждает чтение и сборку конфигурации, но не доступность VDS, REALITY target, корректность маршрутов, DNS или голосовых приложений. Отдельно выполните сетевые проверки из инструкции.

## Источники

- Xray и релизы: https://github.com/XTLS/Xray-core/releases
- Установка Linux: https://github.com/XTLS/Xray-install
- Примеры VLESS/REALITY: https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-XTLS-Vision-REALITY
- Правила маршрутизации: https://xtls.github.io/en/config/routing.html
- Локальный SOCKS: https://xtls.github.io/en/config/inbounds/socks.html
- tun2socks: https://github.com/xjasonlyu/tun2socks/releases
- Windows TUN: https://github.com/xjasonlyu/tun2socks/wiki/Examples
- Имя TUN: https://github.com/xjasonlyu/tun2socks/wiki/Device-Models
- Wintun: https://www.wintun.net/
- Windows-маршруты: https://learn.microsoft.com/en-us/powershell/module/nettcpip/new-netroute
- curl: https://curl.se/docs/manpage.html

VDSina: https://www.vdsina.com/?partner=7928ly98iumw — реферальная ссылка автора.
Разработка сайтов, сервисов и приложений: https://apexworks.ru


---

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


---

# Windows: tun2socks → Xray → VDS

Windows 10/11 x64. Сначала настройте сервер по `01-VDS.md`. Это пример точечных IPv4-маршрутов, без подмены default route и без автоматического перехвата IPv6.

## 1. Файлы

Скачайте архивы из официальных источников:

- Xray для Windows x64: https://github.com/XTLS/Xray-core/releases
- tun2socks для Windows amd64: https://github.com/xjasonlyu/tun2socks/releases
- Wintun: https://www.wintun.net/ — DLL из каталога `bin/amd64`.

Распакуйте в новый каталог, например `C:\split-tunnel`. Не заменяйте существующий `C:\vpn`. Сравните контрольные суммы с опубликованными для выбранного релиза, если они предоставлены; локальную сумму показывает `Get-FileHash -Algorithm SHA256 ПУТЬ_К_АРХИВУ`.

В каталоге должны находиться:

```text
C:\split-tunnel\
  xray.exe
  tun2socks-windows-amd64.exe
  wintun.dll
  client.json
  Start-SelectedTunnel.ps1
```

`client.json` — заполненная копия `client.template.json` из раздела VDS. Геобазы этому минимальному шаблону не нужны: в нём нет правил `geoip:`/`geosite:`. Пример проверялся синтаксически Xray 26.7.28; используйте совместимый релиз и повторите проверку своей версии.

## 2. Xray

Обычный PowerShell, первое окно:

```powershell
Set-Location -LiteralPath 'C:\split-tunnel'
.\xray.exe version
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in @(1080,1081,1082) }
.\xray.exe run -test -config .\client.json
```

Если порты уже заняты, сначала выясните, какая программа их использует. Не останавливайте её вслепую. Если меняете порты шаблона, согласованно измените и Windows-скрипт.

При успешном тесте и свободных портах запустите Xray в этом окне:

```powershell
.\xray.exe run -config .\client.json
```

Во втором окне проверьте Xray без tun2socks:

```powershell
curl.exe --noproxy "*" -4 https://api.ipify.org
curl.exe --noproxy "" --proxy socks5h://127.0.0.1:1082 https://api.ipify.org
```

Первый результат — обычный выход компьютера, второй — выход VDS. Если второй запрос не проходит, TUN пока не запускайте: проверьте соединение с сервером и параметры REALITY. `socks5h` передаёт доменное имя прокси.

## 3. Точечные маршруты

Откройте третье окно PowerShell **от администратора**. Сначала запишите контрольный прямой IP, затем проверьте скрипт и запустите:

```powershell
Set-Location -LiteralPath 'C:\split-tunnel'
curl.exe --noproxy "*" -4 https://checkip.amazonaws.com
Get-Content -LiteralPath .\Start-SelectedTunnel.ps1
# Только если файлы заблокированы после скачивания и вы проверили источник:
Unblock-File -LiteralPath .\Start-SelectedTunnel.ps1
.\Start-SelectedTunnel.ps1 -ServerIPv4 'ВАШ_IPV4_VDS' -Domains @('api.ipify.org')
```

Если политика запуска запрещает скрипты, не отключайте защиту всей системы. Для самостоятельно проверенного файла на личном компьютере можно разрешить локальные скрипты только текущему процессу: `Set-ExecutionPolicy -Scope Process RemoteSigned`. Корпоративная политика может запрещать и это.

Скрипт запускает **свой** tun2socks, создаёт адаптер `apex-tun`, задаёт адрес `198.18.20.1/24` и добавляет временные `/32`-маршруты к A-записям выбранного домена. Адрес VDS, локальные и служебные адреса не допускаются как назначения.

TUN использует порт **1082**: этот вход Xray отправляет выбранный трафик только через VDS. Не направляйте его в `direct`: те же IP-маршруты могут снова захватить исходящие подключения Xray и создать петлю.

## 4. Проверка именно TUN

Пока скрипт работает, во втором окне выполните:

```powershell
curl.exe --noproxy "*" -4 https://api.ipify.org
curl.exe --noproxy "*" -4 https://checkip.amazonaws.com
Get-NetRoute -InterfaceAlias 'apex-tun' -AddressFamily IPv4 |
    Format-Table DestinationPrefix,NextHop,RouteMetric
Get-NetRoute -DestinationPrefix '0.0.0.0/0' |
    Format-Table InterfaceAlias,NextHop,RouteMetric
```

Первый запрос теперь должен показать IP VDS без явного прокси. Контрольный `checkip.amazonaws.com` должен сохранить прежний прямой IP. Если назначения неожиданно разделяют один IP или пересекаются с другими вашими маршрутами, выберите независимый контрольный ресурс. Default route должен остаться на обычном интерфейсе.

Это TCP/IPv4-проверка. Для голосового приложения отдельно проверьте звонок/UDP. Один удачный `curl` не доказывает работу UDP или IPv6.

## 5. Свои ресурсы

Остановите скрипт Ctrl+C, дождитесь сообщения удаления маршрутов и запустите снова со своим списком:

```powershell
.\Start-SelectedTunnel.ps1 -ServerIPv4 'ВАШ_IPV4_VDS' `
    -Domains @('api.ipify.org','example.com')
```

`example.com` здесь только учебный домен — замените его нужными адресами. Для известного публичного IPv4 без DNS используйте параметр `-SelectedIPv4 @('ВАШ_ЦЕЛЕВОЙ_IPV4')`. Скрипт принимает отдельные IP, не CIDR-подсети. Адрес VDS в этот список не включайте.

Скрипт разрешает домены при старте. Это не постоянная доменная маршрутизация: после изменения DNS перезапустите его, а для рабочего автозапуска поручите агенту сделать обновление адресов с удалением устаревших маршрутов. Учитывайте домены входа, API, CDN и обновлений; не копируйте вслепую чужие большие списки IP.

## 6. Отключение

1. Ctrl+C в окне `Start-SelectedTunnel.ps1`: выполняется `finally`, снимаются маршруты этой сессии и останавливается её tun2socks.
2. Ctrl+C в первом окне останавливает Xray.
3. Повторите прямой запрос к `api.ipify.org`: должен вернуться прежний обычный выход.

Не закрывайте окно крестиком вместо Ctrl+C: принудительное завершение может обойти очистку. После аварийного закрытия проверьте сохранённый список и снимите только его маршруты с правильного адаптера:

```powershell
$sessionRoutes = @(Get-Content -LiteralPath 'C:\split-tunnel\created-routes.json' -Raw | ConvertFrom-Json)
foreach ($entry in $sessionRoutes) {
    $adapter = Get-NetAdapter -InterfaceIndex $entry.InterfaceIndex -ErrorAction SilentlyContinue
    if ($adapter -and $adapter.Name -eq 'apex-tun') {
        Get-NetRoute -InterfaceIndex $entry.InterfaceIndex -DestinationPrefix $entry.DestinationPrefix `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.NextHop -eq $entry.NextHop } |
            Remove-NetRoute -Confirm:$false
    }
}
```

Если процесс остался, завершите в диспетчере задач только экземпляр tun2socks из `C:\split-tunnel`, сверив путь. Маршруты создаются в ActiveStore и не переживают перезагрузку. Перезагрузка не удаляет сами файлы.

## Ограничения

- IPv6 остаётся как был; программы могут выбрать его вместо IPv4 и пройти мимо этих правил. Не отключайте IPv6 во всей системе без необходимости. Для полного охвата агент должен отдельно согласовать и настроить IPv6-маршруты либо настройки конкретного приложения.
- DNS использует текущий системный путь. Приложение с DoH может получить другие IP; простые маршруты по системному DNS тогда не совпадут.
- Один IP может принадлежать нескольким сайтам. Правило `/32` охватывает все подключения к этому IP.
- Если Xray остановится, выбранные соединения перестанут работать до восстановления Xray или удаления маршрутов. Это не автоматический failover.
- При штатном завершении tun2socks скрипт снимает маршруты. При принудительном уничтожении скрипта нужна ручная очистка, описанная выше.


---

# Linux: Xray → VDS

Пример для Ubuntu 24.04 LTS / Debian 12 с systemd. Используется локальный прокси Xray: приложение передаёт ему запрос, Xray выбирает прямой выход или VDS по доменному правилу. Это не прозрачный перехват всей системы.

## 1. Установка клиента

Сначала настройте VDS по `01-VDS.md`. Следующие команды выполняются **на вашем Linux-компьютере**, не на VDS.

Если Xray уже установлен, сохраните его конфигурацию и используйте отдельный согласованный экземпляр либо дополните существующий. Команды ниже рассчитаны на новую установку.

```bash
sudo apt update
sudo apt install -y curl unzip nano
curl -fL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o install-xray.sh
less install-xray.sh
sudo bash install-xray.sh install
sudo systemctl stop xray
/usr/local/bin/xray version
ss -ltn 'sport = :1080 or sport = :1081 or sport = :1082'
```

Порты должны быть свободны. Заполните `client.template.json` параметрами из раздела VDS, сохраните полученный `client.json` в текущем каталоге. В нём по умолчанию `ipify.org` и учебный `example.com` идут через VDS, остальное — напрямую. Добавьте свои `domain:...` в это правило. Оно включает и поддомены.

```bash
sudo cp -a /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.before-tutorial
XRAY_USER=$(systemctl show xray -p User --value)
test -n "$XRAY_USER" || XRAY_USER=root
XRAY_GROUP=$(id -gn "$XRAY_USER")
sudo install -o root -g "$XRAY_GROUP" -m 640 client.json /usr/local/etc/xray/config.json
sudo -u "$XRAY_USER" /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

Продолжайте только после успешной проверки. В шаблоне loopback-порты 1080 и 1081 предназначены для программ; 1082 оставлен для совместимости с Windows-комплектом и здесь не используется.

```bash
sudo systemctl enable --now xray
sudo systemctl status xray --no-pager
sudo journalctl -u xray -n 30 --no-pager
```

## 2. Два маршрута

Сравните выбранный домен без прокси и с прокси:

```bash
curl --noproxy '*' -4 https://api.ipify.org
curl --noproxy '' --proxy socks5h://127.0.0.1:1080 https://api.ipify.org
```

В первом ответе — обычный выход компьютера, во втором — выход VDS. Затем проверьте контрольный домен, которого нет в VPN-правиле:

```bash
curl --noproxy '*' -4 https://checkip.amazonaws.com
curl --noproxy '' --proxy socks5h://127.0.0.1:1080 https://checkip.amazonaws.com
```

Оба контрольных ответа должны совпасть с обычным прямым выходом. Вторая команда всё ещё обращается к Xray, но Xray выбирает `direct`. `--noproxy ''` исключает случайный обход прокси из-за переменной NO_PROXY.

Если IP не соответствует ожиданиям, посмотрите `journalctl -u xray -n 50`. На время диагностики `loglevel: info` помогает увидеть теги маршрутов. Не публикуйте полный журнал с адресами ваших подключений.

## 3. Подключение программ

В программе с поддержкой SOCKS укажите SOCKS5, хост `127.0.0.1`, порт `1080`, без логина/пароля. Включите передачу DNS-имени через SOCKS, если есть такой параметр. Программа с HTTP-прокси использует `http://127.0.0.1:1081`.

Обычный HTTP-прокси поддерживает HTTPS через CONNECT, поэтому схема локального адреса всё равно `http://`, а не `https://`.

Для программы, поддерживающей proxy-переменные, можно задать их только на один запуск. Например:

```bash
env http_proxy=http://127.0.0.1:1081 \
    https_proxy=http://127.0.0.1:1081 \
    HTTP_PROXY=http://127.0.0.1:1081 \
    HTTPS_PROXY=http://127.0.0.1:1081 \
    NO_PROXY=localhost,127.0.0.1,::1 \
    no_proxy=localhost,127.0.0.1,::1 \
    curl https://api.ipify.org
```

Замените завершающую команду `curl ...` на запуск своей программы, предварительно проверив её поддержку переменных. Они не перенастраивают уже запущенные приложения и не действуют на любую программу автоматически.

Сразу проверьте нужные действия внутри приложения. При подключении по IP доменное правило не сработает: нужен известный адрес/подсеть в отдельном IP-правиле либо передача доменного имени приложением. В минимальном примере нет обещания, что sniffing восстановит любой домен.

## 4. Изменение правил

```bash
sudo cp -a /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.before-edit
sudo nano /usr/local/etc/xray/config.json
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

Только после успешного теста:

```bash
sudo systemctl restart xray
sudo systemctl status xray --no-pager
```

Повторите проверки двух маршрутов. Не добавляйте правила после завершающего `tcp,udp → direct`: они окажутся недостижимыми.

## 5. Отключение и откат

Сначала верните в приложениях прежние proxy-настройки. Затем отключите новую службу:

```bash
sudo systemctl disable --now xray
```

Переменные из команды `env ...` исчезают вместе с дочерним процессом, системные переменные она не меняет. Для возврата предыдущего конфига после неудачной правки:

```bash
sudo cp -a /usr/local/etc/xray/config.json.before-edit /usr/local/etc/xray/config.json
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
# При успешном тесте:
sudo systemctl restart xray
```

Эта инструкция не меняет iptables/nftables, DNS всей машины и маршруты по умолчанию. UDP и приложения без настройки прокси требуют отдельного решения. На Linux с OpenRC или другим менеджером служб команды systemctl не подходят.


---

# Задание ИИ-агенту

Настрой раздельное туннелирование на моём компьютере и VDS.

Моя система: [Windows 10/11 или дистрибутив Linux]. Через сервер должны идти: [список доменов и, если известны, IP-подсетей]. Остальной трафик оставь напрямую.

Для Windows используй tun2socks → локальный Xray → Xray на VDS. Для Linux — приложения → локальный Xray → Xray на VDS. Не заменяй эти схемы SSH-прокси.

Сначала изучи README и инструкции из приложенного комплекта. Проверь существующие VPN, прокси, маршруты, DNS, занятые порты, архитектуру CPU и версии компонентов. Сохрани исходные настройки. Если конфигурация уже работает, дополни её без запуска дубликатов. Не останавливай сторонние сервисы и не перезаписывай их конфигурации.

Для Windows настрой точечные маршруты к нужным IPv4-адресам. Не меняй маршрут по умолчанию. Не направляй адрес VDS и локальную сеть в TUN. Учитывай общие IP разных сайтов и обновление адресов. Предусмотри удаление устаревших маршрутов и очистку при остановке. В комплекте tun2socks подключается к выделенному SOCKS-входу 1082: этот трафик идёт через VDS, а не обратно в direct. При смене портов согласованно обнови конфигурации и команды.

Для Linux настрой локальные SOCKS/HTTP-порты и доменные правила Xray. Подключи выбранные приложения к прокси. Проверь, поддерживают ли они proxy-переменные и передачу DNS через SOCKS. Если приложение не поддерживает прокси, объясни необходимую дополнительную настройку, не заявляй о готовности прозрачного перехвата.

Отдельно проверь IPv6, DNS/DoH и UDP в выбранных приложениях. Не отключай IPv6 или firewall во всей системе ради успешного демонстрационного теста. Не вводи большие облачные подсети в туннель без объяснения области действия.

Устанавливай компоненты из официальных источников. Для нового соединения настрой VLESS/REALITY, сгенерируй параметры доступа и проверь пригодность target с VDS. Локальные прокси слушают только loopback. Приватный ключ REALITY остаётся на сервере; приватный SSH-ключ не копируется на VDS и не публикуется.

Проверь конфигурации до запуска. Покажи два результата: выбранное подключение выходит через VDS, контрольное — напрямую. Для Windows проверяй TUN без явного указания прокси. Для Linux проверяй оба направления через Xray, а затем целевое приложение. Не подменяй сетевые проверки проверкой синтаксиса JSON.

Подготовь включение, отключение и откат только созданных тобой настроек. После успешной ручной проверки настрой автозапуск с защитой от дубликатов, обновлением выбранных IP и обработкой остановки туннеля. Запиши расположение файлов, версии, проверки и ограничения. Не выводи ключи в отчёт.


---

# Файл client.template.json

Сохраните этот блок в файл с указанным именем.

```json
{
  "log": { "loglevel": "info" },
  "inbounds": [
    { "tag": "apps-socks", "listen": "127.0.0.1", "port": 1080, "protocol": "socks", "settings": { "auth": "noauth", "udp": true, "ip": "127.0.0.1" } },
    { "tag": "apps-http", "listen": "127.0.0.1", "port": 1081, "protocol": "http", "settings": {} },
    { "tag": "tun-socks", "listen": "127.0.0.1", "port": 1082, "protocol": "socks", "settings": { "auth": "noauth", "udp": true, "ip": "127.0.0.1" } }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom", "settings": {} },
    {
      "tag": "vpn", "protocol": "vless",
      "settings": { "vnext": [ { "address": "REPLACE_SERVER_IPV4", "port": 443, "users": [ { "id": "REPLACE_UUID", "encryption": "none", "flow": "xtls-rprx-vision" } ] } ] },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "fingerprint": "chrome", "serverName": "REPLACE_REALITY_HOST", "publicKey": "REPLACE_PUBLIC_KEY", "shortId": "REPLACE_SHORT_ID", "spiderX": "/" }
      }
    },
    { "tag": "block", "protocol": "blackhole", "settings": {} }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "ip": ["0.0.0.0/8", "10.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8"], "inboundTag": ["tun-socks"], "outboundTag": "block" },
      { "type": "field", "inboundTag": ["tun-socks"], "outboundTag": "vpn" },
      { "type": "field", "domain": ["domain:ipify.org", "domain:example.com"], "outboundTag": "vpn" },
      { "type": "field", "network": "tcp,udp", "outboundTag": "direct" }
    ]
  }
}

```


---

# Файл server.template.json

Сохраните этот блок в файл с указанным именем.

```json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "vless-in", "listen": "0.0.0.0", "port": 443, "protocol": "vless",
      "settings": { "clients": [ { "id": "REPLACE_UUID", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "dest": "REPLACE_REALITY_HOST:443", "serverNames": ["REPLACE_REALITY_HOST"], "privateKey": "REPLACE_PRIVATE_KEY", "shortIds": ["REPLACE_SHORT_ID"] }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"], "routeOnly": false }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom", "settings": {} },
    { "tag": "block", "protocol": "blackhole", "settings": {} }
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
      { "type": "field", "ip": ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4", "::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8"], "outboundTag": "block" }
    ]
  }
}

```


---

# Файл Start-SelectedTunnel.ps1

Сохраните этот блок в файл с указанным именем.

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ServerIPv4,
    [string[]]$Domains = @('api.ipify.org'),
    [string[]]$SelectedIPv4 = @()
)

# Run from an elevated PowerShell. Only explicit IPv4 /32 routes are added.
# Xray must already be listening on 127.0.0.1:1082 with the supplied config.
$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run PowerShell as Administrator.'
}
$serverAddress = [Net.IPAddress]::Parse($ServerIPv4)
if ($serverAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'ServerIPv4 must be an IPv4 address.'
}
$ServerIPv4 = $serverAddress.IPAddressToString
$tunName = 'apex-tun'
$tunIp = '198.18.20.1'
$exe = Join-Path $PSScriptRoot 'tun2socks-windows-amd64.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "Missing $exe" }
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'wintun.dll'))) { throw 'Missing wintun.dll' }
if (Get-NetAdapter -Name $tunName -IncludeHidden -ErrorAction SilentlyContinue) {
    throw 'apex-tun already exists. Stop the previous instance first; do not create duplicates.'
}
if (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '198.18.20.*' }) {
    throw '198.18.20.0/24 is already in use. Choose a nonconflicting TUN subnet.'
}
if (-not (Test-NetConnection 127.0.0.1 -Port 1082 -InformationLevel Quiet)) {
    throw 'Xray SOCKS port 1082 is not available.'
}

# Resolve before adding routes. No automatic DNS/IPv6 changes.
$targets = @($SelectedIPv4)
foreach ($domain in $Domains) {
    $answers = @(Resolve-DnsName -Name $domain -Type A -DnsOnly -ErrorAction Stop |
        Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress)
    if ($answers.Count -eq 0) { throw "No IPv4 addresses for $domain" }
    $targets += $answers
}
$targets = @($targets | Sort-Object -Unique)
if ($targets.Count -eq 0) { throw 'No destinations selected.' }
foreach ($target in $targets) {
    $addr = [Net.IPAddress]::Parse($target)
    if ($addr.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw "Not IPv4: $target" }
    $octets = $addr.GetAddressBytes()
    $nonPublic = $octets[0] -in @(0, 10, 127) -or $octets[0] -ge 224 -or
        ($octets[0] -eq 169 -and $octets[1] -eq 254) -or
        ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
        ($octets[0] -eq 192 -and $octets[1] -eq 168) -or
        ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127) -or
        ($octets[0] -eq 198 -and $octets[1] -in @(18, 19))
    if ($nonPublic -or $addr.IPAddressToString -eq $ServerIPv4) {
        throw "Destination cannot be local, reserved, or the VDS itself: $target"
    }
}

$ownedRoutes = @()
$tunProcess = $null
try {
    $tunProcess = Start-Process -FilePath $exe -WorkingDirectory $PSScriptRoot `
        -ArgumentList @('--device', 'tun://apex-tun', '--proxy', 'socks5://127.0.0.1:1082', '--loglevel', 'info') `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $PSScriptRoot 'tun-session.out.log') `
        -RedirectStandardError (Join-Path $PSScriptRoot 'tun-session.err.log')
    $deadline = (Get-Date).AddSeconds(15)
    do {
        if ($tunProcess.HasExited) { throw 'tun2socks exited; inspect tun-session.err.log' }
        $adapter = Get-NetAdapter -Name $tunName -ErrorAction SilentlyContinue
        if ($adapter) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    if (-not $adapter) { throw 'TUN adapter did not appear.' }
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $tunIp -PrefixLength 24 `
        -PolicyStore ActiveStore | Out-Null
    $nic = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter ("InterfaceIndex = {0}" -f $adapter.ifIndex)
    if ($nic) {
        Invoke-CimMethod -InputObject $nic -MethodName SetTcpipNetbios `
            -Arguments @{ TcpipNetbiosOptions = [uint32]2 } | Out-Null
    }
    foreach ($target in $targets) {
        $route = New-NetRoute -DestinationPrefix "$target/32" -InterfaceIndex $adapter.ifIndex `
            -NextHop $tunIp -RouteMetric 5 -PolicyStore ActiveStore
        $ownedRoutes += $route
    }
    $ownedRoutes | Select-Object DestinationPrefix, InterfaceIndex, NextHop |
        ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'created-routes.json') -Encoding UTF8
    Write-Host 'Selected IPv4 routes are active. Default route and IPv6 are unchanged.'
    $ownedRoutes | Format-Table DestinationPrefix, InterfaceIndex, NextHop
    Write-Host 'Test in another terminal. Press Ctrl+C here to remove these routes and stop this tun2socks.'
    while (-not $tunProcess.HasExited) { Start-Sleep -Milliseconds 500 }
    throw 'tun2socks stopped; removing routes.'
}
finally {
    foreach ($route in $ownedRoutes) {
        $route | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    }
    if ($tunProcess -and -not $tunProcess.HasExited) {
        Stop-Process -Id $tunProcess.Id -ErrorAction SilentlyContinue
    }
    Write-Host 'Session routes removed; this tun2socks stopped. Xray was not stopped.'
}

```
