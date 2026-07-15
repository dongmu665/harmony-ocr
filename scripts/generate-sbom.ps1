param(
    [Parameter(Mandatory = $true)]
    [string] $RepositoryRoot,

    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:UnsafeGitEnvironmentVariables = @(
    'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_CONFIG', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_COUNT',
    'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_NOSYSTEM', 'GIT_OBJECT_DIRECTORY',
    'GIT_DIR', 'GIT_WORK_TREE', 'GIT_IMPLICIT_WORK_TREE', 'GIT_GRAFT_FILE', 'GIT_INDEX_FILE',
    'GIT_REPLACE_REF_BASE', 'GIT_PREFIX', 'GIT_SHALLOW_FILE', 'GIT_COMMON_DIR', 'GIT_NAMESPACE'
)

function Assert-SafeGitEnvironment {
    foreach ($name in $script:UnsafeGitEnvironmentVariables) {
        $value = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
        if (-not [string]::IsNullOrEmpty($value)) {
            throw "Unsafe Git environment variable is set: $name"
        }
    }
}

function Invoke-GitValue {
    param([string] $Root, [string[]] $Arguments)
    Assert-SafeGitEnvironment
    $lines = @(& git -C $Root @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: $($Arguments -join ' ')"
    }
    return ([string]$lines[0]).Trim()
}

function Test-PathInside {
    param([string] $Candidate, [string] $Parent)
    $candidatePath = [IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    $comparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    if ([string]::Equals($candidatePath, $parentPath, $comparison)) { return $true }
    return $candidatePath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Assert-NoReparseAncestor {
    param([string] $Path)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not (Test-Path -LiteralPath $current)) {
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { return }
        $current = $parent.FullName
    }
    while ($null -ne $current) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Path traverses a reparse point: $current"
        }
        $parent = [IO.Directory]::GetParent($current)
        $current = if ($null -eq $parent) { $null } else { $parent.FullName }
    }
}

function Get-JsonProperty {
    param([object] $Object, [string] $Name, [switch] $Required)
    if ($null -eq $Object) {
        if ($Required) { throw "JSON object is missing while reading property: $Name" }
        return $null
    }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        if ($Required) { throw "JSON property is missing: $Name" }
        return $null
    }
    return $property.Value
}

function Write-Utf8Json {
    param([string] $Path, [object] $Value)
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Get-ExecutablePath {
    param([string] $WindowsName, [string] $UnixName)
    $name = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $WindowsName } else { $UnixName }
    $commands = @(Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) { throw "Required tool is not installed: $name" }
    return [string]$commands[0].Source
}

