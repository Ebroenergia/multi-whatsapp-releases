<#
  Instalador de Ebro Multi WhatsApp en un solo comando (PowerShell, sin administrador).

  Uso (PowerShell normal, sin administrador, Windows 10/11):
      irm https://raw.githubusercontent.com/Ebroenergia/multi-whatsapp-releases/main/install.ps1 | iex

  Mismo esquema que el instalador de Ebro Transcripciones:
    1. Descarga la ultima version publicada en latest.json (releases de multi-whatsapp-releases).
    2. La deja en %LocalAppData%\Programs\Ebro Multi WhatsApp (reemplaza si ya existia).
       Las sesiones de WhatsApp NO se tocan: viven en %AppData%\Ebro Multi WhatsApp.
    3. Accesos directos en Menu Inicio y Escritorio.
    4. Arranque con Windows (HKCU\...\Run, en segundo plano con --background).
    5. Entrada en "Aplicaciones" de Windows para desinstalar.
    6. Abre la app: se anade cada cuenta con el + y se escanea su QR desde el movil.

  Lo publica scripts/release.ps1 (lo sube a la rama main del repo publico de releases).

  Todo va dentro de un bloque & { } para no dejar variables ni preferencias en la sesion del usuario.
#>
& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # la barra de progreso de PS 5.1 ralentiza mucho la descarga

$Feed       = 'https://github.com/Ebroenergia/multi-whatsapp-releases/releases/latest/download/latest.json'
$AppName    = 'Ebro Multi WhatsApp'
$ExeName    = 'MultiWhatsApp.exe'
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
$TargetExe  = Join-Path $InstallDir $ExeName
$RunKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValue   = 'EbroMultiWhatsApp'
$UninstKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EbroMultiWhatsApp'

function Paso($msg) { Write-Host ("  > " + $msg) -ForegroundColor Cyan }

Write-Host ''
Write-Host "=== Instalador de $AppName ===" -ForegroundColor Green
Write-Host ''

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# 1) Que version hay publicada
Paso 'Consultando la ultima version publicada...'
$latest  = Invoke-RestMethod -Uri ($Feed + '?t=' + [DateTime]::UtcNow.Ticks) -UseBasicParsing
$version = [string]$latest.version
$zipUrl  = [string]$latest.url
if (-not $version -or -not $zipUrl) { throw "latest.json no tiene version/url: $($latest | ConvertTo-Json -Compress)" }
Paso "Version $version"

# 2) Cerrar la app si esta abierta (reinstalacion / actualizacion a mano)
$running = Get-Process -Name 'MultiWhatsApp' -ErrorAction SilentlyContinue
if ($running) {
    Paso 'La app estaba abierta; cerrandola para reemplazarla...'
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

# 3) Descargar a un temporal, descomprimir aparte y mover (nunca dejamos una instalacion a medias)
$tmpZip = Join-Path $env:TEMP "EbroMultiWhatsApp-$version.zip"
$tmpDir = "$InstallDir.new"
if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }
Paso 'Descargando la app (~120 MB, puede tardar un par de minutos)...'
$sw = [Diagnostics.Stopwatch]::StartNew()
$wc = New-Object System.Net.WebClient
try { $wc.DownloadFile($zipUrl, $tmpZip) } finally { $wc.Dispose() }
$sw.Stop()
$mb = [math]::Round((Get-Item $tmpZip).Length / 1MB, 1)
if ($mb -lt 50) { Remove-Item $tmpZip -Force; throw "La descarga ocupa solo $mb MB; no parece el paquete completo." }
Paso ("Descargados {0} MB en {1:0} s" -f $mb, $sw.Elapsed.TotalSeconds)

Paso 'Descomprimiendo...'
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
Remove-Item $tmpZip -Force
if (-not (Test-Path (Join-Path $tmpDir $ExeName))) { throw "El paquete no trae $ExeName." }

# Quitar la marca "descargado de Internet" para que SmartScreen no lo bloquee al arrancar
Get-ChildItem -LiteralPath $tmpDir -Recurse | Unblock-File -ErrorAction SilentlyContinue

if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir) | Out-Null
Move-Item -LiteralPath $tmpDir -Destination $InstallDir
Paso "Instalado en $InstallDir"

