[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$InstanceDirectory,
    [switch]$SkipLauncher,
    [switch]$UpdateOnly,
    [switch]$Gui,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PackRepository = 'tecteccruz-dot/NeoModPack'
$LauncherRepository = 'sklauncher/binaries'
$LauncherExe = Join-Path $env:LOCALAPPDATA 'Programs\sklauncher\sklauncher.exe'
$LauncherInstances = Join-Path $env:APPDATA '.sklauncher\instances.json'
$ApiHeaders = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'NeoModPack-Installer'
}
$script:MainForm = $null
$script:StatusLabel = $null
$script:DetailLabel = $null
$script:ProgressBar = $null

function Initialize-Gui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()

    $script:MainForm = New-Object Windows.Forms.Form
    $script:MainForm.Text = if ($UpdateOnly) { 'Actualizar Neo Modpack' } else { 'Instalar Neo Modpack' }
    $script:MainForm.ClientSize = New-Object Drawing.Size(540, 190)
    $script:MainForm.StartPosition = 'CenterScreen'
    $script:MainForm.FormBorderStyle = 'FixedDialog'
    $script:MainForm.MaximizeBox = $false
    $script:MainForm.MinimizeBox = $true
    $script:MainForm.ControlBox = $false

    $title = New-Object Windows.Forms.Label
    $title.Text = 'Neo Modpack'
    $title.Font = New-Object Drawing.Font('Segoe UI', 18, [Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object Drawing.Point(24, 18)
    $script:MainForm.Controls.Add($title)

    $script:StatusLabel = New-Object Windows.Forms.Label
    $script:StatusLabel.Text = 'Preparando...'
    $script:StatusLabel.Font = New-Object Drawing.Font('Segoe UI', 10)
    $script:StatusLabel.AutoSize = $false
    $script:StatusLabel.Size = New-Object Drawing.Size(492, 28)
    $script:StatusLabel.Location = New-Object Drawing.Point(27, 67)
    $script:MainForm.Controls.Add($script:StatusLabel)

    $script:ProgressBar = New-Object Windows.Forms.ProgressBar
    $script:ProgressBar.Minimum = 0
    $script:ProgressBar.Maximum = 100
    $script:ProgressBar.Value = 0
    $script:ProgressBar.Size = New-Object Drawing.Size(486, 25)
    $script:ProgressBar.Location = New-Object Drawing.Point(27, 101)
    $script:MainForm.Controls.Add($script:ProgressBar)

    $script:DetailLabel = New-Object Windows.Forms.Label
    $script:DetailLabel.Text = '0%'
    $script:DetailLabel.Font = New-Object Drawing.Font('Segoe UI', 9)
    $script:DetailLabel.AutoSize = $false
    $script:DetailLabel.TextAlign = 'MiddleCenter'
    $script:DetailLabel.Size = New-Object Drawing.Size(486, 24)
    $script:DetailLabel.Location = New-Object Drawing.Point(27, 132)
    $script:MainForm.Controls.Add($script:DetailLabel)

    $script:MainForm.Show()
    [Windows.Forms.Application]::DoEvents()
}

function Set-ProgressState([int]$Percent, [string]$Detail, [switch]$Indeterminate) {
    if ($Gui -and $script:MainForm) {
        if ($Indeterminate) {
            $script:ProgressBar.Style = 'Marquee'
            $script:ProgressBar.MarqueeAnimationSpeed = 25
        }
        else {
            $script:ProgressBar.Style = 'Continuous'
            $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
        }
        $script:DetailLabel.Text = $Detail
        [Windows.Forms.Application]::DoEvents()
    }
    elseif (-not $Indeterminate) {
        Write-Progress -Activity 'Neo Modpack' -Status $Detail -PercentComplete $Percent
    }
}

function Show-Result([string]$Message, [bool]$Success) {
    if (-not $Gui) { return }
    $icon = if ($Success) { 'Information' } else { 'Error' }
    $title = if ($Success) { 'Neo Modpack' } else { 'No se pudo completar' }
    [Windows.Forms.MessageBox]::Show($Message, $title, 'OK', $icon) | Out-Null
}

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
    if ($Gui -and $script:StatusLabel) {
        $script:StatusLabel.Text = $Message
        Set-ProgressState 0 $Message -Indeterminate
    }
}

