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