function Invoke-ExternalCommand {
    param([string] $FilePath, [string[]] $Arguments, [string] $WorkingDirectory)
    $stderrPath = [IO.Path]::GetTempFileName()
    try {
        Push-Location $WorkingDirectory
        try {
            $stdout = @(& $FilePath @Arguments 2> $stderrPath)
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { [string](Get-Content -LiteralPath $stderrPath -Raw) } else { '' }
        if ($exitCode -ne 0) {
            $detailLines = @($stdout | Select-Object -Last 12)
            if (-not [string]::IsNullOrWhiteSpace($stderr)) { $detailLines += @($stderr.Trim() -split '\r?\n' | Select-Object -Last 12) }
            $detail = $detailLines -join [Environment]::NewLine
            throw "External command failed with exit code ${exitCode}: $FilePath $($Arguments -join ' ')`n$detail"
        }
        return ($stdout -join [Environment]::NewLine)
    } finally {
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function ConvertFrom-Json5Text {
    param([string] $Text, [string] $Path)
    try { return ,($Text | ConvertFrom-Json) } catch { }

    # 只删除字符串外的注释，避免把 URL 中的双斜线误删；随后处理常见 JSON5 键名和尾逗号。
    $builder = New-Object Text.StringBuilder
    $inString = $false
    $quote = [char]0
    $escaped = $false
    $lineComment = $false
    $blockComment = $false
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }
        if ($lineComment) {
            if ($character -eq "`r" -or $character -eq "`n") { $lineComment = $false; [void]$builder.Append($character) }
            continue
        }
        if ($blockComment) {
            if ($character -eq '*' -and $next -eq '/') { $blockComment = $false; $index++ } elseif ($character -eq "`r" -or $character -eq "`n") { [void]$builder.Append($character) }
            continue
        }
        if ($inString) {
            if ($escaped) {
                # JSON5 的 \' 在 JSON 双引号字符串中无需保留反斜杠；其他 JSON 转义保持原样。
                if ($quote -eq "'" -and $character -eq "'") {
                    [void]$builder.Append($character)
                } else {
                    [void]$builder.Append('\').Append($character)
                }
                $escaped = $false
                continue
            }
            if ($character -eq '\') { $escaped = $true; continue }
            if ($character -eq $quote) {
                [void]$builder.Append('"')
                $inString = $false
                continue
            }
            if ($quote -eq "'" -and $character -eq '"') {
                [void]$builder.Append('\').Append($character)
            } else {
                [void]$builder.Append($character)
            }
            continue
        }
        if ($character -eq '"' -or $character -eq "'") { $inString = $true; $quote = $character; [void]$builder.Append('"'); continue }
        if ($character -eq '/' -and $next -eq '/') { $lineComment = $true; $index++; continue }
        if ($character -eq '/' -and $next -eq '*') { $blockComment = $true; $index++; continue }
        [void]$builder.Append($character)
    }
    $normalized = $builder.ToString()
    $normalized = [regex]::Replace($normalized, '(?m)([{,]\s*)([A-Za-z_$][A-Za-z0-9_$.-]*)(\s*:)', '$1"$2"$3')
    $normalized = [regex]::Replace($normalized, ',\s*([}\]])', '$1')
    try { return ,($normalized | ConvertFrom-Json) } catch { throw "Unable to parse JSON/JSON5 manifest: $Path" }
}

function Get-LicenseLabels {
    param([object] $Component)
    $labels = @()
    foreach ($entry in @(Get-JsonProperty -Object $Component -Name 'licenses')) {
        $license = Get-JsonProperty -Object $entry -Name 'license'
        if ($null -eq $license) { $license = $entry }
        foreach ($field in @('id', 'name', 'expression')) {
            $value = Get-JsonProperty -Object $license -Name $field
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $labels += [string]$value }
        }
    }
    return @($labels | Select-Object -Unique)
}

function Normalize-CycloneDxBom {
    param([object] $Bom)
    $serial = $Bom.PSObject.Properties['serialNumber']
    if ($null -ne $serial) { $Bom.PSObject.Properties.Remove('serialNumber') }
    $metadata = Get-JsonProperty -Object $Bom -Name 'metadata'
    if ($null -ne $metadata) {
        $timestamp = $metadata.PSObject.Properties['timestamp']
        if ($null -ne $timestamp) { $metadata.PSObject.Properties.Remove('timestamp') }
    }
    $components = @(Get-JsonProperty -Object $Bom -Name 'components' -Required)
    $Bom.components = @($components | Sort-Object @{Expression={ [string](Get-JsonProperty $_ 'purl') }}, @{Expression={ [string](Get-JsonProperty $_ 'name') }}, @{Expression={ [string](Get-JsonProperty $_ 'version') }})
    $dependencies = Get-JsonProperty -Object $Bom -Name 'dependencies'
    if ($null -ne $dependencies) {
        foreach ($dependency in @($dependencies)) {
            $dependsOn = Get-JsonProperty -Object $dependency -Name 'dependsOn'
            if ($null -ne $dependsOn) { $dependency.dependsOn = @($dependsOn | Sort-Object) }
        }
        $Bom.dependencies = @($dependencies | Sort-Object @{Expression={ [string](Get-JsonProperty $_ 'ref') }})
    }
    return $Bom
}

function Test-Bom {
    param([string] $Path, [object] $Bom, [System.Collections.Generic.List[object]] $Findings)
    if ((Get-JsonProperty $Bom 'bomFormat') -ne 'CycloneDX') {
        $Findings.Add([pscustomobject]@{ path = $Path; rule = 'bomFormat must be CycloneDX' })
    }
    $all = @()
    $metadata = Get-JsonProperty $Bom 'metadata'
    if ($null -ne $metadata -and $null -ne (Get-JsonProperty $metadata 'component')) { $all += Get-JsonProperty $metadata 'component' }
    $all += @(Get-JsonProperty $Bom 'components' -Required)
    if ($all.Count -eq 0) { $Findings.Add([pscustomobject]@{ path = $Path; rule = 'SBOM has no components' }) }
    foreach ($component in $all) {
        $name = [string](Get-JsonProperty $component 'name')
        $version = [string](Get-JsonProperty $component 'version')
        if ([string]::IsNullOrWhiteSpace($name)) { $Findings.Add([pscustomobject]@{ path = $Path; rule = 'component name is missing' }) }
        if ([string]::IsNullOrWhiteSpace($version)) { $Findings.Add([pscustomobject]@{ path = $Path; rule = "component version is missing: $name" }) }
        if (@(Get-LicenseLabels $component).Count -eq 0) { $Findings.Add([pscustomobject]@{ path = $Path; rule = "component license metadata is missing: $name@$version" }) }
    }
}

function New-LicenseEntry {
    param([string] $Name, [string] $Url)
    return [ordered]@{ license = [ordered]@{ name = $Name; url = $Url } }
}

function New-Property {
    param([string] $Name, [string] $Value)
    return [ordered]@{ name = $Name; value = $Value }
}

function Get-ManifestObject {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required manifest is missing: $Path" }
    return ConvertFrom-Json5Text -Text (Get-Content -LiteralPath $Path -Raw -Encoding UTF8) -Path $Path
}

function Add-OhpmComponents {
    param([string] $Path, [System.Collections.Generic.List[object]] $Components)
    $manifest = Get-ManifestObject $Path
    $name = [string](Get-JsonProperty $manifest 'name' -Required)
    $version = [string](Get-JsonProperty $manifest 'version' -Required)
    $license = [string](Get-JsonProperty $manifest 'license')
    $projectPurl = "pkg:generic/harmony-ocr/$([Uri]::EscapeDataString($name))@$([Uri]::EscapeDataString($version))"
    $project = [ordered]@{
        type = 'application'; name = $name; version = $version; purl = $projectPurl
        scope = 'required'; properties = @((New-Property 'harmony-ocr:source-boundary' 'project-source'))
        licenses = @((New-LicenseEntry -Name ($(if ([string]::IsNullOrWhiteSpace($license)) { 'MIT' } else { $license })) -Url 'https://github.com/3128698033/harmony-ocr/blob/main/LICENSE'))
    }
    $Components.Add($project)
    $dependencies = Get-JsonProperty $manifest 'dependencies'
    if ($null -eq $dependencies) { return }
    foreach ($dependencyProperty in $dependencies.PSObject.Properties) {
        $dependencyVersion = [string]$dependencyProperty.Value
        if ($dependencyVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z.+()_-]*$') {
            throw "OHPM dependency must have an exact version for SBOM generation: $($dependencyProperty.Name)"
        }
        $dependencyPurl = "pkg:generic/ohpm/$([Uri]::EscapeDataString($dependencyProperty.Name))@$([Uri]::EscapeDataString($dependencyVersion))"
        $Components.Add([ordered]@{
            type = 'library'; name = [string]$dependencyProperty.Name; version = $dependencyVersion; purl = $dependencyPurl
            scope = 'required'; properties = @((New-Property 'harmony-ocr:source-boundary' 'external-ohpm-package'))
        })
    }
}

function Get-ComposeImageReferences {
    param([string] $Root)
    $images = New-Object 'System.Collections.Generic.List[object]'
    foreach ($composePath in @('deploy/docker-compose.dev.yml', 'deploy/docker-compose.prod.yml')) {
        $path = Join-Path $Root $composePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $service = $null
        $reference = $null
        $platform = $null
        foreach ($line in @(Get-Content -LiteralPath $path -Encoding UTF8)) {
            $serviceMatch = [regex]::Match($line, '^\s{2}(?<service>[A-Za-z0-9_-]+):\s*$')
            if ($serviceMatch.Success) {
                if ($null -ne $reference -and $reference -notmatch '\$\{') {
                    $images.Add([pscustomobject]@{ path = $composePath; service = $service; reference = $reference; platform = $platform })
                }
                $service = $serviceMatch.Groups['service'].Value
                $reference = $null
                $platform = $null
                continue
            }
            if ($null -eq $service) { continue }
            $imageMatch = [regex]::Match($line, '^\s+image:\s*(?<reference>[^\s#]+)')
            if ($imageMatch.Success) { $reference = $imageMatch.Groups['reference'].Value; continue }
            $platformMatch = [regex]::Match($line, '^\s+platform:\s*(?<platform>[^\s#]+)')
            if ($platformMatch.Success) { $platform = $platformMatch.Groups['platform'].Value }
        }
        if ($null -ne $reference -and $reference -notmatch '\$\{') {
            $images.Add([pscustomobject]@{ path = $composePath; service = $service; reference = $reference; platform = $platform })
        }
    }
    return @($images | Sort-Object path, service, reference)
}

function New-ContainerBom {
    param([string] $Root)
    $lockPath = Join-Path $Root 'third-party/container-images.lock.json'
    $lock = Get-ManifestObject $lockPath
    if ((Get-JsonProperty $lock 'schemaVersion' -Required) -ne 1) { throw 'Unsupported container image lock schema.' }
    $entries = @(Get-JsonProperty $lock 'images' -Required)
    if ($entries.Count -eq 0) { throw 'Container image lock must contain at least one image.' }
    $composeImages = @(Get-ComposeImageReferences $Root)
    $composeRefs = @($composeImages | ForEach-Object { [string]$_.reference } | Sort-Object -Unique)
    $lockedRefs = @()
    $lockedReferenceSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $lockedPlatforms = @{}
    $components = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $entries) {
        $name = [string](Get-JsonProperty $entry 'name' -Required)
        $reference = [string](Get-JsonProperty $entry 'reference' -Required)
        $repository = [string](Get-JsonProperty $entry 'repository' -Required)
        $tag = [string](Get-JsonProperty $entry 'tag' -Required)
        $platform = [string](Get-JsonProperty $entry 'platform' -Required)
        $digest = [string](Get-JsonProperty $entry 'digest' -Required)
        $indexDigest = [string](Get-JsonProperty $entry 'indexDigest' -Required)
        $license = Get-JsonProperty $entry 'license' -Required
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($repository) -or [string]::IsNullOrWhiteSpace($tag)) { throw 'Container lock name, repository, and tag must be non-empty.' }
        $referenceMatch = [regex]::Match($reference, '^(?<repository>[^\s:@]+(?:/[^\s:@]+)*):(?<tag>[^\s@]+)@(?<digest>sha256:[0-9a-f]{64})$')
        if (-not $referenceMatch.Success -or $referenceMatch.Groups['tag'].Value -ne $tag -or $referenceMatch.Groups['digest'].Value -ne $indexDigest) {
            throw "Locked container reference must pin the reviewed tag and index digest: $reference"
        }
        $expectedReferenceRepository = if ($repository.StartsWith('docker.io/library/')) {
            $repository.Substring('docker.io/library/'.Length)
        } elseif ($repository.StartsWith('docker.io/')) {
            $repository.Substring('docker.io/'.Length)
        } else {
            $repository
        }
        if ($referenceMatch.Groups['repository'].Value -ne $expectedReferenceRepository -or
            $name -ne (($repository -split '/')[-1])) {
            throw "Container lock name, repository, and reference are inconsistent: $reference"
        }
        if (-not $lockedReferenceSet.Add($reference)) { throw "Duplicate locked container reference: $reference" }
        if ($platform -notmatch '^linux/(amd64|arm64)$') { throw "Unsupported locked container platform: $reference" }
        if ($digest -notmatch '^sha256:[0-9a-f]{64}$' -or $indexDigest -notmatch '^sha256:[0-9a-f]{64}$') { throw "Container digest is not a full SHA-256: $reference" }
        if ([string]::IsNullOrWhiteSpace([string](Get-JsonProperty $license 'name')) -or [string]::IsNullOrWhiteSpace([string](Get-JsonProperty $license 'url'))) { throw "Container license evidence is incomplete: $reference" }
        $lockedRefs += $reference
        $lockedPlatforms[$reference] = $platform
        $digestValue = $digest.Substring(7)
        $components.Add([ordered]@{
            type = 'container'; name = $repository; version = $tag
            purl = "pkg:oci/$([Uri]::EscapeDataString($name))@$([Uri]::EscapeDataString($digest))`?repository_url=$([Uri]::EscapeDataString($repository))&tag=$([Uri]::EscapeDataString($tag))"
            hashes = @([ordered]@{ alg = 'SHA-256'; content = $digestValue })
            licenses = @((New-LicenseEntry -Name ([string](Get-JsonProperty $license 'name')) -Url ([string](Get-JsonProperty $license 'url'))))
            properties = @(
                (New-Property 'harmony-ocr:source-boundary' 'external-container-image'),
                (New-Property 'container:reference' $reference),
                (New-Property 'container:platform' $platform),
                (New-Property 'container:index-digest' $indexDigest)
            )
        })
    }
    if (@(Compare-Object ($composeRefs | Sort-Object) ($lockedRefs | Sort-Object) -CaseSensitive).Count -ne 0) {
        throw 'Container image lock does not exactly match the image references in the compose files.'
    }
    foreach ($composeImage in $composeImages) {
        $composePlatform = [string]$composeImage.platform
        if ([string]::IsNullOrWhiteSpace($composePlatform) -or $composePlatform -ne $lockedPlatforms[[string]$composeImage.reference]) {
            throw "Compose image platform does not match the reviewed lock: $($composeImage.path):$($composeImage.service)"
        }
    }
    return [ordered]@{
        bomFormat = 'CycloneDX'; specVersion = '1.6'; version = 1
        metadata = [ordered]@{ component = [ordered]@{
            type = 'application'; name = 'harmony-ocr-container-deployment'; version = '1'
            purl = 'pkg:generic/harmony-ocr-container-deployment@1'
            licenses = @((New-LicenseEntry -Name 'MIT' -Url 'https://github.com/3128698033/harmony-ocr/blob/main/LICENSE'))
            properties = @((New-Property 'harmony-ocr:source-boundary' 'project-source'))
        } }
        components = @($components | Sort-Object @{Expression={ [string](Get-JsonProperty $_ 'purl') }})
    }
}

