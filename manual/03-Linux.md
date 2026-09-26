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
