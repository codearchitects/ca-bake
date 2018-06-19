$outFile = "bake-run.ps1"
Invoke-WebRequest https://raw.githubusercontent.com/codearchitects/ca-bake/master/bake-run.ps1 -OutFile $outFile
Install-PackageProvider -Scope CurrentUser  -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -force -Scope CurrentUser psyaml -AllowClobber