Assert-SafeGitEnvironment
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryRoot).Path).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "RepositoryRoot is not a directory: $root" }
$gitTop = Invoke-GitValue -Root $root -Arguments @('rev-parse', '--show-toplevel')
$gitTop = [IO.Path]::GetFullPath($gitTop).TrimEnd('\', '/')
if (-not [string]::Equals($root, $gitTop, $(if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) {
    throw 'RepositoryRoot must be the canonical Git worktree root.'
}
$gitCommon = Invoke-GitValue -Root $root -Arguments @('rev-parse', '--git-common-dir')
if (-not [IO.Path]::IsPathRooted($gitCommon)) { $gitCommon = Join-Path $root $gitCommon }
$gitCommon = [IO.Path]::GetFullPath($gitCommon).TrimEnd('\', '/')
$destination = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
if ((Test-PathInside $destination $root) -or (Test-PathInside $destination $gitCommon)) {
    throw 'OutputDirectory must be outside the Git worktree and Git common directory.'
}
Assert-NoReparseAncestor -Path $destination
$parent = [IO.Directory]::GetParent($destination)
if ($null -eq $parent) { throw 'OutputDirectory must have a parent directory.' }
[IO.Directory]::CreateDirectory($parent.FullName) | Out-Null
Assert-NoReparseAncestor -Path $parent.FullName
if (Test-Path -LiteralPath $destination) {
    $existing = @(Get-ChildItem -LiteralPath $destination -Force)
    if ($existing.Count -ne 0) { throw 'OutputDirectory must be new or empty.' }
} else {
    [IO.Directory]::CreateDirectory($destination) | Out-Null
}

$temporarySettings = Join-Path $destination ('.harmony-ocr-maven-settings-' + [Guid]::NewGuid().ToString('N') + '.xml')
$temporaryNpmConfig = Join-Path $destination ('.harmony-ocr-npmrc-' + [Guid]::NewGuid().ToString('N'))
$mavenStagingLeaf = 'harmony-ocr-maven-' + [Guid]::NewGuid().ToString('N')
$mavenStaging = Join-Path $destination $mavenStagingLeaf
$validationFindings = New-Object 'System.Collections.Generic.List[object]'
try {
    # 使用空的用户配置，避免把开发者本机的 Maven/npm 凭据带入生成过程。
    [IO.File]::WriteAllText($temporarySettings, '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"/>', (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($temporaryNpmConfig, "registry=https://registry.npmjs.org/`n", (New-Object Text.UTF8Encoding($false)))
    [IO.Directory]::CreateDirectory($mavenStaging) | Out-Null

    $npm = Get-ExecutablePath -WindowsName 'npm.cmd' -UnixName 'npm'
    $runningOnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $npmPrefix = Join-Path $root 'admin-console'
    $npmArgs = @('--prefix', $npmPrefix, 'sbom', '--sbom-format', 'cyclonedx', '--sbom-type', 'application', '--package-lock-only', '--json', '--registry=https://registry.npmjs.org', "--userconfig=$temporaryNpmConfig")
    $npmJson = Invoke-ExternalCommand -FilePath $npm -Arguments $npmArgs -WorkingDirectory $root
    $npmBom = Normalize-CycloneDxBom -Bom ($npmJson | ConvertFrom-Json)
    $npmPath = Join-Path $destination 'npm.cyclonedx.json'
    Write-Utf8Json -Path $npmPath -Value $npmBom
    Test-Bom -Path 'npm.cyclonedx.json' -Bom $npmBom -Findings $validationFindings

    $mavenCommand = Get-ExecutablePath -WindowsName 'mvn.cmd' -UnixName 'mvn'
    $mavenArgs = @('-B', '--no-transfer-progress', '-ntp', '-s', $temporarySettings, '-f', (Join-Path $root 'server/pom.xml'), 'org.cyclonedx:cyclonedx-maven-plugin:2.9.1:makeAggregateBom', '-DskipTests', '-Dcyclonedx.skipAttach=true', '-DoutputFormat=json', '-DoutputName=maven.cyclonedx', "-DoutputDirectory=$mavenStaging")
    if ($runningOnWindows) {
        # 直接调用 Java 的 ClassWorlds 启动器，避免 Windows PowerShell 经由 mvn.cmd 传递 Unicode 临时路径时发生代码页损坏。
        $mavenHomePath = Split-Path -Parent (Split-Path -Parent $mavenCommand)
        $classworlds = @(Get-ChildItem -LiteralPath (Join-Path $mavenHomePath 'boot') -Filter 'plexus-classworlds-*.jar' -File)
        if ($classworlds.Count -ne 1) { throw 'Maven ClassWorlds launcher is missing or ambiguous.' }
        $java = Get-ExecutablePath -WindowsName 'java.exe' -UnixName 'java'
        $launcherArgs = @(
            '-classpath', $classworlds[0].FullName,
            "-Dclassworlds.conf=$(Join-Path $mavenHomePath 'bin/m2.conf')",
            "-Dmaven.home=$mavenHomePath",
            "-Dlibrary.jansi.path=$(Join-Path $mavenHomePath 'lib/jansi-native')",
            "-Dmaven.multiModuleProjectDirectory=$root",
            'org.codehaus.plexus.classworlds.launcher.Launcher'
        ) + $mavenArgs
        [void](Invoke-ExternalCommand -FilePath $java -Arguments $launcherArgs -WorkingDirectory $root)
    } else {
        $maven = Get-ExecutablePath -WindowsName 'mvn.cmd' -UnixName 'mvn'
        [void](Invoke-ExternalCommand -FilePath $maven -Arguments $mavenArgs -WorkingDirectory $root)
    }
    $mavenStagingPath = Join-Path $mavenStaging 'maven.cyclonedx.json'
    if (-not (Test-Path -LiteralPath $mavenStagingPath -PathType Leaf)) { throw 'Maven CycloneDX plugin did not create maven.cyclonedx.json.' }
    $mavenPath = Join-Path $destination 'maven.cyclonedx.json'
    [IO.File]::Copy($mavenStagingPath, $mavenPath, $false)
    $mavenBom = Normalize-CycloneDxBom -Bom (Get-Content -LiteralPath $mavenPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    Write-Utf8Json -Path $mavenPath -Value $mavenBom
    Test-Bom -Path 'maven.cyclonedx.json' -Bom $mavenBom -Findings $validationFindings

    $ohpmComponents = New-Object 'System.Collections.Generic.List[object]'
    Add-OhpmComponents -Path (Join-Path $root 'app/oh-package.json5') -Components $ohpmComponents
    Add-OhpmComponents -Path (Join-Path $root 'app/entry/oh-package.json5') -Components $ohpmComponents
    $buildProfile = Get-ManifestObject (Join-Path $root 'app/build-profile.json5')
    $products = @(Get-JsonProperty (Get-JsonProperty $buildProfile 'app' -Required) 'products' -Required)
    $sdkVersions = @($products | ForEach-Object { [string](Get-JsonProperty $_ 'compatibleSdkVersion' -Required) } | Sort-Object -Unique)
    if ($sdkVersions.Count -eq 0) { throw 'HarmonyOS build profile has no compatible SDK version.' }
    foreach ($sdkVersion in $sdkVersions) {
        $ohpmComponents.Add([ordered]@{
            type = 'framework'; name = 'HarmonyOS SDK'; version = $sdkVersion
            purl = "pkg:generic/harmonyos-sdk@$([Uri]::EscapeDataString($sdkVersion))"
            scope = 'required'; licenses = @((New-LicenseEntry -Name 'Huawei HarmonyOS SDK platform terms' -Url 'https://developer.harmonyos.com/en/develop/deveco-studio'))
            properties = @((New-Property 'harmony-ocr:source-boundary' 'externally-installed-platform'))
        })
    }
    $appManifest = Get-ManifestObject (Join-Path $root 'app/oh-package.json5')
    $appVersion = [string](Get-JsonProperty $appManifest 'version' -Required)
    $ohpmBom = [ordered]@{
        bomFormat = 'CycloneDX'; specVersion = '1.6'; version = 1
        metadata = [ordered]@{ component = [ordered]@{
            type = 'application'; name = 'harmony-ocr-app'; version = $appVersion
            purl = "pkg:generic/harmony-ocr-app@$([Uri]::EscapeDataString($appVersion))"; licenses = @((New-LicenseEntry -Name 'MIT' -Url 'https://github.com/3128698033/harmony-ocr/blob/main/LICENSE'))
            properties = @((New-Property 'harmony-ocr:source-boundary' 'project-source'))
        } }
        components = @($ohpmComponents | Sort-Object @{Expression={ [string](Get-JsonProperty $_ 'purl') }})
    }
    $ohpmBom = Normalize-CycloneDxBom -Bom $ohpmBom
    $ohpmPath = Join-Path $destination 'harmonyos-ohpm.cyclonedx.json'
    Write-Utf8Json -Path $ohpmPath -Value $ohpmBom
    Test-Bom -Path 'harmonyos-ohpm.cyclonedx.json' -Bom $ohpmBom -Findings $validationFindings

    $containerBom = New-ContainerBom -Root $root
    $containerBom = Normalize-CycloneDxBom -Bom $containerBom
    $containerPath = Join-Path $destination 'container-images.cyclonedx.json'
    Write-Utf8Json -Path $containerPath -Value $containerBom
    Test-Bom -Path 'container-images.cyclonedx.json' -Bom $containerBom -Findings $validationFindings

    $validationStatus = if ($validationFindings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
    $validation = [ordered]@{
        schemaVersion = 1; status = $validationStatus
        files = @('npm.cyclonedx.json', 'maven.cyclonedx.json', 'harmonyos-ohpm.cyclonedx.json', 'container-images.cyclonedx.json')
        findings = @($validationFindings | ForEach-Object { $_ })
    }
    Write-Utf8Json -Path (Join-Path $destination 'sbom-validation.json') -Value $validation
    if ($validationFindings.Count -ne 0) {
        throw ('SBOM validation failed; review sbom-validation.json:' + [Environment]::NewLine + (($validationFindings | ForEach-Object { "$($_.path): $($_.rule)" }) -join [Environment]::NewLine))
    }
    Write-Output "PASS: SBOM inventories written to $destination"
} finally {
    Remove-Item -LiteralPath $temporarySettings, $temporaryNpmConfig -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $mavenStaging) { Remove-Item -LiteralPath $mavenStaging -Recurse -Force -ErrorAction SilentlyContinue }
}
