$urlFile = [Environment]::GetEnvironmentVariable("BAKE_RUNNER_URL")
if ([string]::IsNullOrEmpty($urlFile)) {
    $urlFile = "https://raw.githubusercontent.com/codearchitects/ca-bake/master/bake-init.ps1?$($(Get-Date).ToFileTimeUTC())"
}
Invoke-WebRequest $urlFile -OutFile bake-install.ps1
.\bake-install.ps1
Remove-Item bake-install.ps1