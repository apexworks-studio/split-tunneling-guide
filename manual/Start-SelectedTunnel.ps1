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
