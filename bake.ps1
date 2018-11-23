param($step)

$ErrorActionPreference = "Stop"

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
        do { $ErrorActionPreference = "SilentlyContinue"; docker ps 2>&1>$null; $ErrorActionPreference = "Stop"; Start-Sleep 3 } while ($lastexitcode -ne 0)
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
        $component.codequality = $item["codequality"]
        $component.buildProfile = $item["buildProfile"]
        $component.optional = @()
        foreach ($itemOptional in $item["optional"]) {
            $component.optional += $itemOptional
        }
        $component.packageDist = $item["packageDist"]
        $component.packagePath = $item["packagePath"]
        $component.sourcePath = $item["sourcePath"]
        $component.package = $item["package"]
        $component.secrets = @()
        foreach ($items2 in $item["secrets"]) {
            $secretItem = New-Object Secret
            $secretItem.name = $items2["name"]
            $secretItem.items = $items2["items"]
            $component.secrets += $secretItem
        }
        $components += $component
    }
    $recipe.components = $components
    $recipe.environment = @{}
    $envItems = $yaml["environment"]
    foreach ($key in $envItems.Keys) {
        $recipe.environment.Add($key, $envItems[$key])
    }
    return $recipe
}

Function CheckOptional() {
    $optionalStep = [string]$(Get-PSCallStack)[1].FunctionName.ToLower()
    if ($env:BAKE_OPTIONAL_ENABLED -eq $true -and $component.optional.Contains($optionalStep) -eq $true) {
        PrintAction "Skipping optional component $($component.name)"
        return $true
    }
    return $false
}

