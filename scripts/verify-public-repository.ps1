param(
    [Parameter(Mandatory = $true)] [string] $RepositoryRoot,
    [string[]] $RelativePaths,
    [switch] $VerifyGeneratedAdminAssets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:UnsafeGitEnvironmentVariables = @(
    'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_CONFIG', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_COUNT',
    'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_NOSYSTEM', 'GIT_OBJECT_DIRECTORY',
    'GIT_DIR', 'GIT_WORK_TREE', 'GIT_IMPLICIT_WORK_TREE', 'GIT_GRAFT_FILE', 'GIT_INDEX_FILE',
    'GIT_REPLACE_REF_BASE', 'GIT_PREFIX', 'GIT_SHALLOW_FILE', 'GIT_COMMON_DIR', 'GIT_NAMESPACE'
)

# 公共策略检查也必须固定到调用参数指定的仓库，不能接受继承的 Git 重定向变量。
function Assert-SafeGitEnvironment {
    foreach ($name in $script:UnsafeGitEnvironmentVariables) {
        $value = [System.Environment]::GetEnvironmentVariable($name, [System.EnvironmentVariableTarget]::Process)
        if (-not [string]::IsNullOrEmpty($value)) { throw "Unsafe Git environment variable is set: $name" }
    }
}

function Invoke-PublicGit {
    param([string] $Repository, [string[]] $Arguments)
    Assert-SafeGitEnvironment
    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Public Git check failed: $($Arguments[0])" }
    return @($output | ForEach-Object { $_.ToString() })
}

function Get-RelativePublicPaths {
    param([string] $Root, [string[]] $RequestedPaths)
    if ($null -ne $RequestedPaths) { return @($RequestedPaths) }
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
        return @(Invoke-PublicGit -Repository $Root -Arguments @('-c', 'core.quotePath=false', 'ls-tree', '-r', '--name-only', 'HEAD'))
    }
    $excluded = @('.git', 'node_modules', 'target', 'oh_modules', '.hvigor', 'build', 'dist')
    $result = @()
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($Root)
    while ($queue.Count -ne 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Public repository tree contains a reparse point.' }
            if ($item.PSIsContainer) {
                if ($excluded -notcontains $item.Name) { $queue.Enqueue($item.FullName) }
            } else {
                $result += $item.FullName.Substring($Root.Length + 1).Replace('\', '/')
            }
        }
    }
    return @($result)
}

function Assert-PublicPath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -ne $Path.Trim() -or
        $Path -match '^[A-Za-z]:' -or $Path.StartsWith('/') -or $Path.Contains('\') -or
        $Path.Contains('//') -or $Path -match '[\*\?\[\]:"<>\|]') {
        throw 'Public path list contains an invalid path.'
    }
    $segments = @($Path.Split('/'))
    if (@($segments | Where-Object { $_ -eq '.' -or $_ -eq '..' -or $_.Length -eq 0 }).Count -ne 0) {
        throw 'Public path list contains an invalid segment.'
    }
}

function Assert-NoPublicReparseAncestor {
    param([string] $Root, [string] $RelativePath)
    $current = [System.IO.DirectoryInfo]::new($Root)
    if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Public repository root is a reparse point.'
    }
    foreach ($segment in $RelativePath.Split('/')) {
        $currentPath = Join-Path $current.FullName $segment
        $current = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
        if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Public path or ancestor is a reparse point: $RelativePath"
        }
    }
}

function Test-TextBytes {
    param([byte[]] $Bytes)
    if ($Bytes -contains [byte]0) { return $false }
    $decoder = New-Object System.Text.UTF8Encoding($false, $true)
    try { [void] $decoder.GetString($Bytes); return $true } catch { return $false }
}

function Get-TextLines {
    param([byte[]] $Bytes)
    $lines = @([regex]::Split([System.Text.Encoding]::UTF8.GetString($Bytes), '\r?\n'))
    # Windows PowerShell 5.1 写出的 UTF-8 BOM 不属于 YAML/配置键名，扫描前统一移除。
    if ($lines.Count -gt 0 -and $lines[0].StartsWith([string][char]0xFEFF)) {
        $lines[0] = $lines[0].Substring(1)
    }
    return $lines
}