function Get-LatestRelease([string]$Repository) {
    $uri = "https://api.github.com/repos/$Repository/releases/latest"
    try {
        return Invoke-RestMethod -UseBasicParsing -Headers $ApiHeaders -Uri $uri
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) {
            throw "El repositorio $Repository todavia no tiene una Release publicada."
        }
        throw
    }
}

function Download-File([string]$Uri, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = New-Object Net.Http.HttpClient($handler)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('NeoModPack-Installer')
    try {
        $response = $client.GetAsync($Uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        $response.EnsureSuccessStatusCode() | Out-Null
        $total = $response.Content.Headers.ContentLength
        $inputStream = $response.Content.ReadAsStreamAsync().Result
        $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $buffer = New-Object byte[] (1024 * 1024)
            [long]$downloaded = 0
            while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $outputStream.Write($buffer, 0, $read)
                $downloaded += $read
                if ($total -and $total -gt 0) {
                    $percent = [int][Math]::Floor(($downloaded * 100.0) / $total)
                    $detail = '{0}%  —  {1:N1} de {2:N1} MB' -f $percent, ($downloaded / 1MB), ($total / 1MB)
                    Set-ProgressState $percent $detail
                }
                else {
                    Set-ProgressState 0 ('{0:N1} MB descargados' -f ($downloaded / 1MB)) -Indeterminate
                }
            }
        }
        finally {
            if ($outputStream) { $outputStream.Dispose() }
            if ($inputStream) { $inputStream.Dispose() }
        }
    }
    finally {
        if ($response) { $response.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}

function Install-SKLauncher {
    if (Test-Path -LiteralPath $LauncherExe) {
        Write-Host "SKLauncher encontrado: $LauncherExe"
        return
    }

    Write-Step 'Descargando SKLauncher desde su repositorio oficial'
    $release = Get-LatestRelease $LauncherRepository
    $asset = $release.assets | Where-Object { $_.name -match '(?i)setup.*\.exe$|SKlauncher-.*-setup\.exe$' } | Select-Object -First 1
    if (-not $asset) {
        Start-Process 'https://docs.skmedix.pl/getting-started/downloads'
        throw 'No encontre el instalador automatico de SKLauncher. Se abrio su pagina oficial de descarga.'
    }

    $setup = Join-Path $env:TEMP $asset.name
    Download-File $asset.browser_download_url $setup
    Write-Host "Ejecutando $($asset.name)..."
    $process = Start-Process -FilePath $setup -Wait -PassThru
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $LauncherExe)) {
        throw 'SKLauncher no termino de instalarse correctamente.'
    }
}

function Expand-SafeArchive([string]$ArchivePath, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('/', '\')
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $relative))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw "El ZIP contiene una ruta insegura: $($entry.FullName)"
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                continue
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Verify-PackFiles([string]$ExtractedRoot, $PackManifest) {
    Write-Step 'Verificando los archivos extraidos'
    foreach ($file in $PackManifest.files) {
        $path = Join-Path $ExtractedRoot ($file.path.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Falta un archivo del paquete: $($file.path)"
        }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $file.sha256) {
            throw "La verificacion fallo para: $($file.path)"
        }
    }
}

function Test-InstalledPack([string]$GameDirectory, $PackManifest) {
    foreach ($file in $PackManifest.files) {
        if ($file.category -ne 'managed') { continue }
        $path = Join-Path $GameDirectory ($file.path.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-Host "Falta: $($file.path)" -ForegroundColor Yellow
            return $false
        }

        $rootName = ($file.path -split '/')[0]
        if ($rootName -in @('mods', 'resourcepacks', 'shaderpacks', 'greatsage-voice')) {
            $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $file.sha256) {
                Write-Host "Dañado o modificado: $($file.path)" -ForegroundColor Yellow
                return $false
            }
        }
    }
    return $true
}

