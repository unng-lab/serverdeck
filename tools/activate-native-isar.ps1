[CmdletBinding()]
param([Parameter(Mandatory)][string]$CompatibilityReceipt,[Parameter(Mandatory)][string]$ReviewEvidence)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-artifact-activation.ps1"
$selected=Invoke-NativeArtifactActivation -CompatibilityReceipt $CompatibilityReceipt -ReviewEvidence $ReviewEvidence
'REVIEWED_NATIVE_BUILD_INPUT_ACTIVATED_PRODUCT_ACCEPTANCE_STILL_SEPARATE'
$selected | ConvertTo-Json -Depth 5