function Test-PrivateAddress {
    param([string] $Value)
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Value, [ref] $address)) { return $false }
    $bytes = $address.GetAddressBytes()
    if ($bytes.Length -ne 4) { return $false }
    if ($bytes[0] -eq 10) { return $true }
    if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $true }
    return $bytes[0] -eq 192 -and $bytes[1] -eq 168
}

function Test-CodeSourcePath {
    param([string] $Path)
    return $Path -match '(?i)\.(?:c|cc|cpp|cs|ets|go|groovy|h|hpp|java|js|jsx|kt|kts|php|ps1|psd1|psm1|py|rb|rs|scala|swift|ts|tsx)$'
}

function Test-AllowedCredentialValue {
    param([string] $Path, [string] $Value)
    $raw = $Value.Trim().TrimEnd(';', ',').Trim()
    if ([string]::IsNullOrEmpty($raw)) { return $true }
    $stringLiteralPattern = '^(?:"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|`(?:\\.|[^`\\])*`)$'
    $isStringLiteral = $raw -cmatch $stringLiteralPattern
    $clean = if ($isStringLiteral) { $raw.Substring(1, $raw.Length - 2) } else { $raw }
    if ([string]::IsNullOrEmpty($clean)) { return $true }
    # 仅接受完整环境变量占位符；非空默认值会把凭据固化进公开源码。
    if ($clean -cmatch '^\$\{[A-Za-z_][A-Za-z0-9_]*(?::)?\}$' -or
        (-not $isStringLiteral -and $clean -match '(?i)process\.env|system\.getenv|getenv\(')) { return $true }
    if ($Path -eq 'server/src/main/resources/application-test.yml' -and
        $clean -match '^(test|test-only-placeholder-not-for-production-at-least-32-characters|test-only-activation-code-pepper-not-for-production|test-only-byok-encryption-secret-not-for-production)$') {
        return $true
    }
    # 代码中的标识符、调用结果和组合表达式不是静态凭据；完整的非空字符串字面量仍然拒绝。
    if ((Test-CodeSourcePath -Path $Path) -and -not $isStringLiteral) { return $true }
    return $false
}

function Get-CredentialAssignment {
    param([string] $Path, [string] $Line, [string] $Pattern)
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    $match = [regex]::Match($Line, $Pattern, $options)
    if ($match.Success) { return $match }
    if (-not (Test-CodeSourcePath -Path $Path)) { return $null }

    # 兼容 TypeScript/Java 等声明前缀和可选类型注解，同时保留对字符串字面量的拒绝。
    $codePattern = '^\s*(?:(?:public|private|protected|internal|static|final|const|let|var|readonly|volatile|transient|lateinit)\s+)*(?:(?:[A-Za-z_$][A-Za-z0-9_$<>\[\],.?]*\s+))?(?<key>(?:[A-Za-z_$][A-Za-z0-9_$]*\.)*(?:password|secret|token|api[_-]?key|access[_-]?key|secret[_-]?key|jwt[_-]?secret))(?:\s*:\s*[^=;]+)?\s*=\s*(?<value>.*)$'
    $codeMatch = [regex]::Match($Line, $codePattern, $options)
    if ($codeMatch.Success) { return $codeMatch }
    return $null
}

function Add-Finding {
    param([System.Collections.Generic.List[string]] $Findings, [string] $Rule, [string] $Path, [int] $Line)
    $Findings.Add($Rule + ':' + $Path + ':' + $Line)
}

