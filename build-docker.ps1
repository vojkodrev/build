param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    
    [string]$PreviousRoot,

    [switch]$SwitchEnv = $false,
    
    [switch]$CleanPublish = $false,

    [switch]$Publish = $false,
    [switch]$ValidatePublish = $false,

    [switch]$DontValidateImplementationMasterBranch = $false,
    [switch]$DontValidateServerVersion = $false,
    
    [switch]$GitRebase = $false,

    [switch]$InstallNodeModules = $false
)

function Run-Command {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command,
  
        [string]$Description
    )
  
    if ($Description) {
        Write-Output $Description
    }
    
    $currentLocation = Get-Location
    Write-Output "$currentLocation> $Command"

    Invoke-Expression $Command
}

function Run-Command-Stop-On-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command,
  
        [string]$Description
    )
  
    Run-Command -Description $Description -Command $Command
  
    if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
        Write-Error "FAILED ($LASTEXITCODE)!" -ErrorAction Stop
    }
}

function Validate-Implementation-Master-Branch {
    param(
        [parameter(Mandatory = $true)]
        [string]$ImplementationDir,
  
        [parameter(Mandatory = $true)]
        [string]$MasterBranchName,

        [switch]$GitRebase = $false
    )
  
    $startingLocation = Get-Location
  
    try {
        Set-Location $ImplementationDir
    
        if ($GitRebase) {
            Run-Command-Stop-On-Error "git fetch"
        }
        else {
            git fetch | Out-Null
            if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
                Write-Error "Git fetch failed ($LASTEXITCODE)" -ErrorAction Stop
            }
        }
  
        if ($GitRebase) {
            Run-Command-Stop-On-Error "git rebase --autostash $MasterBranchName"
        }
    
        if (git branch --show-current) {
            git merge-base --is-ancestor $MasterBranchName $(git branch --show-current)
            if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
                Write-Error "There are new changes in $MasterBranchName. It should be merged into current branch." -ErrorAction Stop
            }
        }
    }
    finally {
        Set-Location $startingLocation
    }
}

function Get-AdInsure-Server-Version {
    param(
    )
    
    $serverVersion = (Get-Item "$([System.IO.Path]::GetTempPath())/Adacta.AdInsure.Core.API.dll").VersionInfo.FileVersion
    if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
        Write-Error "FAILED ($LASTEXITCODE)! Unable to get server version from dll" -ErrorAction Stop
    }

    $fixed = $serverVersion -replace '\.0$', ''

    return $fixed
}

function Validate-Server-Version {
    param(
        [parameter(Mandatory = $true)]
        [string]$ImplementationDir
    )
  
    $startingLocation = Get-Location
  
    try {
        Set-Location $ImplementationDir
    
        if (!(Test-Path "PLATFORM_VERSION")) {
            return
        }

        if ($ImplementationDir -match "signal") {
            $serverName = "signal-server-1"
        }
        elseif ($ImplementationDir -match "dva") {
            $serverName = "dva-server-1"
        }

        docker cp ${serverName}:/app/Adacta.AdInsure.Core.API.dll "$([System.IO.Path]::GetTempPath())" | Out-Null
        if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
            Write-Error "FAILED ($LASTEXITCODE)! Unable to copy Adinusre dll from docker container to temp" -ErrorAction Stop
        }

        $serverVersion = Get-AdInsure-Server-Version
        
        $implPlatformVersion = cat PLATFORM_VERSION

        if ($implPlatformVersion -ne $serverVersion) {
            Write-Error "Server version missmatch server: $serverVersion, platform: $implPlatformVersion" -ErrorAction Stop
        }
    }
    finally {
        Set-Location $startingLocation
    }
}

