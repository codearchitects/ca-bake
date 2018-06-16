$outFile = Join-Path $PSScriptRoot build-run.ps1
$urlFile = [Environment]::GetEnvironmentVariable("BAKE_RUNNER_URL")
if([string]::IsNullOrEmpty($urlFile)) 
{
    $urlFile = "https://raw.githubusercontent.com/codearchitects/ca-bake/master/bake-run.ps1"
}
Invoke-WebRequest $urlFile -OutFile $outFile
Install-PackageProvider -Scope CurrentUser  -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -force -Scope CurrentUser psyaml -AllowClobber