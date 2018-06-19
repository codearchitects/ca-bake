$urlFile = [Environment]::GetEnvironmentVariable("BAKE_RUNNER_URL")
if ([string]::IsNullOrEmpty($urlFile)) {
    $urlFile = "https://raw.githubusercontent.com/codearchitects/ca-bake/master/bake-install.ps1"
}
Invoke-WebRequest $urlFile -OutFile bake-install.ps1
.\bake-install.ps1
Remove-Item bake-install.ps1