function Get-Node-Info {
    param(
    )
  
    return Get-ChildItem `
        HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, `
        HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall `
    | Get-ItemProperty | Where-Object { $_.DisplayName -match 'node' }
}

$instructions = @{
    ValidateImplementationMasterBranch = $false
    StopPreviousDocker                 = $false
    GitRebase                          = $false
    Clean                              = $false
    UninstallNode                      = $false
    RemoveDocker                       = $false
    InitDocker                         = $false
    ValidateServerVersion              = $false
    StartDocker                        = $false
    InstallESAnalysisIcuPlugin         = $false
    InstallNode                        = $false
    InstallNodeModules                 = $false
    ExecutePrePublishScripts           = $false
    ValidateWorkspace                  = $false
    PublishWorkspace                   = $false
    ExecutePostPublishScripts          = $false
    RestartServer                      = $false
    InstallStudio                      = $false
    RegisterScheduler                  = $false
}

if ($GitRebase) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.GitRebase = $true
    $instructions.ValidateServerVersion = $true
}

if ($CleanPublish) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopPreviousDocker = $true
    $instructions.Clean = $true
    $instructions.UninstallNode = $true
    $instructions.RemoveDocker = $true
    $instructions.InitDocker = $true
    $instructions.ValidateServerVersion = $true
    $instructions.InstallESAnalysisIcuPlugin = $true
    $instructions.InstallNode = $true
    $instructions.InstallNodeModules = $true
    $instructions.ExecutePrePublishScripts = $true
    $instructions.ValidateWorkspace = $true
    $instructions.PublishWorkspace = $true
    $instructions.ExecutePostPublishScripts = $true
    $instructions.RestartServer = $true
    $instructions.InstallStudio = $true
    # $instructions.RegisterScheduler = $true
}

if ($SwitchEnv) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopPreviousDocker = $true
    $instructions.UninstallNode = $true
    $instructions.InstallNode = $true
    $instructions.ValidateServerVersion = $true
    $instructions.StartDocker = $true
    $instructions.InstallStudio = $true
}

if ($ValidatePublish) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateServerVersion = $true
    $instructions.ValidateWorkspace = $true
    $instructions.PublishWorkspace = $true
    $instructions.RestartServer = $true
}

if ($Publish) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateServerVersion = $true
    $instructions.PublishWorkspace = $true
    $instructions.RestartServer = $true
}

if ($InstallNodeModules) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateServerVersion = $true
    $instructions.InstallNodeModules = $true
}

if ($DontValidateImplementationMasterBranch) {
    $instructions.ValidateImplementationMasterBranch = $false
}

if ($DontValidateServerVersion) {
    $instructions.ValidateServerVersion = $false
}

if ($instructions.ValidateImplementationMasterBranch) {
    Validate-Implementation-Master-Branch `
        -ImplementationDir $Root `
        -MasterBranchName "origin/master" `
        -GitRebase:$instructions.GitRebase
}

if ($PreviousRoot) {
    $startingLocation = Get-Location
    try {
        Set-Location $PreviousRoot
        if ($instructions.StopPreviousDocker) {
            Run-Command-Stop-On-Error "docker-compose stop"
        }
    }
    finally {
        Set-Location $startingLocation
    }
}