# Classes
Class Component {
    [string]$name
    [string]$path
    [string]$type
    [string]$codequality
    [string]$buildProfile
    [string[]]$optional
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
    
    [boolean] IsAspNetApp() {
        return $this.type -eq "aspnet-app"
    }

    [boolean] IsDotNetTestApp() {
        return $this.type -eq "dotnet-test-app"
    }

    [boolean] IsDotNetMigrationDbUp() {
        return $this.type -eq "dotnet-migration-dbup"
    }

    [boolean] CodeQualityCheck() {
        return $this.codequality -eq $true
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
    PrintStep "Started the CLEAN step"
    Remove-Item "dist" -Force -Recurse -ErrorAction SilentlyContinue
    foreach ($component in $recipe.components) {
        if (CheckOptional) { continue }
        if ($component.IsAspNetApp()) { continue }
        PrintAction "Cleaning component $($component.name)"
        $path = Join-Path $PSScriptRoot $component.path
        PrintAction "Pushing location $($path)"
        Push-Location $path
        $vsProjectFile = "$($component.name).csproj"
        PrintAction "Cleaning $($vsProjectFile)..."
        dotnet clean $vsProjectFile
        Pop-Location
    }
    PrintStep "Completed the CLEAN step"
}

Function Setup([Recipe] $recipe) {
    PrintStep "Started the SETUP step"
    PathNugetFile "NuGet.Config" "nugetfeed" $recipe.GetNugetUsername() $recipe.GetNugetPassword()
    foreach ($component in $recipe.components) {
        if (CheckOptional) { continue }
        if ($component.IsDotNetApp() -or $component.IsAspNetApp() -or $component.IsDotnetTestApp()) { continue }
        PrintAction "Restoring component $($component.name)"
        $path = Join-Path $PSScriptRoot $component.path
        PrintAction "Pushing location $($path)"
        Push-Location $path
        PrintAction "Restoring $($component.name)..."
        $configFile = Join-Path $PSScriptRoot NuGet.Config
        dotnet restore --force --configfile $configFile
        Pop-Location
    }
    PathNugetFile -logout
    PrintStep "Completed the SETUP step"
}

Function Build([Recipe] $recipe) {
    PrintStep "Started the BUILD step"
    PathNugetFile "NuGet.Config" "nugetfeed" $recipe.GetNugetUsername() $recipe.GetNugetPassword()
    foreach ($component in $recipe.components) {
        if (CheckOptional) { continue }
        PrintAction "Building $($component.type) component $($component.name)"
        $version = $recipe.GetVersion()
        $path = Join-Path $PSScriptRoot $component.path
        $buildProfile = @{$true = $component.buildProfile; $false = "Release"}[(-not ([string]::IsNullOrEmpty($component.buildProfile)))]
        if ($component.IsDotNetPackage() -or $component.IsDotNetMigrationDbUp()) {
            PrintAction "Pushing location $($path)"
            Push-Location $path
            $vsProjectFile = "$($component.name).csproj"
            PrintAction "Building $($vsProjectFile)..."
            dotnet build $vsProjectFile --no-restore --configuration $buildProfile
            Pop-Location
        }
        if ($component.IsDotNetApp() -or $component.IsDotnetTestApp() -or $component.IsDotNetMigrationDbUp()) {
            $DockerfilePath = Join-Path $path "Dockerfile"
            PrintAction "Building $($component.name) in Docker..."
            CheckDockerStart
            $imageName = $($component.name).ToLower().Trim()
            docker build -f $DockerfilePath . -t $imageName":"$version
        }
        if ($component.IsAspNetApp()) {
            $DockerfilePath = Join-Path $path "Dockerfile"
            PrintAction "Building $($component.name) in Docker..."
            CheckDockerStart
            $imageName = $($component.name).ToLower().Trim()
            docker build -f $DockerfilePath . -t $imageName":"$version
            docker run --rm -u $(id -u) -v ${pwd}:/app --name temp_build_dist $imageName":"$version
        }
    }
    PathNugetFile -logout
    PrintStep "Completed the BUILD step"
}

Function Test([Recipe] $recipe) {
    PrintStep "Started the TEST step"
    PathNugetFile "NuGet.Config" "nugetfeed" $recipe.GetNugetUsername() $recipe.GetNugetPassword()
    foreach ($component in $recipe.components) {
        if (CheckOptional) { continue }
        if ($component.IsDotNetTest()) {
            PrintAction "Testing component $($component.name)..."
            $path = Join-Path $PSScriptRoot $component.path
            PrintAction "Pushing location $($path)"
            Push-Location $path
            $vsProjectFile = "$($component.name).csproj"
            PrintAction "Testing $($vsProjectFile)..."
            dotnet test $vsProjectFile
            Pop-Location
        }
        elseif ($component.IsDotNetTestApp()) {
            PrintAction "Testing $($component.name) in Docker..."
            CheckDockerStart
            $imageName = $($component.name).ToLower().Trim()
            docker-compose --log-level ERROR run $imageName
        }
    }
    PathNugetFile -logout
    PrintStep "Completed the TEST step"
}

Function CodeQuality ([Recipe] $recipe) {
    PrintStep "Started the CODEQUALITY step"
    $whoami = whoami
    $env:PATH += ":/home/$whoami/.dotnet/tools"
    foreach ($component in $recipe.components) {
        $version = $recipe.GetVersion()
        $path = Join-Path $PSScriptRoot $component.path
        if ($component.CodeQualityCheck()) {
            if (CheckOptional) { continue }
            PrintAction "Pushing location $($path)"
            Push-Location $path
            $vsProjectFile = "$($component.name).csproj"
            $coverageFile = Join-Path $path "coverage.opencover.xml"
            PrintAction "Starting Code Coverage..."
            dotnet sonarscanner begin /k:"$vsProjectFile" /n:"$vsProjectFile" /v:"$version" /d:sonar.cs.opencover.reportsPaths=$coverageFile /d:sonar.host.url="$env:SONAR_HOST_URL" /d:sonar.login="$env:SONAR_LOGIN_TOKEN" /d:sonar.exclusions="**/AssemblyInfo.cs,**/lib/**"
            dotnet test $vsProjectFile /p:CollectCoverage=true /p:CoverletOutputFormat="opencover" 
            dotnet sonarscanner end /d:sonar.login="$env:SONAR_LOGIN_TOKEN"
            PrintAction "Code Coverage completed."
            Pop-Location
        }
    }
    PrintStep "Completed the CODEQUALITY step"
}

Function Pack([Recipe] $recipe) {
    PrintStep "Started the PACK step"
    foreach ($component in $recipe.components) {
        if (CheckOptional) { continue }
        PrintAction "Packing component $($component.name)"
        $version = $recipe.GetVersion()
        $path = Join-Path $PSScriptRoot $component.path
        if ($component.IsDotNetPackage()) {
            PrintAction "Pushing location $($path)"
            Push-Location $path
            PrintAction "Packing $($component.name)..."
            $distPath = Join-Path $PSScriptRoot $component.packageDist
            dotnet pack /p:Version="$version,PackageVersion=$version" --no-dependencies --force -c Release --output $distPath
            Pop-Location
        }
        elseif ($component.IsDotNetMigrationDbUp() -or $component.IsAspNetApp()) {
            $source = Join-Path $component.path $component.sourcePath
            $destination = Join-Path $component.packageDist ($component.name + "." + $version + ".zip")
            if (-not (Test-path $component.packageDist)) { new-item -Name $component.packageDist -ItemType directory }
            if (Test-path $destination) { Remove-item $destination -Force -ErrorAction SilentlyContinue }
            Compress-Archive -Path $source -CompressionLevel Optimal -DestinationPath $destination
        }
    }
    PrintStep "Completed the PACK step"
}

Function Publish([Recipe] $recipe) {
    PrintStep "Started the PUBLISH step"
    foreach ($component in $recipe.components) {
        if (CheckOptional) { continue }
        PrintAction "Publishing $($component.type) component $($component.name)"
        $version = $recipe.GetVersion()
        if ($component.IsDotNetPackage()) {
            $path = Join-Path $PSScriptRoot $component.packageDist
            Push-Location $path
            $package = "$($component.package).$($version).nupkg"
            $source = "$($recipe.GetNugetFeed())/$($component.packagePath)"
            Write-Host "Publishing package $($package)"
            dotnet nuget push $package -k $recipe.GetNugetFeedApiKey() -s $source
            Pop-Location
        }
        elseif ($component.IsDotNetApp() -or $component.IsDotNetTestApp()) {
            SetupDocker
            $imageName = $($component.name).ToLower().Trim()
            $imageTag = "$($imageName):$($version)"
            $imageFinal = "$Env:JFROG_DOCKER_LOCAL/$imageTag"
            docker tag $imageTag $imageFinal
            docker push $imageFinal
            docker rmi $imageFinal $imageTag
            SetupDocker -logout
        }
        elseif ($component.IsDotNetMigrationDbUp() -or $component.IsAspNetApp()) {
            $file = Join-Path $component.packageDist ($component.name + "." + $version + ".zip")
            $fileName = $component.name + "." + $version + ".zip"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -TimeoutSec 9200 -UseBasicParsing -Uri (New-Object System.Uri ($Env:BAKE_ARTIFACTS_REPO_URI + $component.name + "/" + $fileName)) -InFile $file -Method Put -Credential (New-Object System.Management.Automation.PSCredential ($Env:BAKE_NUGET_USERNAME), (ConvertTo-SecureString ($Env:BAKE_NUGET_PASSWORD) -AsPlainText -Force))
        }
    }
    PrintStep "Completed the PUBLISH step"
}

Function SetupBox([Recipe] $recipe) {
    PrintStep "Started the SETUPBOX step"
    foreach ($component in $recipe.components) {
        if (($component.IsDotNetApp()) -or ($component.IsDotNetTest())) {
            PrintAction "SETUPBOX for the component $($component.name)"
            $path = Join-Path $PSScriptRoot $component.path
            PrintAction "Pushing location $($path)"
            Push-Location $path
            dotnet user-secrets clear
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
                    }
                }
            }
            Pop-Location
        }
    }
    PrintStep "Completed the SETUPBOX step"
}

Function docker.start ([Recipe] $recipe) {
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
    PrintStep "Completed the DOCKER.START step"
}

Function docker.stop () {
    PrintStep "Started the DOCKER.STOP step"
    Write-Host "I'm stopping all project's containers..." -ForegroundColor Yellow
    if (Test-Path env:IS_CI) { docker-compose -f docker-compose.yml --log-level ERROR down } else { docker-compose down }
    if (docker ps -aq) { docker rm $(docker ps -aq) -f }
    PrintStep "Completed the DOCKER.STOP step"
}

Function docker.clean () {
    PrintStep "Started the DOCKER.CLEAN step"
    # $ErrorActionPreference = "SilentlyContinue"
    # foreach ($component in $recipe.components) {
    #     $imageName = $($component.name).ToLower().Trim()
    #     docker rmi $imageName -f
    # }
    # $ErrorActionPreference = "Stop"
    docker system prune -f
    docker container prune -f
    docker volume prune -f
    docker network prune -f
    PrintStep "Completed the DOCKER.CLEAN step"
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
if ($step -eq "CI" -or $step -eq "RC" -or $step -eq "CODEQUALITY") {
    CodeQuality($recipe)
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