# 4) Accesos directos (Menu Inicio + Escritorio). La app reescribe el del Menu Inicio
#    al arrancar para anadirle su AppUserModelID (sin el, Windows no muestra sus notificaciones).
function New-Shortcut($lnk) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath       = $TargetExe
        $sc.WorkingDirectory = $InstallDir
        $sc.IconLocation     = "$TargetExe,0"
        $sc.Description      = $AppName
        $sc.Save()
    } catch { Write-Host "    (no se pudo crear el acceso directo $lnk)" -ForegroundColor DarkYellow }
}
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk")
New-Shortcut (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) "$AppName.lnk")
Paso 'Accesos directos creados (Menu Inicio y Escritorio)'

# 5) Arranque con Windows en segundo plano (mismo nombre de valor que usa la app)
New-Item -Path $RunKey -Force | Out-Null
Set-ItemProperty -Path $RunKey -Name $RunValue -Value "`"$TargetExe`" --background"
# Si Windows la tenia "Deshabilitada" en Aplicaciones de inicio (reinstalacion), quitar esa marca
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -Name $RunValue -ErrorAction SilentlyContinue
Paso 'Arranque automatico con Windows configurado'

# 6) Registro en "Aplicaciones" de Windows (para desinstalar desde Configuracion)
New-Item -Path $UninstKey -Force | Out-Null
Set-ItemProperty -Path $UninstKey -Name 'DisplayName'     -Value $AppName
Set-ItemProperty -Path $UninstKey -Name 'DisplayIcon'     -Value $TargetExe
Set-ItemProperty -Path $UninstKey -Name 'DisplayVersion'  -Value $version
Set-ItemProperty -Path $UninstKey -Name 'Publisher'       -Value 'Ebroenergia'
Set-ItemProperty -Path $UninstKey -Name 'InstallLocation' -Value $InstallDir
Set-ItemProperty -Path $UninstKey -Name 'UninstallString' -Value "`"$TargetExe`" --uninstall"
Set-ItemProperty -Path $UninstKey -Name 'NoModify' -Value 1 -Type DWord
Set-ItemProperty -Path $UninstKey -Name 'NoRepair' -Value 1 -Type DWord

# 7) Abrir la app
Paso 'Abriendo la app...'
try {
    Start-Process -FilePath $TargetExe -WorkingDirectory $InstallDir
} catch {
    # "Una directiva de Control de aplicaciones bloqueo este archivo": el exe no va firmado y
    # Windows no lo deja arrancar. Puede ser Smart App Control (Windows 11) o una politica de TI
    # (WDAC / AppLocker / Intune); la solucion es distinta, asi que dejamos el diagnostico hecho.
    $sac = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
    $sacTxt = switch ($sac) { 0 { 'desactivado' } 1 { 'ACTIVADO' } 2 { 'en evaluacion' } default { 'no existe en este PC' } }
    $ev = $null
    try {
        $ev = Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 50 -ErrorAction Stop |
              Where-Object { $_.Id -in 3033, 3034, 3076, 3077, 3089 } | Select-Object -First 1
    } catch { }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'La app quedo instalada, pero Windows NO la deja abrirse (Control de aplicaciones).' -ForegroundColor Yellow
    Write-Host 'Copia desde aqui hasta el final y enviaselo a Santiago Carvajal:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "  Equipo: $env:COMPUTERNAME  Usuario: $env:USERNAME"
    Write-Host "  Windows: $($os.Caption) $($os.Version)"
    Write-Host "  Smart App Control: $sacTxt"
    if ($ev) {
        $msg = ($ev.Message -split "`r?`n" | Where-Object { $_ } | Select-Object -First 3) -join ' '
        Write-Host "  Evento $($ev.Id) ($($ev.TimeCreated)): $msg"
    } else {
        Write-Host '  Evento de Code Integrity: no se pudo leer'
    }
    Write-Host ''
    return
}

Write-Host ''
Write-Host "Listo. $AppName $version instalada y arrancara sola con Windows." -ForegroundColor Green
Write-Host 'Anade cada cuenta con el boton + y escanea el QR desde el movil (WhatsApp > Dispositivos vinculados).'
Write-Host ''
}
