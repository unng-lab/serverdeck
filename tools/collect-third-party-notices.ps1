[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$SdkDirectory = '',
    [string]$OutputDirectory = 'build/foundation/notices',
    [string]$NativeArtifact = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$boundNative = $null
if ($NativeArtifact) {
    . "$PSScriptRoot/native-isar-artifact-inputs.ps1"
    if ([IO.Path]::GetFullPath($WorkspaceRoot) -cne $NativeIsarRepository) { throw 'Bound native notices require the actual repository workspace.' }
    $boundNative = Get-NativeIsarCandidateArtifact $NativeArtifact
}
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory, $WorkspaceRoot)
$workspacePrefix = $WorkspaceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $OutputDirectory.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Notices output must remain inside workspace.' }
for ($parent = $OutputDirectory; $parent; $parent = Split-Path $parent -Parent) {
    if ((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Notices output cannot traverse a reparse point.' }
}
if ($boundNative) {
    $nativePrefix = (Join-Path $WorkspaceRoot '.local/native-isar') + [IO.Path]::DirectorySeparatorChar
    if ($OutputDirectory.StartsWith($nativePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $OutputDirectory -ceq $nativePrefix.TrimEnd([IO.Path]::DirectorySeparatorChar) -or
        (Test-Path -LiteralPath $OutputDirectory)) { throw 'Bound native notices require a fresh output outside native input artifacts.' }
}
if (-not $SdkDirectory) {
    $SdkDirectory = Join-Path $WorkspaceRoot '.local/sdk/3.47.7/flutter'
    if ($env:SERVERDECK_FLUTTER_ROOT) { $SdkDirectory = $env:SERVERDECK_FLUTTER_ROOT }
}
$SdkDirectory = [IO.Path]::GetFullPath($SdkDirectory)
$sdkIdentity = Get-Content -LiteralPath (Join-Path $SdkDirectory 'bin/cache/flutter.version.json') -Raw | ConvertFrom-Json
if ($sdkIdentity.frameworkVersion -ne '3.47.7' -or $sdkIdentity.dartSdkVersion -ne '3.13.5' -or $sdkIdentity.frameworkRevision -ne 'abaf9c523780a608bd46686fd5e53740a07077f8') { throw 'Pinned SDK source identity mismatch.' }
$sourceItems = @{}
function Add-NoticeText {
    param([string]$Id, [string]$FilePath, [string]$SourceUrl, [string]$ExpectedHash = '')
    $bytes = [IO.File]::ReadAllBytes($FilePath)
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if (-not $text.Trim().Trim([char]0xfeff)) { throw "Empty notice: $Id" }
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    if ($ExpectedHash -and $hash -cne $ExpectedHash) { throw "Pinned notice hash mismatch: $Id" }
    if ($sourceItems.ContainsKey($Id)) {
        if ($sourceItems[$Id].sha256 -cne $hash) { throw "Conflicting notice sources: $Id" }
        return
    }
    $sourceItems[$Id] = [ordered]@{ id = $Id; sha256 = $hash; source = $SourceUrl; text = $text }
}
$resolvedPackages = @{}
$contexts = [ordered]@{ root = ''; serverdeck_locald = 'packages/serverdeck_locald'; serverdeck_protocol = 'packages/serverdeck_protocol'; serverdeck_windows = 'packages/serverdeck_windows' }
foreach ($context in $contexts.GetEnumerator()) {
    $packageRoot = Join-Path $WorkspaceRoot $context.Value
    $config = Get-Content -LiteralPath (Join-Path $packageRoot '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
    if ($config.configVersion -ne 2) { throw 'Unsupported package config version.' }
    $lock = [IO.File]::ReadAllText((Join-Path $packageRoot 'pubspec.lock'))
    $hosted = @{}
    foreach ($block in [regex]::Matches($lock, '(?ms)^  (?<name>[a-zA-Z0-9_]+):\r?\n(?<body>.*?)(?=^  [a-zA-Z0-9_]+:|\z)')) {
        if ($block.Groups['body'].Value -match '(?m)^    source: hosted\r?$') {
            $version = [regex]::Match($block.Groups['body'].Value, '(?m)^    version: "([^"\r\n]+)"\r?$')
            if (-not $version.Success) { throw 'Hosted package lock version missing.' }
            $hosted[$block.Groups['name'].Value] = $version.Groups[1].Value
        }
    }
    if ($hosted.Count -eq 0) { throw 'Hosted package lock inventory empty.' }
    foreach ($name in $hosted.Keys) {
        $entries = @($config.packages | Where-Object name -CEQ $name)
        if ($entries.Count -ne 1) { throw "Missing or duplicate package config: $name" }
        $uri = [Uri]$entries[0].rootUri
        if (-not $uri.IsAbsoluteUri -or -not $uri.IsFile) { throw "Hosted package source must be a local file URI: $name" }
        $root = $uri.LocalPath
        $pubspec = [IO.File]::ReadAllText((Join-Path $root 'pubspec.yaml'))
        $installedName = [regex]::Match($pubspec, '(?m)^name:\s*[''"]?([^\s''"#]+)').Groups[1].Value
        $installedVersion = [regex]::Match($pubspec, '(?m)^version:\s*[''"]?([^\s''"#]+)').Groups[1].Value
        if ($installedName -cne $name -or $installedVersion -cne $hosted[$name]) { throw "Package lock/source identity mismatch: $name" }
        $id = "$name@$installedVersion"
        # LICENSE is mandatory; additional root notices are included unabridged.
        if (-not (Test-Path -LiteralPath (Join-Path $root 'LICENSE') -PathType Leaf)) { throw "Package LICENSE missing: $id" }
        $noticeFiles = @(Get-ChildItem -LiteralPath $root -File | Where-Object Name -Match '^(LICENSE|COPYING|NOTICE)([._-].*)?$')
        foreach ($file in $noticeFiles) { Add-NoticeText "$id/$($file.Name)" $file.FullName "https://pub.dev/packages/$name/versions/$installedVersion" }
        if (-not $resolvedPackages.ContainsKey($id)) { $resolvedPackages[$id] = [ordered]@{ id = $id; contexts = [Collections.Generic.List[string]]::new() } }
        $resolvedPackages[$id].contexts.Add($context.Key)
    }
}
Add-NoticeText 'sdk/flutter-3.47.7/LICENSE' (Join-Path $SdkDirectory 'LICENSE') 'https://github.com/flutter/flutter/tree/abaf9c523780a608bd46686fd5e53740a07077f8'
Add-NoticeText 'sdk/dart-3.13.5/LICENSE' (Join-Path $SdkDirectory 'bin/cache/dart-sdk/LICENSE') 'https://github.com/dart-lang/sdk'
Add-NoticeText 'sdk/sky_engine/LICENSE' (Join-Path $SdkDirectory 'bin/cache/pkg/sky_engine/LICENSE') 'https://github.com/flutter/engine/tree/deb287481e3ce9468f3434937ced4240a70539ca'
Add-NoticeText 'fonts/Noto/OFL.txt' (Join-Path $WorkspaceRoot 'assets/brand/fonts/OFL.txt') 'https://openfontlicense.org/open-font-license-official-text/'
if ($boundNative) {
    Add-NoticeText 'native/THIRD_PARTY_NATIVE_NOTICES.txt' (Join-Path $boundNative.directory 'THIRD_PARTY_NATIVE_NOTICES.txt') 'native/native-notice-inventory.json'
} else {
$nativeRoot = Join-Path $WorkspaceRoot 'docs/development/licenses/native'
$native = Get-Content -LiteralPath (Join-Path $nativeRoot 'sources.json') -Raw | ConvertFrom-Json
if ($native.format -ne 1 -or $native.status -cne 'incomplete-native-chain' -or $native.sources.Count -ne 5) { throw 'Native preview inventory mismatch.' }
$expectedNativeIds = @('isar-3.3.2/NOTICE', 'mdbx-sys-13.7.0/MPL-2.0', 'libmdbx-source/LICENSE', 'libmdbx-source/NOTICE', 'libmdbx-source/COPYRIGHT')
$nativeIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($source in $native.sources) {
    if ($expectedNativeIds -cnotcontains $source.id -or -not $nativeIds.Add($source.id)) { throw 'Native preview inventory mismatch.' }
    if ($source.file -notmatch '^[a-zA-Z0-9._-]+\.txt$' -or $source.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid pinned native source metadata.' }
    $sourceUri = [Uri]$source.url
    if ($sourceUri.Scheme -ne 'https' -or $sourceUri.UserInfo -or $sourceUri.Query -or $sourceUri.Fragment) { throw 'Native source URL must be a public HTTPS reference.' }
    Add-NoticeText "native/$($source.id)" (Join-Path $nativeRoot $source.file) $source.url $source.sha256
}
}
$ids = [string[]]@($sourceItems.Keys)
[Array]::Sort($ids, [StringComparer]::Ordinal)
$builder = [Text.StringBuilder]::new()
if ($boundNative) {
    [void]$builder.Append("SERVERDECK THIRD-PARTY NOTICES`nStatus: bound-native-notices-unqualified; distributionReady=false.`nIncludes resolved hosted development dependencies and full native vendor notices; inclusion does not assert shipping.`nNative corresponding sources and exact provenance are in native/. Qualification, activation and product acceptance remain separate gates.`n")
} else {
    [void]$builder.Append("SERVERDECK THIRD-PARTY NOTICES PREVIEW`nStatus: incomplete-native-chain; NOT A DISTRIBUTION NOTICE BUNDLE.`nIncludes resolved hosted development dependencies; inclusion does not assert shipping.`nDLL build provenance and native transitive dependency coverage remain unverified (T045).`n")
}
$inventory = foreach ($id in $ids) {
    $source = $sourceItems[$id]
    [void]$builder.Append("`n==================== $id ====================`nSource: $($source.source)`nSource SHA-256: $($source.sha256)`n`n")
    [void]$builder.Append($source.text)
    [void]$builder.Append("`n")
    [ordered]@{ id = $source.id; source = $source.source; sha256 = $source.sha256 }
}
$packageIds = [string[]]@($resolvedPackages.Keys)
[Array]::Sort($packageIds, [StringComparer]::Ordinal)
$utf8 = [Text.UTF8Encoding]::new($false)
$previewBytes = $utf8.GetBytes($builder.ToString())
$metadata = [ordered]@{
    format = 1; status = 'incomplete-native-chain'; distributionReady = $false
    previewSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($previewBytes)).ToLowerInvariant()
    packages = @($packageIds | ForEach-Object { $resolvedPackages[$_] })
    sources = @($inventory)
}
if ($boundNative) {
    $metadata.status = 'bound-native-notices-unqualified'
    $metadata.noticesSha256 = $metadata.previewSha256
    $metadata.Remove('previewSha256')
    $metadata.native = [ordered]@{ artifactManifestFile = 'native/native-artifact.json'; artifactManifestSha256 = $boundNative.manifestSha256; dllSha256 = Get-NativeIsarDigest $boundNative.dll; payloadRole = 'corresponding-source-and-provenance-copy; libisar.dll belongs to application root'; payload = @($boundNative.manifest.files | Where-Object file -CNE 'libisar.dll') }
}
# All input validation completed before any output replacement.
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputs = @(
    @{ path = Join-Path $OutputDirectory 'THIRD_PARTY_NOTICES.preview.txt'; bytes = $previewBytes },
    @{ path = Join-Path $OutputDirectory 'notices.preview.json'; bytes = $utf8.GetBytes(($metadata | ConvertTo-Json -Depth 6) + "`n") }
)
if ($boundNative) {
    $outputs[0].path = Join-Path $OutputDirectory 'THIRD_PARTY_NOTICES.txt'
    $outputs[1].path = Join-Path $OutputDirectory 'third-party-notices.json'
    foreach ($file in $metadata.native.payload) {
        $destination = Join-Path $OutputDirectory ('native/' + $file.file)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $boundNative.directory $file.file) -Destination $destination
        if ((Get-NativeIsarDigest $destination) -cne $file.sha256) { throw 'Bound notice payload copy mismatch.' }
    }
    Copy-Item -LiteralPath (Join-Path $boundNative.directory 'native-artifact.json') -Destination (Join-Path $OutputDirectory 'native/native-artifact.json')
    if ((Get-NativeIsarDigest (Join-Path $OutputDirectory 'native/native-artifact.json')) -cne $boundNative.manifestSha256 -or
        (Get-NativeIsarCandidateArtifact $boundNative.directory).manifestSha256 -cne $boundNative.manifestSha256) { throw 'Bound native input changed during collection.' }
}
foreach ($output in $outputs) {
    $existing = Get-Item -LiteralPath $output.path -Force -ErrorAction SilentlyContinue
    if ($existing -and (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $existing.PSIsContainer)) { throw 'Notices output file cannot be a reparse point or directory.' }
}
foreach ($output in $outputs) {
    $temporary = Join-Path $OutputDirectory ('.notices-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($output.bytes, 0, $output.bytes.Length) } finally { $stream.Dispose() }
        # Replace the directory entry, never truncate an existing hardlink target.
        [IO.File]::Move($temporary, $output.path, $true)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
[pscustomobject]@{ Status = $metadata.status; Packages = $resolvedPackages.Count; Sources = $sourceItems.Count }