function Update-ResourcePackSelection([string]$PlayerOptions, [string]$DefaultOptions) {
    if (-not (Test-Path -LiteralPath $PlayerOptions) -or -not (Test-Path -LiteralPath $DefaultOptions)) {
        return
    }

    $defaultLine = Get-Content -LiteralPath $DefaultOptions -Encoding UTF8 |
        Where-Object { $_ -match '^resourcePacks:' } |
        Select-Object -First 1
    if (-not $defaultLine) {
        Write-Host 'El options.txt publicado no contiene resourcePacks; no se modifico nada.' -ForegroundColor Yellow
        return
    }

    if ($Gui) {
        $choice = [Windows.Forms.MessageBox]::Show(
            '¿Quieres aplicar la selección de packs de recursos recomendada?',
            'Packs de recursos', 'YesNo', 'Question'
        )
        $accepted = $choice -eq [Windows.Forms.DialogResult]::Yes
    }
    else {
        $answer = Read-Host 'Quieres aplicar la seleccion de packs de recursos recomendada? [s/N]'
        $accepted = $answer -match '^(?i:s|si|sí|y|yes)$'
    }
    if (-not $accepted) {
        Write-Host 'Se conservaron tus packs de recursos actuales.'
        return
    }

    $lines = @(Get-Content -LiteralPath $PlayerOptions -Encoding UTF8)
    $found = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^resourcePacks:') {
            $lines[$index] = $defaultLine
            $found = $true
            break
        }
    }
    if (-not $found) { $lines += $defaultLine }
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllLines($PlayerOptions, [string[]]$lines, $utf8NoBom)
    Write-Host 'La seleccion resourcePacks fue actualizada.' -ForegroundColor Green
}

