param(
    [Parameter(Mandatory = $true)]
    [string] $RepositoryRoot,

    [Parameter(Mandatory = $true)]
    [Alias('InputDirectory', 'SbomRoot', 'ReportDirectory')]
    [string] $SbomDirectory
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
        if (-not [string]::IsNullOrEmpty($value)) { throw "Unsafe Git environment variable is set: $name" }
    }
}

function Invoke-GitValue {
    param([string] $Root, [string[]] $Arguments)
    Assert-SafeGitEnvironment
    $lines = @(& git -C $Root @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: $($Arguments -join ' ')" }
    return ([string]$lines[0]).Trim()
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

function Get-LicenseLabels {
    param([object] $Component)
    $labels = @()
    foreach ($entry in @(Get-JsonProperty $Component 'licenses')) {
        $license = Get-JsonProperty $entry 'license'
        if ($null -eq $license) { $license = $entry }
        foreach ($field in @('id', 'name', 'expression')) {
            $value = Get-JsonProperty $license $field
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $labels += [string]$value }
        }
    }
    return @($labels | Select-Object -Unique)
}

function Get-PropertyValue {
    param([object] $Component, [string] $Name)
    foreach ($property in @(Get-JsonProperty $Component 'properties')) {
        if ((Get-JsonProperty $property 'name') -eq $Name) { return [string](Get-JsonProperty $property 'value') }
    }
    return $null
}

function Read-Bom {
    param([string] $Directory, [string] $FileName)
    $path = Join-Path $Directory $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required SBOM is missing: $path" }
    try { return ,(Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { throw "Unable to parse SBOM: $path" }
}

function Add-Finding {
    param([System.Collections.Generic.List[object]] $Findings, [string] $Ecosystem, [string] $Rule, [string] $Component)
    $Findings.Add([pscustomobject]@{ ecosystem = $Ecosystem; rule = $Rule; component = $Component })
}

function Add-BomEvidence {
    param(
        [string] $Ecosystem,
        [string] $FileName,
        [object] $Bom,
        [System.Collections.Generic.List[object]] $Evidence,
        [System.Collections.Generic.List[object]] $Findings,
        [System.Collections.Generic.HashSet[string]] $Purls
    )
    if ((Get-JsonProperty $Bom 'bomFormat') -ne 'CycloneDX') {
        Add-Finding $Findings $Ecosystem 'bomFormat must be CycloneDX' $FileName
    }
    $all = @()
    $metadata = Get-JsonProperty $Bom 'metadata'
    if ($null -ne $metadata -and $null -ne (Get-JsonProperty $metadata 'component')) {
        $all += [pscustomobject]@{ component = Get-JsonProperty $metadata 'component'; index = -1; boundary = 'project-source' }
    }
    $components = @(Get-JsonProperty $Bom 'components' -Required)
    for ($index = 0; $index -lt $components.Count; $index++) {
        $boundary = Get-PropertyValue -Component $components[$index] -Name 'harmony-ocr:source-boundary'
        if ([string]::IsNullOrWhiteSpace($boundary)) {
            $boundary = switch ($Ecosystem) {
                'npm' { 'external-npm-package' }
                'maven' { 'external-maven-package' }
                'harmonyos' { 'external-ohpm-or-platform' }
                'containers' { 'external-container-image' }
                default { 'external-dependency' }
            }
        }
        $all += [pscustomobject]@{ component = $components[$index]; index = $index; boundary = $boundary }
    }
    if ($all.Count -eq 0) { Add-Finding $Findings $Ecosystem 'SBOM has no components' $FileName }
    for ($itemIndex = 0; $itemIndex -lt $all.Count; $itemIndex++) {
        $item = $all[$itemIndex]
        $component = $item.component
        $name = [string](Get-JsonProperty $component 'name')
        $version = [string](Get-JsonProperty $component 'version')
        $purl = [string](Get-JsonProperty $component 'purl')
        $display = if ([string]::IsNullOrWhiteSpace($name)) { "#$itemIndex" } else { "$name@$version" }
        if ([string]::IsNullOrWhiteSpace($name)) { Add-Finding $Findings $Ecosystem 'component name is missing' $display }
        if ([string]::IsNullOrWhiteSpace($version)) { Add-Finding $Findings $Ecosystem 'component version is missing' $display }
        if ([string]::IsNullOrWhiteSpace($purl)) {
            Add-Finding $Findings $Ecosystem 'component purl is missing; exact evidence is required' $display
        } elseif (-not $Purls.Add($purl)) {
            Add-Finding $Findings $Ecosystem 'duplicate component purl' $purl
        }
        $licenseLabels = @(Get-LicenseLabels $component)
        $unknownLicense = @($licenseLabels | Where-Object { $_ -match '(?i)^(unknown|noassertion|unlicensed)$' }).Count -ne 0
        if ($licenseLabels.Count -eq 0 -or $unknownLicense) {
            Add-Finding $Findings $Ecosystem 'component license metadata is missing' $display
        }
        $prefix = switch ($Ecosystem) {
            'npm' { 'pkg:npm/' }
            'maven' { 'pkg:maven/' }
            'harmonyos' { 'pkg:generic/' }
            'containers' { 'pkg:oci/' }
            default { 'pkg:' }
        }
        $projectGenericPurl = $item.boundary -eq 'project-source' -and $purl.StartsWith('pkg:generic/', [StringComparison]::Ordinal)
        if (-not [string]::IsNullOrWhiteSpace($purl) -and -not $purl.StartsWith($prefix, [StringComparison]::Ordinal) -and -not $projectGenericPurl) {
            Add-Finding $Findings $Ecosystem "purl must start with $prefix" $purl
        }
        if ($item.index -ge 0 -and $Ecosystem -in @('npm', 'maven', 'containers') -and $item.boundary -eq 'project-source') {
            Add-Finding $Findings $Ecosystem 'dependency component cannot be classified as project source' $display
        }
        if ($Ecosystem -eq 'maven' -and $item.index -ge 0) {
            # Maven 的继承许可证只能由同一组件的完整 purl 支撑，不能使用 group 或 artifact 级别的宽泛映射。
            if ([string]::IsNullOrWhiteSpace($purl) -or $purl -notmatch '^pkg:maven/[^/]+/[^@]+@[^?]+(?:\?.+)?$') {
                Add-Finding $Findings $Ecosystem 'Maven license evidence must use an exact pkg:maven purl' $display
            } else {
                $group = [string](Get-JsonProperty $component 'group')
                $escapedGroup = [Uri]::EscapeDataString($group)
                $escapedName = [Uri]::EscapeDataString($name)
                $escapedVersion = [Uri]::EscapeDataString($version)
                $expectedPurl = "pkg:maven/$escapedGroup/$escapedName@$escapedVersion"
                if (-not ($purl -eq $expectedPurl -or $purl.StartsWith($expectedPurl + '?', [StringComparison]::Ordinal))) {
                    Add-Finding $Findings $Ecosystem 'Maven purl does not match the component group, name, and version' $display
                }
            }
        }
        $licenseEvidencePath = if ($item.index -lt 0) { "$FileName#/metadata/component/licenses" } else { "$FileName#/components/$($item.index)/licenses" }
        $Evidence.Add([pscustomobject]@{
            ecosystem = $Ecosystem; boundary = [string]$item.boundary; name = $name; version = $version
            purl = $purl; licenses = $licenseLabels; source = $FileName
            evidencePath = $licenseEvidencePath
            evidenceType = if ($Ecosystem -eq 'maven' -and $item.index -ge 0) { 'exact-cyclonedx-purl' } else { 'cyclonedx-component-license' }
        })
    }
}

function Write-MarkdownReport {
    param([string] $Path, [object] $Report)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('# Dependency License Audit')
    $lines.Add('')
    $lines.Add("Status: **$($Report.status)**")
    $lines.Add('')
    $lines.Add('Project MIT source, external packages, externally pulled container images, and the HarmonyOS SDK are reported as separate boundaries.')
    $lines.Add('')
    if (@($Report.findings).Count -ne 0) {
        $lines.Add('## Release-blocking findings')
        $lines.Add('')
        foreach ($finding in @($Report.findings)) { $lines.Add("- [$($finding.ecosystem)] $($finding.rule): $($finding.component)") }
        $lines.Add('')
    }
    $lines.Add('## Evidence')
    $lines.Add('')
    $lines.Add('| Ecosystem | Boundary | Name | Version | License | Exact purl | Evidence path |')
    $lines.Add('| --- | --- | --- | --- | --- | --- | --- |')
    foreach ($entry in @($Report.components | Sort-Object ecosystem, purl)) {
        $license = ((@($entry.licenses) -join '; ') -replace '\|', '\\|')
        $lines.Add("| $($entry.ecosystem) | $($entry.boundary) | $($entry.name) | $($entry.version) | $license | $($entry.purl) | $($entry.evidencePath) |")
    }
    [IO.File]::WriteAllText($Path, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

Assert-SafeGitEnvironment
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryRoot).Path).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "RepositoryRoot is not a directory: $root" }
$sbomRoot = [IO.Path]::GetFullPath($SbomDirectory).TrimEnd('\', '/')
$gitTop = Invoke-GitValue -Root $root -Arguments @('rev-parse', '--show-toplevel')
$gitTop = [IO.Path]::GetFullPath($gitTop).TrimEnd('\', '/')
$comparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (-not [string]::Equals($root, $gitTop, $comparison)) { throw 'RepositoryRoot must be the canonical Git worktree root.' }
$gitCommon = Invoke-GitValue -Root $root -Arguments @('rev-parse', '--git-common-dir')
if (-not [IO.Path]::IsPathRooted($gitCommon)) { $gitCommon = Join-Path $root $gitCommon }
$gitCommon = [IO.Path]::GetFullPath($gitCommon).TrimEnd('\', '/')
if ((Test-PathInside $sbomRoot $root) -or (Test-PathInside $sbomRoot $gitCommon)) { throw 'SbomDirectory must be outside the Git worktree and Git common directory.' }
Assert-NoReparseAncestor -Path $sbomRoot
if (-not (Test-Path -LiteralPath $sbomRoot -PathType Container)) { throw "SbomDirectory does not exist: $sbomRoot" }

$licenseFile = Join-Path $root 'LICENSE'
if (-not (Test-Path -LiteralPath $licenseFile -PathType Leaf) -or (Get-Content -LiteralPath $licenseFile -Raw -Encoding UTF8) -notmatch 'MIT License') {
    throw 'The project MIT LICENSE is missing or invalid.'
}

$evidence = New-Object 'System.Collections.Generic.List[object]'
$findings = New-Object 'System.Collections.Generic.List[object]'
$purls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$bomDefinitions = @(
    [pscustomobject]@{ ecosystem = 'npm'; file = 'npm.cyclonedx.json' },
    [pscustomobject]@{ ecosystem = 'maven'; file = 'maven.cyclonedx.json' },
    [pscustomobject]@{ ecosystem = 'harmonyos'; file = 'harmonyos-ohpm.cyclonedx.json' },
    [pscustomobject]@{ ecosystem = 'containers'; file = 'container-images.cyclonedx.json' }
)
foreach ($definition in $bomDefinitions) {
    $bom = Read-Bom -Directory $sbomRoot -FileName $definition.file
    Add-BomEvidence -Ecosystem $definition.ecosystem -FileName $definition.file -Bom $bom -Evidence $evidence -Findings $findings -Purls $purls
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$report = [ordered]@{
    schemaVersion = 1; status = $status
    projectLicense = [ordered]@{ name = 'MIT'; source = 'LICENSE'; boundary = 'project-source' }
    components = @($evidence | ForEach-Object { $_ } | Sort-Object ecosystem, purl)
    findings = @($findings | ForEach-Object { $_ })
    releaseBlocking = ($findings.Count -ne 0)
}
$jsonPath = Join-Path $sbomRoot 'dependency-license-audit.json'
$markdownPath = Join-Path $sbomRoot 'dependency-license-audit.md'
Write-Utf8Json -Path $jsonPath -Value $report
Write-MarkdownReport -Path $markdownPath -Report $report
if ($findings.Count -ne 0) {
    throw ('Dependency license audit failed; review dependency-license-audit.json:' + [Environment]::NewLine + (($findings | ForEach-Object { "[$($_.ecosystem)] $($_.rule): $($_.component)" }) -join [Environment]::NewLine))
}
Write-Output "PASS: dependency license audit written to $jsonPath"
