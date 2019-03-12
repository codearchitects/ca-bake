$ErrorActionPreference = "Stop"
$global:ProgressPreference = "SilentlyContinue"
$urlFile = [Environment]::GetEnvironmentVariable("BAKE_RUNNER_URL")
import-module psyaml
[string[]]$fileContent = Get-Content ".\bake-recipe.yml"
$content = ''
foreach ($line in $fileContent) { $content = $content + "`n" + $line }
$yaml = ConvertFrom-YAML $content
$version = $yaml["version"]
if ([string]::IsNullOrEmpty($urlFile)) {
    $urlFile = "https://raw.githubusercontent.com/codearchitects/ca-bake/master/versions/$version/bake-install.ps1?$($(Get-Date).ToFileTimeUTC())"
}
Invoke-WebRequest $urlFile -OutFile bake-install.ps1
.\bake-install.ps1
Remove-Item bake-install.ps1