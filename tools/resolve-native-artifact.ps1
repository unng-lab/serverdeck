[CmdletBinding()]
param()
. "$PSScriptRoot/native-artifact.ps1"
Get-NativeArtifactBuildSelection | ConvertTo-Json -Compress