function Test-RequiredMetadata {
    param([string] $Root, $PathSet, [System.Collections.Generic.List[string]] $Findings)
    $required = @(
        'LICENSE', 'README.md', 'SECURITY.md', 'CONTRIBUTING.md', 'CODE_OF_CONDUCT.md',
        'CHANGELOG.md', 'ASSET_LICENSES.md', 'THIRD_PARTY_NOTICES.md',
        'app/oh-package.json5', 'app/entry/oh-package.json5',
        'admin-console/package.json', 'admin-console/package-lock.json', 'server/pom.xml',
        '.gitleaks.toml', '.github/workflows/ci.yml', '.github/dependabot.yml',
        '.github/ISSUE_TEMPLATE/bug_report.yml', '.github/ISSUE_TEMPLATE/feature_request.yml',
        '.github/ISSUE_TEMPLATE/config.yml', '.github/pull_request_template.md',
        'scripts/verify-public-repository.ps1', 'scripts/generate-sbom.ps1',
        'scripts/audit-dependency-licenses.ps1', 'third-party/container-images.lock.json'
    )
    foreach ($path in $required) {
        if (-not $PathSet.Contains($path)) { Add-Finding -Findings $Findings -Rule 'missing governance or MIT metadata' -Path $path -Line 1 }
    }
    if (-not $PathSet.Contains('LICENSE')) { return }
    $license = Get-Content -LiteralPath (Join-Path $Root 'LICENSE') -Raw -Encoding utf8
    if ($license -notmatch 'MIT License' -or $license -notmatch 'Copyright \(c\) 2026 Harmony OCR contributors') {
        Add-Finding -Findings $Findings -Rule 'invalid MIT license' -Path 'LICENSE' -Line 1
    }
    if ($PathSet.Contains('README.md')) {
        $readme = Get-Content -LiteralPath (Join-Path $Root 'README.md') -Raw -Encoding utf8
        if ($readme -notmatch 'MIT' -or $readme -notmatch 'https://github\.com/3128698033/harmony-ocr') {
            Add-Finding -Findings $Findings -Rule 'README MIT metadata incomplete' -Path 'README.md' -Line 1
        }
    }
    foreach ($path in @('app/oh-package.json5', 'app/entry/oh-package.json5', 'admin-console/package.json')) {
        if ($PathSet.Contains($path)) {
            $text = Get-Content -LiteralPath (Join-Path $Root $path) -Raw -Encoding utf8
            if ($text -notmatch '(?i)license[^A-Za-z0-9]+MIT') { Add-Finding -Findings $Findings -Rule 'package license is not MIT' -Path $path -Line 1 }
        }
    }
    if ($PathSet.Contains('admin-console/package-lock.json')) {
        $lockfile = Get-Content -LiteralPath (Join-Path $Root 'admin-console/package-lock.json') -Raw -Encoding utf8
        $rootPackage = [regex]::Match($lockfile, '(?is)"packages"\s*:\s*\{\s*""\s*:\s*\{(?<root>.*?)\}\s*,\s*"node_modules/')
        if (-not $rootPackage.Success) {
            $rootPackage = [regex]::Match($lockfile, '(?is)"packages"\s*:\s*\{\s*""\s*:\s*\{(?<root>.*?)\}\s*\}\s*\}\s*$')
        }
        if (-not $rootPackage.Success -or $rootPackage.Groups['root'].Value -notmatch '(?i)"license"\s*:\s*"MIT"') {
            Add-Finding -Findings $Findings -Rule 'npm lockfile root package license is not MIT' -Path 'admin-console/package-lock.json' -Line 1
        }
    }
    if ($PathSet.Contains('server/pom.xml')) {
        $pom = Get-Content -LiteralPath (Join-Path $Root 'server/pom.xml') -Raw -Encoding utf8
        if ($pom -notmatch '<licenses>' -or $pom -notmatch 'https://github\.com/3128698033/harmony-ocr' -or
            $pom -notmatch '(?is)<scm>.*?https://github\.com/3128698033/harmony-ocr.*?</scm>' -or
            $pom -notmatch '(?is)<developers>.*?<developer>.*?</developer>.*?</developers>') {
            Add-Finding -Findings $Findings -Rule 'Maven MIT metadata incomplete' -Path 'server/pom.xml' -Line 1
        }
    }
    if ($PathSet.Contains('.gitleaks.toml')) {
        $gitleaks = Get-Content -LiteralPath (Join-Path $Root '.gitleaks.toml') -Raw -Encoding utf8
        if ($gitleaks -notmatch '(?m)^\s*\[extend\]\s*$' -or $gitleaks -notmatch '(?m)^\s*useDefault\s*=\s*true\s*$') {
            Add-Finding -Findings $Findings -Rule 'Gitleaks default rules are not enabled' -Path '.gitleaks.toml' -Line 1
        }
    }
}

