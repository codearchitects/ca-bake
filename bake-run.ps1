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

Function PrintError([string] $text) {
    Write-Error -Message "$($text)"
}

Function PathNugetFile([string] $file, [string] $feedName, [string] $useraname, [string] $pass) {
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
    $xml.Save("$pwd\" + $file + ".Temp")
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
        $component.package = $item["package"]
        $component.secrets = @()
        foreach ($items2 in $item["secrets"]) 
        {
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
    [string]$package
    [string]$packagePath
    [Secret[]]$secrets

    [boolean] IsDotNetPackage() {
        return $this.type -eq "dotnet-package"
    }

    [boolean] IsDotNetTest() {
        return ($this.type -eq "dotnet-test")
    }

    [boolean] IsDotNetApp() {
        return (($this.type -eq "dotnet-container") -or ($this.type -eq "dotnet-app"))
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
    $error = false
    $errorMessage = ""
    PrintStep "Started the CLEAN step"
    foreach ($component in $recipe.components) {
        PrintAction "Cleaning component $($component.name)"
        $path = Join-Path $PSScriptRoot ("\" + $component.path)
        PrintAction "Pushing location $($path)"
        Push-Location $path
        $vsProjectFile = "$($component.name).csproj"
        PrintAction "Building $($vsProjectFile)..."
        dotnet clean $vsProjectFile
        if ($LastExitCode -ne 0) {
            $error = $true
            $errorMessage = "Failed to clean $($component.name)"
        }
        PrintAction "Popping location"
        Pop-Location     
        if ($error) {
            break
        }
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the CLEAN step"
}

Function Setup([Recipe] $recipe) {
    $error = false
    $errorMessage = ""
    PrintStep "Started the SETUP step"
    PathNugetFile "NuGet.Config" "nugetfeed" $recipe.GetNugetUsername() $recipe.GetNugetPassword()
    PrintStep "Created Nuget.Config temporary file"
    foreach ($component in $recipe.components) {
        PrintAction "Restoring component $($component.name)"
        $path = Join-Path $PSScriptRoot ("\" + $component.path)
        PrintAction "Pushing location $($path)"
        Push-Location $path
        PrintAction "Restoring $($component.name)..."
        $configFile = Join-Path $PSScriptRoot NuGet.Config.Temp
        dotnet restore --force --configfile $configFile
        if ($LastExitCode -ne 0) {
            $error = $true
            $errorMessage = "Failed to restore $($component.name)"
        }
        PrintAction "Popping location"
        Pop-Location
        if ($error) {
            break
        }
    }
    Remove-Item NuGet.Config.Temp
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Delete Nuget.Config temporary file"
    PrintStep "Completed the SETUP step"
}

Function Build([Recipe] $recipe) {
    $error = false
    $errorMessage = ""
    PrintStep "Started the BUILD step"
    foreach ($component in $recipe.components) {
        PrintAction "Building component $($component.name)"
        $path = Join-Path $PSScriptRoot ("\" + $component.path)
        PrintAction "Pushing location $($path)"
        Push-Location $path
        $vsProjectFile = "$($component.name).csproj"
        PrintAction "Building $($vsProjectFile)..."
        dotnet build $vsProjectFile --no-restore
        if ($LastExitCode -ne 0) {
            $error = $true
            $errorMessage = "Failed to build $($component.name)"
        }
        PrintAction "Popping location"
        Pop-Location
        if ($error) {
            break
        }
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the BUILD step"
}

Function Pack([Recipe] $recipe) {
    $error = false
    $errorMessage = ""
    PrintStep "Started the PACK step"
    foreach ($component in $recipe.components) {
        if ($component.IsDotNetPackage()) {
            PrintAction "Packing component $($component.name)"
            $path = Join-Path $PSScriptRoot ("\" + $component.path)
            PrintAction "Pushing location $($path)"
            Push-Location $path
            PrintAction "Packing $($component.name)..."
            $version = $recipe.GetVersion()
            $distPath = Join-Path $PSScriptRoot $component.packageDist
            dotnet pack /p:Version="$version,PackageVersion=$version" --no-dependencies --force -c Release --output $distPath
            if ($LastExitCode -ne 0) {
                $error = $true
                $errorMessage = "Failed to pack $($component.name)"
            }
            PrintAction "Popping location"
            Pop-Location
            if ($error) {
                break
            }
        }
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the PACK step"
}

Function Publish([Recipe] $recipe) {
    $error = false
    $errorMessage = ""
    PrintStep "Started the PUBLISH step"
    foreach ($component in $recipe.components) {
        if ($component.IsDotNetPackage()) {
            PrintAction "Pushing component $($component.name)"
            $path = Join-Path $PSScriptRoot ("\" + $component.packageDist)
            PrintAction "Pushing location $($path)"
            Push-Location $path
            PrintAction "Publishing $($_)..."
            $version = $recipe.GetVersion()
            $package = "$($component.package).$($version).nupkg"
            $source = "$($recipe.GetNugetFeed())/$($component.packagePath)"
            Write-Host "Publishing package $($package)"
            dotnet nuget push $package -k $recipe.GetNugetFeedApiKey() -s $source
            if ($LastExitCode -ne 0) {
                $error = $true
                $errorMessage = "Failed to publish $($component.name)"
            }
            PrintAction "Popping location"
            Pop-Location
            if ($error) {
                break
            }
        }
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the PUBLISH step"
}

Function SetupBox([Recipe] $recipe) {
    $error = false
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
            if (-neq $exit) {
                foreach($secret in $component.secrets) 
                {
                    foreach ($key in $secret.items.Keys) 
                    {
                        $secretKey = $secret.name +':' + $key
                        Write-Host $secretKey -ForegroundColor DarkGreen
                        $input = $secret.items[$key]
                        if (-not ([string]::IsNullOrEmpty($input))) {
                            Write-Host $input
                        } else  {
                            $input = Read-Host
                        }
                        dotnet user-secrets set $secretKey $input
                        if ($LastExitCode -ne 0) {
                            $error = $true
                            $errorMessage = "Failed to setup box $($component.name)"
                        }
                        if ($error) {
                            break
                        }
                    }
                    if ($error) {
                        break
                    }
                }
            }
            PrintAction "Popping location"
            Pop-Location
            if ($error) {
                break
            }
        }
    }
    if ($error) {
        Write-Error "$($errorMessage)"
    }
    PrintStep "Completed the SETUPBOX step"
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
if ($step -eq "CI" -or $step -eq "RC" -or $step -eq "PACK") {
    Pack($recipe)
}
if ($step -eq "RC" -or $step -eq "PUBLISH") {
    Publish($recipe)
}
if ($step -eq "SETUPBOX") {
    SetupBox($recipe)
}