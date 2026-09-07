[CmdletBinding()]
param(
    [string]$InstallRoot,
    [switch]$SkipLauncher,
    [switch]$UpdateOnly,
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

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
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
    Invoke-WebRequest -UseBasicParsing -Headers $ApiHeaders -Uri $Uri -OutFile $Destination
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

    $answer = Read-Host 'Quieres aplicar la seleccion de packs de recursos recomendada? [s/N]'
    if ($answer -notmatch '^(?i:s|si|sí|y|yes)$') {
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

try {
    Write-Step 'Comprobando requisitos'
    Write-Host 'Git:         no es necesario'
    Write-Host 'Python:      no es necesario'
    Write-Host 'CurseForge:  no es necesario'
    Write-Host 'Java:        lo administra SKLauncher'
    Write-Host "PowerShell:  $($PSVersionTable.PSVersion)"

    if ($CheckOnly) {
        Write-Host "`nComprobacion completada." -ForegroundColor Green
        exit 0
    }

    if (-not $SkipLauncher) { Install-SKLauncher }

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

        if (-not $InstallRoot) {
            $defaultRoot = Join-Path $env:LOCALAPPDATA 'NeoModPack'
            $defaultState = Join-Path $defaultRoot 'state.json'
            if ($UpdateOnly -and (Test-Path -LiteralPath $defaultState)) {
                $savedState = Get-Content -Raw -LiteralPath $defaultState -Encoding UTF8 | ConvertFrom-Json
                if ($savedState.game_directory) {
                    $InstallRoot = Split-Path -Parent $savedState.game_directory
                }
            }
            if (-not $InstallRoot) {
                $answer = Read-Host "Carpeta de instalacion [$defaultRoot]"
                if ([string]::IsNullOrWhiteSpace($answer)) { $InstallRoot = $defaultRoot }
                else { $InstallRoot = [Environment]::ExpandEnvironmentVariables($answer.Trim('"')) }
            }
        }
        $InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
        $gameDirectory = Join-Path $InstallRoot 'game'
        $playerOptions = Join-Path $gameDirectory 'options.txt'
        $savedDefaultOptions = Join-Path $InstallRoot 'defaults\options.txt'
        $hadPlayerOptions = Test-Path -LiteralPath $playerOptions

        if ($UpdateOnly) {
            Write-Step 'Comprobando la instalacion actual'
            $statePath = Join-Path $InstallRoot 'state.json'
            $installedManifestPath = Join-Path $InstallRoot 'pack-manifest.json'
            if ((Test-Path -LiteralPath $statePath) -and (Test-Path -LiteralPath $installedManifestPath)) {
                $installedState = Get-Content -Raw -LiteralPath $statePath -Encoding UTF8 | ConvertFrom-Json
                $installedManifest = Get-Content -Raw -LiteralPath $installedManifestPath -Encoding UTF8 | ConvertFrom-Json
                if (($installedState.version -eq $manifest.version) -and (Test-InstalledPack $gameDirectory $installedManifest)) {
                    Write-Host "`nNeo Modpack $($manifest.version) ya esta actualizado y completo." -ForegroundColor Green
                    Update-ResourcePackSelection $playerOptions $savedDefaultOptions
                    if (-not $SkipLauncher) { Register-SKLauncherInstance $gameDirectory $installedManifest }
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
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $savedDefaultOptions) | Out-Null
            Copy-Item -LiteralPath $publishedOptions -Destination $savedDefaultOptions -Force
            if ($UpdateOnly -and $hadPlayerOptions) {
                Update-ResourcePackSelection $playerOptions $savedDefaultOptions
            }
        }

        New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
        $state = [pscustomobject]@{
            version = $manifest.version
            installed_at = [DateTime]::UtcNow.ToString('o')
            game_directory = $gameDirectory
            archive_sha256 = $manifest.archive.sha256
        }
        $state | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallRoot 'state.json') -Encoding UTF8
        Copy-Item -LiteralPath $internalManifestPath -Destination (Join-Path $InstallRoot 'pack-manifest.json') -Force

        if (-not $SkipLauncher) {
            Register-SKLauncherInstance $gameDirectory $internalManifest
            if (-not $UpdateOnly) { Start-Process -FilePath $LauncherExe }
        }
        Write-Host "`nNeo Modpack $($manifest.version) quedo instalado en:`n$gameDirectory" -ForegroundColor Green
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
    exit 1
}