$startingLocation = Get-Location
try {
    Set-Location $Root

    if ($instructions.Clean) {
        Run-Command-Stop-On-Error "git stash --include-untracked" | Tee-Object -Variable gitStashOutput
        
        Run-Command-Stop-On-Error "echo no | git clean -fdx -e node_modules"
        Run-Command-Stop-On-Error "git reset --hard"
        
        if (!($gitStashOutput -match "No local changes to save")) {
            Run-Command-Stop-On-Error "git stash pop"
        }
        
        $printoutAssetsDir = [io.path]::combine($Root, "printout-assets")
        if (!(Test-Path $printoutAssetsDir)) {
            Run-Command-Stop-On-Error "New-Item -Path $printoutAssetsDir -ItemType Directory"
        }
    }

    if ($instructions.UninstallNode) {
        $node = Get-Node-Info
        $uninstall = $true

        if (($Root -match "vh") -and ($node.DisplayVersion -eq "12.22.12")) {
            $uninstall = $false
        }
        elseif ($node.DisplayVersion -eq "18.20.2") {
            $uninstall = $false
        }

        if ($node -and $uninstall) {
            Run-Command "msiexec /x `"C:\Users\VojkoD.ADFT\Downloads\node-v18.20.2-x64.msi`" /quiet /log `"C:\Users\VojkoD.ADFT\Downloads\node-uninstall-v18.20.2-x64.log`" | Out-Default"            
            Run-Command "msiexec /x `"C:\Users\VojkoD.ADFT\Downloads\node-v12.22.12-x64.msi`" /quiet /log `"C:\Users\VojkoD.ADFT\Downloads\node-uninstall-v12.22.12-x64.log`" | Out-Default"
        }
    }

    if ($instructions.RemoveDocker) {
        if ($Root -match "vh") {
            Run-Command-Stop-On-Error "docker-compose -p vh down -v"
        }
        else {
            Run-Command-Stop-On-Error "docker-compose down -v"
        }
    }

    if ($instructions.InitDocker) {
        Run-Command-Stop-On-Error "docker-compose pull"

        if ($Root -match "vh") {
            Run-Command-Stop-On-Error "docker-compose -p vh up -d"
        }
        else {
            Run-Command-Stop-On-Error "docker-compose up -d"
        }
    }

    if ($instructions.ValidateServerVersion) {
        Validate-Server-Version -ImplementationDir $Root
    }

    if ($instructions.StartDocker) {
        Run-Command-Stop-On-Error "docker-compose start"
    }

    if (($instructions.InstallESAnalysisIcuPlugin) -and ($Root -match "signal")) {
        Run-Command-Stop-On-Error "docker exec -it signal-es-1 bin/elasticsearch-plugin install analysis-icu"
        Run-Command-Stop-On-Error "docker restart signal-es-1"
    }
    
    if ($instructions.InstallNode) {
        $node = Get-Node-Info

        if (!$node) {
            if ($Root -match "vh") {
                Run-Command-Stop-On-Error "msiexec /i `"C:\Users\VojkoD.ADFT\Downloads\node-v12.22.12-x64.msi`" /quiet /log `"C:\Users\VojkoD.ADFT\Downloads\node-install-v12.22.12-x64.log`" NATIVETOOLSCHECKBOX=1 | Out-Default"
            }
            else {
                Run-Command-Stop-On-Error "msiexec /i `"C:\Users\VojkoD.ADFT\Downloads\node-v18.20.2-x64.msi`" /quiet /log `"C:\Users\VojkoD.ADFT\Downloads\node-install-v18.20.2-x64.log`" NATIVETOOLSCHECKBOX=1 | Out-Default"
            }
        }
    }

    if ($instructions.InstallNodeModules) {
        do {
            $runAgain = $false
            $command = ""

            if ($Root -match "dva") {
                $command = "yarn install-modules"
            }
            else {
                $command = "yarn install"
            }

            Run-Command $command 2>&1 | Tee-Object -Variable commandOutput
            
            if (($commandOutput -match "401 Unauthorized") -or ($commandOutput -match "error couldn't find package") -or ($commandOutput -match "503 Service Unavailable")) {
                $runAgain = $true
            }
            elseif (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
                Write-Error "FAILED!" -ErrorAction Stop
            }
        } while ($runAgain)
    }

    if ($instructions.ExecutePrePublishScripts) {
        if ($Root -match "signal") {
            Run-Command-Stop-On-Error ".\build.ps1 -ExecutePrePublishScripts"
        }
    }

    $publishEnv = $null
    if ($Root -match "dva") {
        $publishEnv = "docker"
    }
    elseif ($Root -match "vh") {
        $publishEnv = "demo-vh"
    }
    else {
        $publishEnv = "local"
    }

    if ($instructions.ValidateWorkspace) {
        Run-Command-Stop-On-Error "yarn run validate-workspace -e $publishEnv"
    }
    
    if ($instructions.PublishWorkspace) {
        Run-Command-Stop-On-Error "yarn run publish-workspace -e $publishEnv"
    }

    if ($instructions.ExecutePostPublishScripts) {
        if ($Root -match "signal") {
            Run-Command-Stop-On-Error ".\build.ps1 -ExecutePostPublishScripts"
        }
    }
    
    if ($instructions.RestartServer) {
        $serverName = $null
        if ($Root -match "signal") {
            $serverName = "signal-server-1"
        }
        elseif ($Root -match "dva") {
            $serverName = "dva-server-1"
        }
        elseif ($Root -match "vh") {
            $serverName = "vh-server-1"
        }
        else {
            Write-Error "Don't know how to restart server :(" -ErrorAction Stop
        }

        Run-Command-Stop-On-Error "docker restart $serverName"
    }

    if ($instructions.InstallStudio) {
        Run-Command-Stop-On-Error "ops download:studio -v $(Get-AdInsure-Server-Version) -i"
    }

    if ($instructions.RegisterScheduler) {
        if ($Root -match "signal") {
            $schedulerStartingLocation = Get-Location
            try {
                Set-Location .\.build\scheduler\
                Run-Command-Stop-On-Error ".\import.ps1"
            }
            finally {
                Set-Location $schedulerStartingLocation
            }
        }
        elseif ($Root -match "dva") {
            Run-Command-Stop-On-Error "yarn run register-scheduler-jobs"
        }
    }
}
finally {
    Set-Location $startingLocation
}