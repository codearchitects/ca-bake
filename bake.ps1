param($step)

import-module psyaml

# Functions

$bannerText = @"
 ______        _
(____  \      | |
 ____)  ) ____| |  _ ____
|  __  ( / _  | | / ) _  )
| |__)  | ( | | |< ( (/ /
|______/ \_||_|_| \_)____)
        by Code Architects

"@

Function PrintBanner() {
    Write-Host $bannerText -ForegroundColor Yellow
}

Function PrintStep([string] $text) {
    Write-Host "> $($text)" -ForegroundColor Yellow
}

Function PrintAction([string] $text) {
    Write-Host "> $($text)" -ForegroundColor Green
}

Function PathNugetFile([switch] $logout, [string] $file, [string] $feedName, [string] $useraname, [string] $pass) {
    if ($logout) {
        Remove-Item "NuGet.Config"
        Copy-Item -Path "NuGet.Config.original" -Destination "NuGet.Config" -Force
        Remove-Item "NuGet.Config.original"
        return
    }

    Copy-Item -Path $file -Destination "$file.original"

    $xml = [xml](Get-Content $file)

    # intention is to have

    # <configuration>
    #    <packageSourceCredentials>
    #        <feedName>
    #            <add key="Username" value="[useraname] />
    #            <add key="ClearTextPassword" value="[pass]" />
    #        </feedName>
    #    </packageSourceCredentials>
    # </configuration>


    # create the username node and set the attributes
    $userNameNode = $xml.CreateElement("add")
    $userNameNode.SetAttribute("key", "Username")
    $userNameNode.SetAttribute("value", $useraname)

    # create the password node and set the attributes
    $passwordNode = $xml.CreateElement("add")
    $passwordNode.SetAttribute("key", "ClearTextPassword")
    $passwordNode.SetAttribute("value", $pass)

    # create the feedName node and attach the username and password nodes
    $feedNameNode = $xml.CreateElement($feedName)
    [void] $feedNameNode.AppendChild($userNameNode)
    [void] $feedNameNode.AppendChild($passwordNode)

    # create the packageSourceCredentials node and append the feedName node
    $credentialsNode = $xml.CreateElement("packageSourceCredentials")
    [void] $credentialsNode.AppendChild($feedNameNode);

    # add the packageSourceCredentials node to the document's configuration node
    $xml.configuration.AppendChild($credentialsNode);

    # save the file to the same location
    $xml.Save((Join-Path $pwd $file))
}

Function SetupDocker ([switch]$logout) {
    if ($logout) {
        docker logout $Env:JFROG_DOCKER_LOCAL
        return
    }
    docker login $Env:JFROG_DOCKER_LOCAL -u="$Env:DOCKER_USERNAME" -p="$Env:DOCKER_PASSWORD"
}

Function CheckDockerStart () {
    $pathDockerForWindows = "C:\Program Files\Docker\Docker\Docker for Windows.exe"
    if ((Get-Command Get-WmiObject -errorAction SilentlyContinue) -and !(get-process | Where-Object {$_.path -eq $pathDockerForWindows})) {
        Write-Host "Docker is off, I'm starting it now..." -ForegroundColor Yellow
        if (-not (Test-Path env:IS_CI)) { & $pathDockerForWindows }
        do {docker ps 2>&1>$null; Start-Sleep 3} while ($lastexitcode -ne 0)
    }
}

Function LoadYaml ($filePath) {
    [string[]]$fileContent = Get-Content $filePath
    $content = ''
    foreach ($line in $fileContent) { $content = $content + "`n" + $line }
    $yaml = ConvertFrom-YAML $content
    return $yaml
}

Function LoadRecipe() {
    $yaml = LoadYaml(".\bake-recipe.yml")
    $recipe = New-Object Recipe
    $recipe.version = $yaml["version"]
    $recipe.name = $yaml["name"]
    $components = @()
    foreach ($item in $yaml["components"]) {
        $component = New-Object Component
        $component.name = $item["name"]
        $component.path = $item["path"]
        $component.type = $item["type"]
        $component.packageDist = $item["packageDist"]
        $component.packagePath = $item["packagePath"]
        $component.sourcePath = $item["sourcePath"]
        $component.package = $item["package"]
        $component.secrets = @()
        foreach ($items2 in $item["secrets"]) {
            $secretItem = New-Object Secret
            $secretItem.name = $items2["name"]
            $secretItem.items = $items2["items"]
            $component.secrets = $component.secrets + $secretItem
        }
        $components = $components + $component
    }
    $recipe.components = $components
    $recipe.environment = @{}
    $envItems = $yaml["environment"]
    foreach ($key in $envItems.Keys) {
        $recipe.environment.Add($key, $envItems[$key])
    }
    return $recipe
}

# Classes
Class Component {
    [string]$name
    [string]$path
    [string]$type
    [string]$packageDist
    [string]$sourcePath
    [string]$package
    [string]$packagePath
    [Secret[]]$secrets

    [boolean] IsDotNetPackage() {
        return $this.type -eq "dotnet-package"
    }

    [boolean] IsDotNetTest() {
        return $this.type -eq "dotnet-test"
    }

    [boolean] IsDotNetApp() {
        return $this.type -eq "dotnet-app"
    }

    [boolean] IsDotNetMigrationDbUp() {
        return $this.type -eq "dotnet-migration-dbup"
    }
}

Class Secret {
    [string]$name
    [Hashtable]$items
}

Class Recipe {
    [string]$version
    [string]$name
    [Hashtable]$environment
    [Component[]]$components

    [string] GetEnv([string]$envKey) {
        $ciEnv = [Environment]::GetEnvironmentVariable("BAKE_CI")
        $envValue = [Environment]::GetEnvironmentVariable($envKey)
        if ($ciEnv -eq "BAKE" -or [string]::IsNullOrEmpty($envValue)) {
            $envValue = $this.environment[$envKey]
        }
        return $envValue
    }

    [string] GetBuildVersion() {
        return "$($this.GetEnv("BAKE_BUILD_VERSION"))"
    }

    [string] GetBuildNumber() {
        return $this.GetEnv("BAKE_BUILD_NUMBER")
    }

    [string] GetVersion() {
        $env = $this.GetEnv("BAKE_VERSION")
        if ([string]::IsNullOrEmpty($env)) {
            $env = "$($this.GetBuildVersion()).$($this.GetBuildNumber())"
        }
        return $env
    }

    [string] GetNugetFeed() {
        return $this.GetEnv("BAKE_NUGET_FEED")
    }

    [string] GetNugetFeedApiKey() {
        return $this.GetEnv("BAKE_NUGET_FEED_API_KEY")
    }

    [string] GetNugetUsername() {
        return $this.GetEnv("BAKE_NUGET_USERNAME")
    }

    [string] GetNugetPassword() {
        return $this.GetEnv("BAKE_NUGET_PASSWORD")
    }
}

# Build Steps

Function Clean([Recipe] $recipe) {
    $error = $false
    $errorMessage = ""
    PrintStep "Started the CLEAN step"
    foreach ($component in $recipe.components) {
        PrintAction "Cleaning component $($component.name)"
        $path = Join-Path $PSScriptRoot $component.path
        PrintAction "Pushing location $($path)"
        Push-Location $path
        $vsProjectFile = "$($component.name).csproj"
        PrintAction "Cleaning $($vsProjectFile)..."
        dotnet clean $vsProjectFile
        if ($LastExitCode -ne 0) {
            $error = $true
            $errorMessage = "Failed to clean $($component.name)"
        }
        Pop-Location
        if ($error) {break}
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the CLEAN step"
}

Function Setup([Recipe] $recipe) {
    $error = $false
    $errorMessage = ""
    PrintStep "Started the SETUP step"
    PathNugetFile "NuGet.Config" "nugetfeed" $recipe.GetNugetUsername() $recipe.GetNugetPassword()
    foreach ($component in $recipe.components) {

        if ($component.IsDotNetApp()) { continue }

        PrintAction "Restoring component $($component.name)"
        $path = Join-Path $PSScriptRoot $component.path
        PrintAction "Pushing location $($path)"
        Push-Location $path
        PrintAction "Restoring $($component.name)..."
        $configFile = Join-Path $PSScriptRoot NuGet.Config
        dotnet restore --force --configfile $configFile
        if ($LastExitCode -ne 0) {
            $error = $true
            $errorMessage = "Failed to restore $($component.name)"
        }
        Pop-Location
        if ($error) {break}
    }
    PathNugetFile -logout
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the SETUP step"
}

Function Build([Recipe] $recipe) {
    $error = $false
    $errorMessage = ""
    PathNugetFile "NuGet.Config" "nugetfeed" $recipe.GetNugetUsername() $recipe.GetNugetPassword()
    PrintStep "Started the BUILD step"
    foreach ($component in $recipe.components) {
        PrintAction "Building $($component.type) component $($component.name)"
        $path = Join-Path $PSScriptRoot $component.path
        if ($component.IsDotNetPackage() -or $component.IsDotNetMigrationDbUp()) {
            PrintAction "Pushing location $($path)"
            Push-Location $path
            $vsProjectFile = "$($component.name).csproj"
            PrintAction "Building $($vsProjectFile)..."
            dotnet build $vsProjectFile --no-restore --configuration Release
            Pop-Location
        }
        elseif ($component.IsDotNetApp()) {
            $DockerfilePath = Join-Path $path "Dockerfile"
            PrintAction "Building $($component.name) in Docker..."
            CheckDockerStart
            docker build -f $DockerfilePath .
        }
        if ($LastExitCode -ne 0) {
            $error = $true
            $errorMessage = "Failed to build $($component.name)"
        }
        if ($error) {break}
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the BUILD step"
    PathNugetFile -logout
}

Function Test([Recipe] $recipe) {
    $error = $false
    $errorMessage = ""
    PrintStep "Started the TEST step"
    foreach ($component in $recipe.components) {
        if ($component.IsDotNetTest()) {
            PrintAction "Testing component $($component.name)"
            $path = Join-Path $PSScriptRoot $component.path
            PrintAction "Pushing location $($path)"
            Push-Location $path
            $vsProjectFile = "$($component.name).csproj"
            PrintAction "Testing $($vsProjectFile)..."
            dotnet test $vsProjectFile
            if ($LastExitCode -ne 0) {
                $error = $true
                $errorMessage = "Failed to test $($component.name)"
            }
            Pop-Location
            if ($error) {break}
        }
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the TEST step"
}

Function Pack([Recipe] $recipe) {
    $error = $false
    $errorMessage = ""
    PrintStep "Started the PACK step"
    foreach ($component in $recipe.components) {
        PrintAction "Packing component $($component.name)"
        $path = Join-Path $PSScriptRoot $component.path
        if ($component.IsDotNetPackage()) {
            PrintAction "Pushing location $($path)"
            Push-Location $path
            PrintAction "Packing $($component.name)..."
            $version = $recipe.GetVersion()
            $distPath = Join-Path $PSScriptRoot $component.packageDist
            dotnet pack /p:Version="$version,PackageVersion=$version" --no-dependencies --force -c Release --output $distPath
        }
        elseif ($component.IsDotNetMigrationDbUp()) {
            $source = Join-Path $component.path $component.sourcePath
            $destination = Join-Path $component.packageDist ($component.name + ".latest.zip")
            if (-not (Test-path $component.packageDist)) { new-item -Name $component.packageDist -ItemType directory }
            if (Test-path $destination) { Remove-item $destination -Force -ErrorAction SilentlyContinue }
            Compress-Archive -Path $source -CompressionLevel Optimal -DestinationPath $destination
        }
        if ($LastExitCode -ne 0) {
            $error = $true
            $errorMessage = "Failed to pack $($component.name)"
        }
        Pop-Location
        if ($error) {break}
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the PACK step"
}

Function Publish([Recipe] $recipe) {
    $error = $false
    $errorMessage = ""
    PrintStep "Started the PUBLISH step"
    foreach ($component in $recipe.components) {
        PrintAction "Pushing $($component.type) component $($component.name)"
        $path = Join-Path $PSScriptRoot $component.packageDist
        if ($component.IsDotNetPackage()) {
            PrintAction "Pushing location $($path)"
            Push-Location $path
            $version = $recipe.GetVersion()
            $package = "$($component.package).$($version).nupkg"
            $source = "$($recipe.GetNugetFeed())/$($component.packagePath)"
            Write-Host "Publishing package $($package)"
            dotnet nuget push $package -k $recipe.GetNugetFeedApiKey() -s $source
            Pop-Location
        }
        elseif ($component.IsDotNetApp()) {
            SetupDocker
            $imageName = $($component.name).ToLower().Trim()
            docker tag $imageName":latest" $Env:JFROG_DOCKER_LOCAL/$imageName":latest"
            docker push $Env:JFROG_DOCKER_LOCAL/$imageName":latest"
            SetupDocker -logout
        }
        elseif ($component.IsDotNetMigrationDbUp()) {
            $file = Join-Path $component.packageDist ($component.name + ".latest.zip")
            $fileName = $component.name + ".latest.zip"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -TimeoutSec 9200 -UseBasicParsing -Uri (New-Object System.Uri ($Env:BAKE_ARTIFACTS_REPO_URI + $component.name + "/" + $fileName)) -InFile $file -Method Put -Credential (New-Object System.Management.Automation.PSCredential ($Env:BAKE_NUGET_USERNAME), (ConvertTo-SecureString ($Env:BAKE_NUGET_PASSWORD) -AsPlainText -Force))
        }
    }
    if ($LastExitCode -ne 0) {
        $error = $true
        $errorMessage = "Failed to publish $($component.name)"
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    if ($error) {break}
    PrintStep "Completed the PUBLISH step"
}

Function SetupBox([Recipe] $recipe) {
    $error = $false
    $errorMessage = ""
    PrintStep "Started the SETUPBOX step"
    foreach ($component in $recipe.components) {
        if (($component.IsDotNetApp()) -or ($component.IsDotNetTest())) {
            PrintAction "SETUPBOX for the component $($component.name)"
            $path = Join-Path $PSScriptRoot ("\" + $component.path)
            PrintAction "Pushing location $($path)"
            Push-Location $path
            dotnet user-secrets clear
            if ($LastExitCode -ne 0) {
                $error = $true
                $errorMessage = "Failed to clear user secrets $($component.name)"
            }
            else {
                foreach ($secret in $component.secrets) {
                    foreach ($key in $secret.items.Keys) {
                        $secretKey = $secret.name + ':' + $key
                        Write-Host $secretKey -ForegroundColor DarkGreen
                        $input = $secret.items[$key]
                        if (-not ([string]::IsNullOrEmpty($input))) {
                            Write-Host $input
                        }
                        else {
                            $input = Read-Host
                        }
                        dotnet user-secrets set $secretKey $input
                        if ($LastExitCode -ne 0) {
                            $error = $true
                            $errorMessage = "Failed to setup box $($component.name)"
                        }
                        if ($error) {break}
                    }
                    if ($error) {break}
                }
            }
            Pop-Location
            if ($error) {break}
        }
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the SETUPBOX step"
}

Function docker.start ([Recipe] $recipe) {
    $error = $false
    $errorMessage = ""
    PrintStep "Started the DOCKER.START step"
    PathNugetFile "NuGet.Config" "nugetfeed" $recipe.GetNugetUsername() $recipe.GetNugetPassword()
    CheckDockerStart
    Write-Host "I'm starting all project's containers..." -ForegroundColor Yellow
    if (Test-Path env:IS_CI) {
        docker-compose -f docker-compose.yml --log-level ERROR up -d --remove-orphans 
    }
    else {
        docker-compose up -d --remove-orphans 
    }
    PathNugetFile -logout
    if ($error) { Write-Error "$($errorMessage)" }
    PrintStep "Completed the DOCKER.START step"
}

Function docker.stop () {
    $error = $false
    $errorMessage = ""
    PrintStep "Started the DOCKER.STOP step"
    Write-Host "I'm stopping all project's containers..." -ForegroundColor Yellow
    if (Test-Path env:IS_CI) { docker-compose -f docker-compose.yml --log-level ERROR down } else { docker-compose down }
    if (docker ps -aq) { docker rm $(docker ps -aq) -f }
    if ($error) { Write-Error "$($errorMessage)" }
    PrintStep "Completed the DOCKER.STOP step"
}

Function docker.clean () {
    docker system prune -f
    docker volume prune -f
    docker network prune -f
}

if ([string]::IsNullOrEmpty($step)) {
    return
}
PrintBanner
$recipe = LoadRecipe
PrintStep "Loaded recipe: $($recipe.name)"

if ($step -eq "CODE" -or $step -eq "CI" -or $step -eq "RC" -or $step -eq "CLEAN") {
    Clean($recipe)
}
if ($step -eq "CODE" -or $step -eq "CI" -or $step -eq "RC" -or $step -eq "SETUP") {
    Setup($recipe)
}
if ($step -eq "CI" -or $step -eq "RC" -or $step -eq "BUILD") {
    Build($recipe)
}
if ($step -eq "CI" -or $step -eq "RC" -or $step -eq "TEST") {
    Test($recipe)
}
if ($step -eq "CI" -or $step -eq "RC" -or $step -eq "PACK") {
    Pack($recipe)
}
if ($step -eq "RC" -or $step -eq "PUBLISH") {
    Publish($recipe)
}
if ($step -eq "SETUPBOX") { SetupBox($recipe) }
if ($step -eq "DOCKER.START") { docker.start($recipe) }
if ($step -eq "DOCKER.STOP") { docker.stop }
if ($step -eq "DOCKER.CLEAN") { docker.clean }