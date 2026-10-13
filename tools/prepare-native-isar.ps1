[CmdletBinding()]
param([string]$ArchiveCache = '')
. "$PSScriptRoot/native-isar-inputs.ps1"
$recipe = Get-NativeIsarRecipe
$parent = Join-Path $NativeIsarRepository '.local/native-isar'
Assert-NativeIsarPlainPath $parent
[IO.Directory]::CreateDirectory($parent) | Out-Null
$attempt = Join-Path $parent ('prepared-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($attempt) | Out-Null
$archives = Join-Path $attempt 'archives'
[IO.Directory]::CreateDirectory($archives) | Out-Null
$inputs = @(
    @{name='isar-3.3.2-source.zip'; spec=$recipe.isar; kind='zip'; destination='source'},
    @{name='libmdbx-source.zip'; spec=$recipe.mdbx; kind='zip'; destination='mdbx'},
    @{name='libclang-18.1.1-win64.whl'; spec=$recipe.libclang; kind='zip'; destination='libclang'}
)
foreach ($component in $recipe.rust.components) {
    $inputs += @{name=[IO.Path]::GetFileName(([Uri]$component.url).AbsolutePath); spec=$component; kind='tar.xz'; destination=('rust-' + $component.name)}
}
foreach ($input in $inputs) {
    $archive = Join-Path $archives $input.name
    if ($ArchiveCache) {
        $cached = Join-Path ([IO.Path]::GetFullPath($ArchiveCache)) $input.name
        if ((Get-NativeIsarDigest $cached) -cne $input.spec.sha256) { throw 'Cached native archive digest mismatch.' }
        Copy-Item -LiteralPath $cached -Destination $archive
    } else {
        $uri = [Uri]$input.spec.url
        if ($uri.Scheme -cne 'https' -or $uri.Host -notin @('codeload.github.com','static.rust-lang.org','files.pythonhosted.org')) { throw 'Unexpected native input origin.' }
        Invoke-WebRequest -Uri $uri -OutFile $archive
    }
    if ((Get-NativeIsarDigest $archive) -cne $input.spec.sha256) { throw 'Native archive digest mismatch.' }
    Expand-NativeIsarArchive $archive (Join-Path $attempt $input.destination) $input.kind
}
$rust = Join-Path $attempt 'rust'
[IO.Directory]::CreateDirectory($rust) | Out-Null
foreach ($component in $recipe.rust.components) {
    $expanded = Join-Path $attempt ('rust-' + $component.name)
    $container = @(Get-ChildItem -LiteralPath $expanded -Directory)
    if ($container.Count -ne 1) { throw 'Unexpected Rust archive layout.' }
    $part = $component.name
    if ($part -eq 'rust-std') { $part += '-' + $recipe.target }
    $partPath = Join-Path $container[0].FullName $part
    Assert-NativeIsarPlainPath $partPath
    if (-not (Test-Path -LiteralPath $partPath -PathType Container)) { throw 'Missing Rust component payload.' }
    foreach ($entry in Get-ChildItem -LiteralPath $partPath -Force) {
        if ($entry.Name -in @('manifest.in','install.sh')) { continue }
        Copy-Item -LiteralPath $entry.FullName -Destination $rust -Recurse -Force
    }
}
$clang = Join-Path (Join-Path $attempt 'libclang') $recipe.libclang.dllEntry
if ((Get-NativeIsarDigest $clang) -cne $recipe.libclang.dllSha256) { throw 'Libclang payload digest mismatch.' }
$compiler = Join-Path $rust 'bin/rustc.exe'
$version = @(& $compiler --version --verbose)
if ($LASTEXITCODE -ne 0 -or $version -cnotcontains ('release: ' + $recipe.rust.version) -or
    $version -cnotcontains ('commit-hash: ' + $recipe.rust.rustcCommit) -or $version -cnotcontains ('host: ' + $recipe.target)) { throw 'Rust compiler identity mismatch.' }
$cargoVersion = & (Join-Path $rust 'bin/cargo.exe') --version
if ($LASTEXITCODE -ne 0 -or $cargoVersion -cnotmatch ('^cargo ' + [Regex]::Escape($recipe.rust.version) + ' ')) { throw 'Cargo identity mismatch.' }
Write-NativeIsarJson (Join-Path $attempt 'prepared.json') ([ordered]@{
    schemaVersion=1; product=$recipe.product; bindingVersion=$recipe.bindingVersion; target=$recipe.target
    recipeFileSha256=Get-NativeIsarDigest (Join-Path $NativeIsarRepository 'native/isar-3.3.2/recipe.json')
    cargoLockSha256=$recipe.cargoLockSha256; state='prepared'; compiler=$version; cargo=$cargoVersion
})
Write-Output $attempt
