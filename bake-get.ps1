$urlFile = [Environment]::GetEnvironmentVariable("BAKE_RUNNER_URL")
if([string]::IsNullOrEmpty($urlFile)) 
{
    $urlFile = "https://raw.githubusercontent.com/codearchitects/ca-bake/master/bake-setup.ps1"
}
Invoke-WebRequest $urlFile -OutFile build-setup.ps1
.\build-setup.ps1
.\build-run.ps1 -step CI