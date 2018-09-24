$urlFile = [Environment]::GetEnvironmentVariable("BAKE_RUNNER_URL")
if ([string]::IsNullOrEmpty($urlFile)) {
    $urlFile = "https://raw.githubusercontent.com/codearchitects/ca-bake/master/bake-install_next.ps1"
}
Invoke-WebRequest $urlFile -OutFile bake-install_next.ps1
.\bake-install_next.ps1
Remove-Item bake-install_next.ps1