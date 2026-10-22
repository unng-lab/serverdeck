. "$PSScriptRoot/native-isar-artifact-inputs.ps1"
. "$PSScriptRoot/serverdeck-binding-source.ps1"

function Get-NativeArtifactAbiEvidence {
    param([Parameter(Mandatory)][string]$Artifact)
    $candidate=Get-NativeIsarCandidateArtifact $Artifact
    $recipe=Get-NativeIsarRecipe
    $dllHash=Get-NativeIsarDigest $candidate.dll
    $bytes=[IO.File]::ReadAllBytes($candidate.dll)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw 'Native ABI lacks a PE header.' }
    $pe=[BitConverter]::ToInt32($bytes,60)
    if ($pe -lt 64 -or $pe -gt $bytes.Length-26 -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or
        [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664 -or [BitConverter]::ToUInt16($bytes,$pe+24) -ne 0x20b) { throw 'Native ABI is not PE32+ x64.' }
    $binding=Get-ServerDeckBindingSource -WorkspaceRoot $NativeIsarRepository -PackageConfig 'packages/serverdeck_locald/.dart_tool/package_config.json'
    $bindingRoot=$binding.root
    if ($binding.bindingVersion -cne $recipe.bindingVersion) { throw 'Native ABI binding version mismatch.' }
    $bindings=Join-Path $bindingRoot 'lib/src/native/bindings.dart'
    $core=Join-Path $bindingRoot 'lib/src/native/isar_core.dart'
    foreach ($file in @($bindings,$core)) {
        Assert-NativeIsarPlainPath $file
        if ((Get-Item -LiteralPath $file).Length -gt 1MB) { throw 'Native ABI binding input oversized.' }
    }
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($bindings),"'(?<name>isar_[a-zA-Z0-9_]+)'")) { [void]$names.Add($match.Groups['name'].Value) }
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($core),"lookup\('(?<name>isar_[a-zA-Z0-9_]+)'\)")) { [void]$names.Add($match.Groups['name'].Value) }
    if ($names.Count -ne 93 -or -not $names.Contains('isar_instance_close') -or -not $names.Contains('isar_q_free')) { throw 'Native ABI binding export inventory mismatch.' }
    $symbols=[string[]]@($names)
    [Array]::Sort($symbols,[StringComparer]::Ordinal)
    if (-not ('ServerDeckNativeAbiProbe' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ServerDeckNativeAbiProbe {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 public static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
 [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate IntPtr Version();
}
'@
    }
    $library=[ServerDeckNativeAbiProbe]::LoadLibraryExW($candidate.dll,[IntPtr]::Zero,0x900)
    if ($library -eq [IntPtr]::Zero) { throw 'Native ABI safe library load failed.' }
    $versions=[ordered]@{}
    try {
        foreach ($name in $symbols) { [void][Runtime.InteropServices.NativeLibrary]::GetExport($library,$name) }
        foreach ($item in @(@{name='isar_version';expected=$recipe.bindingVersion},@{name='isar_mdbx_version';expected=$recipe.mdbx.tag})) {
            $pointer=[Runtime.InteropServices.NativeLibrary]::GetExport($library,$item.name)
            $function=[Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($pointer,[ServerDeckNativeAbiProbe+Version])
            $version=[Runtime.InteropServices.Marshal]::PtrToStringUTF8($function.Invoke())
            if ($version -cne $item.expected) { throw 'Native ABI version mismatch.' }
            $versions[$item.name]=$version
        }
    } finally { [Runtime.InteropServices.NativeLibrary]::Free($library) }
    if ((Get-NativeIsarDigest $candidate.dll) -cne $dllHash) { throw 'Native ABI DLL changed.' }
    return [ordered]@{schemaVersion=1;passed=$true;dllSha256=$dllHash;pe='PE32+ x64';bindingVersion=$recipe.bindingVersion;
        bindingSourceSha256=Get-NativeIsarDigest $bindings;coreSourceSha256=Get-NativeIsarDigest $core;requiredExports=$symbols;versions=$versions}
}