function Test-WorkflowPolicy {
    param([string] $Path, [string[]] $Lines, [System.Collections.Generic.List[string]] $Findings)
    $knownPins = @{
        'actions/checkout' = '9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0'
        'actions/setup-java' = '0f481fcb613427c0f801b606911222b5b6f3083a'
        'actions/setup-node' = '48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e'
        'actions/dependency-review-action' = 'a1d282b36b6f3519aa1f3fc636f609c47dddb294'
    }
    $permissionScopes = '(?:actions|attestations|checks|contents|deployments|discussions|id-token|issues|models|packages|pages|pull-requests|repository-projects|security-events|statuses)'
    $usesKeyPattern = '(?i)^(?<indent>\s*)(?<dash>-\s+)?(?<keyQuote>["'']?)uses\k<keyQuote>\s*:'
    $usesValuePattern = '(?i)^(?<indent>\s*)(?<dash>-\s+)?(?<keyQuote>["'']?)uses\k<keyQuote>\s*:\s*(?<valueQuote>["'']?)(?<action>[^@\s"''#]+)@(?<ref>[^"''\s#]+)\k<valueQuote>\s*(?:#.*)?$'
    $persistPattern = '(?i)^\s*(?<keyQuote>["'']?)persist-credentials\k<keyQuote>\s*:\s*(?<valueQuote>["'']?)false\k<valueQuote>\s*(?:#.*)?$'
    $writePattern = '(?i)(?:^\s*|[{,]\s*)(?<keyQuote>["'']?)' + $permissionScopes + '\k<keyQuote>\s*:\s*(?:&[A-Za-z0-9_-]+\s+)?(?<valueQuote>["'']?)write(?:-all)?\k<valueQuote>(?:\s|[,}#]|$)'
    $permissionAliasPattern = '(?i)(?:^\s*|[{,]\s*)(?<keyQuote>["'']?)(?:permissions|' + $permissionScopes + '|<<)\k<keyQuote>\s*:\s*(?:[&*][A-Za-z0-9_-]+|.*\s[&*][A-Za-z0-9_-]+)'
    $hasReadOnlyContents = $false

    # 只接受顶层显式权限块，防止 job 级权限、注释或 YAML 别名伪造全局只读权限。
    for ($permissionIndex = 0; $permissionIndex -lt $Lines.Count; $permissionIndex++) {
        if ($Lines[$permissionIndex] -notmatch '^(?<keyQuote>["'']?)permissions\k<keyQuote>\s*:\s*(?:#.*)?$') { continue }
        $childIndent = $null
        for ($childIndex = $permissionIndex + 1; $childIndex -lt $Lines.Count; $childIndex++) {
            $childLine = $Lines[$childIndex]
            $childTrimmed = $childLine.TrimStart()
            if ([string]::IsNullOrWhiteSpace($childTrimmed) -or $childTrimmed.StartsWith('#')) { continue }
            $indent = $childLine.Length - $childTrimmed.Length
            if ($indent -eq 0) { break }
            if ($null -eq $childIndent) { $childIndent = $indent }
            if ($indent -eq $childIndent -and
                $childLine -match '(?i)^\s+(?<keyQuote>["'']?)contents\k<keyQuote>\s*:\s*(?<valueQuote>["'']?)read\k<valueQuote>\s*(?:#.*)?$') {
                $hasReadOnlyContents = $true
            }
        }
        break
    }

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        $trimmed = $line.TrimStart()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }

        $usesDeclaration = [regex]::Match($line, $usesKeyPattern)
        if ($usesDeclaration.Success) {
            $match = [regex]::Match($line, $usesValuePattern)
            if (-not $match.Success) {
                Add-Finding -Findings $Findings -Rule 'action declaration must use a reviewable action@SHA value' -Path $Path -Line ($index + 1)
            } else {
                $action = $match.Groups['action'].Value
                $reference = $match.Groups['ref'].Value
                if (-not $action.StartsWith('./')) {
                    if ($reference -notmatch '^[0-9a-f]{40}$') {
                        Add-Finding -Findings $Findings -Rule 'action must use a 40-character SHA pin' -Path $Path -Line ($index + 1)
                    } elseif ($knownPins.ContainsKey($action) -and $knownPins[$action] -ne $reference) {
                        Add-Finding -Findings $Findings -Rule 'action uses an unreviewed SHA pin' -Path $Path -Line ($index + 1)
                    }
                }
                if ($action -eq 'actions/checkout') {
                    # checkout 必须在自己的 with 块中关闭凭据持久化，不能借用其他步骤或注释中的文本。
                    $stepIndent = $match.Groups['indent'].Value.Length
                    $propertyIndent = $stepIndent + $(if ($match.Groups['dash'].Success) { 2 } else { 0 })
                    $insideWith = $false
                    $persistConfigured = $false
                    for ($stepIndex = $index + 1; $stepIndex -lt $Lines.Count; $stepIndex++) {
                        $stepLine = $Lines[$stepIndex]
                        $stepTrimmed = $stepLine.TrimStart()
                        if ([string]::IsNullOrWhiteSpace($stepTrimmed) -or $stepTrimmed.StartsWith('#')) { continue }
                        $lineIndent = $stepLine.Length - $stepTrimmed.Length
                        if (($stepLine -match '^\s*-\s+' -and $lineIndent -le $stepIndent) -or $lineIndent -lt $propertyIndent) { break }
                        if ($lineIndent -eq $propertyIndent) {
                            $insideWith = $stepLine -match '(?i)^\s*(?<keyQuote>["'']?)with\k<keyQuote>\s*:\s*(?:#.*)?$'
                            continue
                        }
                        if ($insideWith -and $lineIndent -gt $propertyIndent -and $stepLine -match $persistPattern) {
                            $persistConfigured = $true
                        }
                    }
                    if (-not $persistConfigured) {
                        Add-Finding -Findings $Findings -Rule 'every checkout must disable persisted credentials in its own with block' -Path $Path -Line ($index + 1)
                    }
                }
            }
        }
        if ($line -match '\bpull_request_target\b') { Add-Finding -Findings $Findings -Rule 'pull_request_target is forbidden' -Path $Path -Line ($index + 1) }
        if ($line -match '(?i)(?:^\s*|[{,]\s*)(?<keyQuote>["'']?)permissions\k<keyQuote>\s*:\s*(?<valueQuote>["'']?)write-all\k<valueQuote>(?:\s|[,}#]|$)' -or
            $line -match $writePattern) {
            Add-Finding -Findings $Findings -Rule 'workflow write permission is forbidden' -Path $Path -Line ($index + 1)
        }
        if ($line -match $permissionAliasPattern) {
            Add-Finding -Findings $Findings -Rule 'workflow permission aliases and anchors are forbidden' -Path $Path -Line ($index + 1)
        }
        if ($line -match '(?i)\bsecrets\b(?:\s*(?:\.|\[|["'']?\s*:|\s+inherit\b)|(?=\s*\)))') {
            Add-Finding -Findings $Findings -Rule 'workflow repository secrets are forbidden' -Path $Path -Line ($index + 1)
        }
    }
    if (-not $hasReadOnlyContents) {
        Add-Finding -Findings $Findings -Rule 'workflow must grant top-level contents read permission explicitly' -Path $Path -Line 1
    }
}