function Install-PackFiles([string]$ExtractedRoot, [string]$GameDirectory, $PackManifest) {
    Write-Step 'Instalando el contenido del modpack'
    New-Item -ItemType Directory -Force -Path $GameDirectory | Out-Null
    $rollback = Join-Path (Split-Path -Parent $GameDirectory) ('.rollback-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $rollback | Out-Null
    $replaced = New-Object System.Collections.Generic.List[string]

    $roots = $PackManifest.files |
        Where-Object { $_.category -eq 'managed' } |
        ForEach-Object { ($_.path -split '/')[0] } |
        Sort-Object -Unique

    try {
        foreach ($name in $roots) {
            $source = Join-Path $ExtractedRoot $name
            if (-not (Test-Path -LiteralPath $source)) { continue }
            $target = Join-Path $GameDirectory $name
            if (Test-Path -LiteralPath $target) {
                Move-Item -LiteralPath $target -Destination (Join-Path $rollback $name)
                $replaced.Add($name)
            }
            Move-Item -LiteralPath $source -Destination $target
        }

        $defaultOptions = Join-Path $ExtractedRoot '.neo\defaults\options.txt'
        $playerOptions = Join-Path $GameDirectory 'options.txt'
        if ((Test-Path -LiteralPath $defaultOptions) -and -not (Test-Path -LiteralPath $playerOptions)) {
            Copy-Item -LiteralPath $defaultOptions -Destination $playerOptions
        }
    }
    catch {
        foreach ($name in $replaced) {
            $target = Join-Path $GameDirectory $name
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            Move-Item -LiteralPath (Join-Path $rollback $name) -Destination $target
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $rollback) { Remove-Item -LiteralPath $rollback -Recurse -Force }
    }
}

function Set-ObjectProperty($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Select-LauncherMode {
    if ($Gui) {
        $choice = [Windows.Forms.MessageBox]::Show(
            "¿Qué launcher usarás?`n`nSí  = SKLauncher`nNo = Minecraft Launcher oficial",
            'Seleccionar launcher', 'YesNo', 'Question'
        )
        if ($choice -eq [Windows.Forms.DialogResult]::Yes) { return 'sklauncher' }
        return 'official'
    }

    Write-Host "`nSelecciona el launcher:"
    Write-Host '  1. SKLauncher'
    Write-Host '  2. Minecraft Launcher oficial'
    $answer = Read-Host 'Escribe 1 o 2'
    if ($answer -eq '1') { return 'sklauncher' }
    return 'official'
}

function Register-SKLauncherInstance([string]$GameDirectory, $PackManifest) {
    Write-Step 'Registrando la instancia en SKLauncher'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LauncherInstances) | Out-Null
    if (Test-Path -LiteralPath $LauncherInstances) {
        Copy-Item -LiteralPath $LauncherInstances -Destination "$LauncherInstances.bak" -Force
        $document = Get-Content -Raw -LiteralPath $LauncherInstances -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        $document = [pscustomobject]@{ instances = @() }
    }

    $loaderVersion = $PackManifest.loader -replace '^neoforge-', ''
    $desiredVersionId = "$($PackManifest.minecraft_version)-neoforge-$loaderVersion"
    $instance = $document.instances | Where-Object { $_.id -eq 'neo-modpack' } | Select-Object -First 1
    if (-not $instance) {
        $instance = [pscustomobject]@{
            id = 'neo-modpack'; name = 'Neo Modpack'; type = 'custom'; installComplete = $false
            icon = 'Grass'; versionId = ''; gameType = 'neoforge'; minecraftVersion = ''
            loaderVersion = ''; directory = ''; createdAt = [DateTime]::UtcNow.ToString('o')
            playTime = 0; sessionCount = 0
        }
        $document.instances = @($document.instances) + $instance
    }
    elseif ($instance.versionId -ne $desiredVersionId) {
        Set-ObjectProperty $instance 'installComplete' $false
    }

    Set-ObjectProperty $instance 'name' 'Neo Modpack'
    Set-ObjectProperty $instance 'versionId' $desiredVersionId
    Set-ObjectProperty $instance 'minecraftVersion' $PackManifest.minecraft_version
    Set-ObjectProperty $instance 'loaderVersion' $loaderVersion
    Set-ObjectProperty $instance 'directory' $GameDirectory
    $document | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $LauncherInstances -Encoding UTF8
}

if ($Gui) { Initialize-Gui }

try {
    Write-Step 'Comprobando requisitos'
    Write-Host 'Git:         no es necesario'
    Write-Host 'Python:      no es necesario'
    Write-Host 'CurseForge:  no es necesario'
    Write-Host 'Java:        lo administra el launcher elegido'
    Write-Host "PowerShell:  $($PSVersionTable.PSVersion)"

    if ($CheckOnly) {
        Write-Host "`nComprobacion completada." -ForegroundColor Green
        exit 0
    }

    if (-not $InstanceDirectory) {
        if ($InstallRoot) { $InstanceDirectory = $InstallRoot }
        else { $InstanceDirectory = (Get-Location).Path }
    }
    $gameDirectory = [IO.Path]::GetFullPath($InstanceDirectory)
    New-Item -ItemType Directory -Force -Path $gameDirectory | Out-Null
    $statePath = Join-Path $gameDirectory '.neo-state.json'
    $installedManifestPath = Join-Path $gameDirectory '.neo-pack-manifest.json'
    $savedDefaultOptions = Join-Path $gameDirectory '.neo-default-options.txt'
    $playerOptions = Join-Path $gameDirectory 'options.txt'
    $hadPlayerOptions = Test-Path -LiteralPath $playerOptions

    $launcherMode = $null
    if ($UpdateOnly -and (Test-Path -LiteralPath $statePath)) {
        $existingState = Get-Content -Raw -LiteralPath $statePath -Encoding UTF8 | ConvertFrom-Json
        $launcherMode = $existingState.launcher_mode
    }
    if ($launcherMode -notin @('sklauncher', 'official')) {
        Write-Step 'Seleccionando launcher'
        $launcherMode = Select-LauncherMode
    }
    if ($launcherMode -eq 'sklauncher' -and -not $SkipLauncher) {
        Install-SKLauncher
    }

    Write-Step 'Buscando la ultima version de Neo Modpack'
    $release = Get-LatestRelease $PackRepository
    $manifestAsset = $release.assets | Where-Object { $_.name -eq 'manifest.json' } | Select-Object -First 1
    if (-not $manifestAsset) { throw "La Release $($release.tag_name) no contiene manifest.json." }

    $working = Join-Path $env:TEMP ('NeoModPack-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $working | Out-Null
    try {
        $manifestFile = Join-Path $working 'manifest.json'
        Download-File $manifestAsset.browser_download_url $manifestFile
        $manifest = Get-Content -Raw -LiteralPath $manifestFile -Encoding UTF8 | ConvertFrom-Json
        $archiveAsset = $release.assets | Where-Object { $_.name -eq $manifest.archive.filename } | Select-Object -First 1
        if (-not $archiveAsset) { throw "La Release no contiene $($manifest.archive.filename)." }

        if ($UpdateOnly) {
            Write-Step 'Comprobando la instalacion actual'
            if ((Test-Path -LiteralPath $statePath) -and (Test-Path -LiteralPath $installedManifestPath)) {
                $installedState = Get-Content -Raw -LiteralPath $statePath -Encoding UTF8 | ConvertFrom-Json
                $installedManifest = Get-Content -Raw -LiteralPath $installedManifestPath -Encoding UTF8 | ConvertFrom-Json
                if (($installedState.version -eq $manifest.version) -and (Test-InstalledPack $gameDirectory $installedManifest)) {
                    Write-Host "`nNeo Modpack $($manifest.version) ya esta actualizado y completo." -ForegroundColor Green
                    Update-ResourcePackSelection $playerOptions $savedDefaultOptions
                    if ($launcherMode -eq 'sklauncher' -and -not $SkipLauncher) {
                        Register-SKLauncherInstance $gameDirectory $installedManifest
                    }
                    Show-Result "Neo Modpack $($manifest.version) ya está actualizado y completo." $true
                    exit 0
                }
                if ($installedState.version -ne $manifest.version) {
                    Write-Host "Nueva version: $($installedState.version) -> $($manifest.version)"
                }
                else {
                    Write-Host 'Se reparara la instalacion actual.'
                }
            }
            else {
                Write-Host 'No encontre una instalacion completa; se realizara la instalacion inicial.'
            }
        }

        Write-Step "Descargando Neo Modpack $($manifest.version)"
        $archiveFile = Join-Path $working $manifest.archive.filename
        Download-File $archiveAsset.browser_download_url $archiveFile
        if ((Get-Item -LiteralPath $archiveFile).Length -ne [long]$manifest.archive.size) {
            throw 'El tamaño del archivo descargado no coincide con el manifiesto.'
        }
        $archiveHash = (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($archiveHash -ne $manifest.archive.sha256) {
            throw 'El SHA-256 del paquete descargado no coincide.'
        }

        $extracted = Join-Path $working 'extracted'
        New-Item -ItemType Directory -Force -Path $extracted | Out-Null
        Write-Step 'Extrayendo el modpack'
        Expand-SafeArchive $archiveFile $extracted
        $internalManifestPath = Join-Path $extracted '.neo\pack-manifest.json'
        if (-not (Test-Path -LiteralPath $internalManifestPath)) { throw 'El paquete no contiene su manifiesto interno.' }
        $internalManifest = Get-Content -Raw -LiteralPath $internalManifestPath -Encoding UTF8 | ConvertFrom-Json
        Verify-PackFiles $extracted $internalManifest
        Install-PackFiles $extracted $gameDirectory $internalManifest

        $publishedOptions = Join-Path $extracted '.neo\defaults\options.txt'
        if (Test-Path -LiteralPath $publishedOptions) {
            Copy-Item -LiteralPath $publishedOptions -Destination $savedDefaultOptions -Force
            if ($UpdateOnly -and $hadPlayerOptions) {
                Update-ResourcePackSelection $playerOptions $savedDefaultOptions
            }
        }

        $state = [pscustomobject]@{
            version = $manifest.version
            installed_at = [DateTime]::UtcNow.ToString('o')
            game_directory = $gameDirectory
            launcher_mode = $launcherMode
            archive_sha256 = $manifest.archive.sha256
        }
        $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
        Copy-Item -LiteralPath $internalManifestPath -Destination $installedManifestPath -Force

        if (-not $UpdateOnly) {
            $updaterAsset = $release.assets | Where-Object { $_.name -eq 'Actualizar.bat' } | Select-Object -First 1
            if ($updaterAsset) {
                Write-Step 'Preparando el actualizador'
                Download-File $updaterAsset.browser_download_url (Join-Path $gameDirectory 'Actualizar.bat')
            }
        }

        if ($launcherMode -eq 'sklauncher' -and -not $SkipLauncher) {
            Register-SKLauncherInstance $gameDirectory $internalManifest
        }
        Write-Host "`nNeo Modpack $($manifest.version) quedo instalado en:`n$gameDirectory" -ForegroundColor Green
        Set-ProgressState 100 '100% — Instalación completada'
        Show-Result "Neo Modpack $($manifest.version) quedó listo.`n`nTodos los archivos están en:`n$gameDirectory" $true
    }
    finally {
        if ($working -and (Test-Path -LiteralPath $working)) {
            Remove-Item -LiteralPath $working -Recurse -Force
        }
    }
    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Show-Result $_.Exception.Message $false
    exit 1
}
