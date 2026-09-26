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