function Test-GeneratedAdminDrift {
    param([string] $Root)
    $adminRoot = Join-Path $Root 'admin-console'
    $publishedRoot = Join-Path $Root 'server'
    foreach ($segment in @('src', 'main', 'resources', 'static', 'admin')) {
        $publishedRoot = Join-Path $publishedRoot $segment
    }
    if (-not (Test-Path -LiteralPath (Join-Path $adminRoot 'node_modules') -PathType Container)) {
        throw 'Generated admin drift check requires npm dependencies.'
    }
    $temporary = Join-Path ([System.IO.Path]::GetTempPath()) ('harmony-ocr-admin-drift-' + [System.Guid]::NewGuid().ToString('N'))
    try {
        # 直接调用项目锁定的 Vite shim，避免 npm 在不同平台对参数分隔符处理不同。
        $viteExecutable = Join-Path $adminRoot 'node_modules/.bin/vite'
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $viteExecutable += '.cmd' }
        if (-not (Test-Path -LiteralPath $viteExecutable -PathType Leaf)) {
            throw 'Local Vite executable is missing from npm dependencies.'
        }
        Push-Location -LiteralPath $adminRoot
        try {
            & $viteExecutable build --outDir $temporary --emptyOutDir
            if ($LASTEXITCODE -ne 0) { throw 'Temporary admin build failed.' }
        } finally {
            Pop-Location
        }
        $expected = @(Get-ChildItem -LiteralPath $temporary -File -Recurse | ForEach-Object { $_.FullName.Substring($temporary.Length + 1).Replace('\', '/') })
        $actual = @(Get-ChildItem -LiteralPath $publishedRoot -File -Recurse | ForEach-Object { $_.FullName.Substring($publishedRoot.Length + 1).Replace('\', '/') })
        if (Compare-Object ($expected | Sort-Object) ($actual | Sort-Object) -CaseSensitive) { throw 'Generated admin asset path drift detected.' }
        foreach ($path in $expected) {
            $expectedHash = (Get-FileHash -LiteralPath (Join-Path $temporary $path) -Algorithm SHA256).Hash
            $actualHash = (Get-FileHash -LiteralPath (Join-Path $publishedRoot $path) -Algorithm SHA256).Hash
            if ($expectedHash -ne $actualHash) { throw "Generated admin asset hash drift detected: $path" }
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}

Assert-SafeGitEnvironment
$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path.TrimEnd('\', '/')
if (Test-Path -LiteralPath (Join-Path $root '.git')) {
    Assert-NoPublicReparseAncestor -Root $root -RelativePath '.git'
}
$paths = @(Get-RelativePublicPaths -Root $root -RequestedPaths $RelativePaths)
$pathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$findings = New-Object 'System.Collections.Generic.List[string]'
$forbiddenRoots = @('logs', 'handoff', 'report', 'review', 'reference', 'design-output', 'tests')
$forbiddenExact = @(
    'AGENTS.md', 'docs/09-codex-task-log.md', 'scripts/export-public-repository.ps1',
    'scripts/public-export-files.txt', 'scripts/public-export-denylist.json',
    'scripts/tests/export-public-repository.Tests.ps1', 'scripts/tests/verify-public-export.Tests.ps1'
)
$internalMarkers = @(('LEGAL_OPS_' + 'CONFIRMATION_REQUIRED'), ('PASS_' + 'WITH_NOTES'), ('BLOCKED_' + 'WITH_EVIDENCE'))
$motionMarkers = @(('GS' + 'AP'), ('Green' + 'Sock'), ('@g' + 'sap/react'))
$credentialPattern = '^\s*(?:-\s*)?(?<quote>["'']?)(?<key>(?:[A-Za-z0-9_-]+[._-])*(?:password|secret|token|api[_-]?key|access[_-]?key|secret[_-]?key|jwt[_-]?secret))\k<quote>\s*[:=]\s*(?<value>.*)$'
$ipPattern = '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])'
$windowsHome = '(?<![A-Za-z0-9])[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s]+(?:[\\/]|$)'
$slash = [string][char]47
$macHome = '(?<![A-Za-z0-9._~-])' + $slash + 'Users' + $slash + '[^/\s]+(?:' + $slash + '|$)'
$linuxHome = '(?<![A-Za-z0-9._~-])' + $slash + 'home' + $slash + '[^/\s]+(?:' + $slash + '|$)'
$caseSensitiveRegex = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
$windowsRegex = $caseSensitiveRegex -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

if ($null -eq $RelativePaths -and (Test-Path -LiteralPath (Join-Path $root '.git'))) {
    $gitStatus = @(Invoke-PublicGit -Repository $root -Arguments @('status', '--porcelain=v1', '--untracked-files=all'))
    if ($gitStatus.Count -ne 0) { Add-Finding -Findings $findings -Rule 'Git worktree is not clean' -Path '.git' -Line 1 }
}

foreach ($path in $paths) {
    Assert-PublicPath -Path $path
    if (-not $pathSet.Add($path)) { throw 'Public path list contains a duplicate path.' }
    $fullPath = Join-Path $root $path
    Assert-NoPublicReparseAncestor -Root $root -RelativePath $path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Public path is missing: $path" }
    $item = Get-Item -LiteralPath $fullPath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Public path is a reparse point: $path" }
    $segments = @($path.Split('/'))
    $isForbidden = $forbiddenRoots -contains $segments[0] -or $forbiddenExact -contains $path -or
        $path.StartsWith('scripts/report/', [System.StringComparison]::Ordinal) -or
        $path.StartsWith('scripts/tests/', [System.StringComparison]::Ordinal) -or
        $path.StartsWith('docs/superpowers/', [System.StringComparison]::Ordinal) -or
        $path.StartsWith('app/entry/src/main/resources/rawfile/', [System.StringComparison]::Ordinal) -or
        $path.StartsWith('deploy/backup/', [System.StringComparison]::Ordinal)
    if ($isForbidden) {
        Add-Finding -Findings $findings -Rule 'forbidden public path' -Path $path -Line 1
        continue
    }
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    if (-not (Test-TextBytes -Bytes $bytes)) { continue }
    $lines = @(Get-TextLines -Bytes $bytes)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $lineNumber = $index + 1
        if ([regex]::IsMatch($line, $windowsHome, $windowsRegex) -or
            [regex]::IsMatch($line, $macHome, $caseSensitiveRegex) -or
            [regex]::IsMatch($line, $linuxHome, $caseSensitiveRegex)) {
            Add-Finding -Findings $findings -Rule 'absolute home or local path' -Path $path -Line $lineNumber
        }
        foreach ($match in [regex]::Matches($line, $ipPattern)) {
            if (Test-PrivateAddress -Value $match.Value) { Add-Finding -Findings $findings -Rule 'private network endpoint' -Path $path -Line $lineNumber }
        }
        if ($path -ne '.gitleaks.toml') {
            $credential = Get-CredentialAssignment -Path $path -Line $line -Pattern $credentialPattern
            if ($null -ne $credential -and -not (Test-AllowedCredentialValue -Path $path -Value $credential.Groups['value'].Value)) {
                Add-Finding -Findings $findings -Rule 'credential-shaped assignment' -Path $path -Line $lineNumber
            }
        }
        foreach ($marker in $internalMarkers) {
            if ($line.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Add-Finding -Findings $findings -Rule 'internal release marker' -Path $path -Line $lineNumber
            }
        }
        if ($line -match '(?i)\bGate\s+[0-9]') { Add-Finding -Findings $findings -Rule 'internal Gate marker' -Path $path -Line $lineNumber }
        foreach ($marker in $motionMarkers) {
            if ($line.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Add-Finding -Findings $findings -Rule 'special-license motion residue' -Path $path -Line $lineNumber
            }
        }
    }
    if ($path -match '^\.github/workflows/.+\.ya?ml$') { Test-WorkflowPolicy -Path $path -Lines $lines -Findings $findings }
}

Test-RequiredMetadata -Root $root -PathSet $pathSet -Findings $findings
if ($VerifyGeneratedAdminAssets) { Test-GeneratedAdminDrift -Root $root }
if ($findings.Count -ne 0) { throw ('Public repository policy failed:' + [Environment]::NewLine + ($findings -join [Environment]::NewLine)) }
Write-Output 'PASS: public repository policy'
