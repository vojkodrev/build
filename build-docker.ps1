param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    
    [string]$PreviousRoot,

    [switch]$SwitchEnv = $false,
    
    [switch]$CleanPublish = $false,
    [switch]$CleanNodeModules = $false,

    [switch]$Publish = $false,
    [switch]$ValidatePublish = $false,

    [switch]$DontValidateImplementationMasterBranch = $false,
    [switch]$DontValidateServerVersion = $false,
    [switch]$DontRestartServer = $false,
    [switch]$DontRemoveVolumes = $false,
    
    [switch]$GitRebase = $false,

    [switch]$InstallNodeModules = $false,

    [switch]$InstallStudio = $false,

    [switch]$ImportData = $false,

    [switch]$RestartDocker = $false
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
        [parameter(Mandatory = $true)]
        [string]$ServerName
    )

    # if ($ImplementationDir -match "signal") {
    #     $serverName = "signal-server-1"
    # }
    # elseif ($ImplementationDir -match "dva") {
    #     $serverName = "dva-server-1"
    # }
    # elseif ($ImplementationDir -match "VHDemoCommercial") {
    #     $serverName = "commercial-server-1"
    # }

    docker cp ${ServerName}:/app/Adacta.AdInsure.Core.API.dll "$([System.IO.Path]::GetTempPath())" | Out-Null
    if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
        Write-Error "FAILED ($LASTEXITCODE)! Unable to copy Adinusre dll from docker container to temp" -ErrorAction Stop
    }
    
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
        [string]$ImplementationDir,
        
        [parameter(Mandatory = $true)]
        [string]$ServerName
    )
  
    $startingLocation = Get-Location
  
    try {
        Set-Location $ImplementationDir
    
        if (!(Test-Path "PLATFORM_VERSION")) {
            return
        }

        $serverVersion = Get-AdInsure-Server-Version $ServerName
        
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
    CleanNodeModules                   = $false
    UninstallNode                      = $false
    StopDocker                         = $false
    RemoveDocker                       = $false
    InitDocker                         = $false
    ValidateServerVersion              = $false
    StartDocker                        = $false
    ValidateCorrectDocker              = $false
    # InstallESAnalysisIcuPlugin         = $false
    InstallNode                        = $false
    InstallNodeModules                 = $false
    ExecutePrePublishScripts           = $false
    ValidateWorkspace                  = $false
    PublishWorkspace                   = $false
    ExecutePostPublishScripts          = $false
    RestartServer                      = $false
    ImportData                         = $false
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
    $instructions.ValidateCorrectDocker = $true
    # $instructions.InstallESAnalysisIcuPlugin = $true
    $instructions.InstallNode = $true
    $instructions.InstallNodeModules = $true
    $instructions.ExecutePrePublishScripts = $true
    $instructions.ValidateWorkspace = $true
    $instructions.PublishWorkspace = $true
    $instructions.ExecutePostPublishScripts = $true
    $instructions.RestartServer = $true
    $instructions.ImportData = $true
    $instructions.InstallStudio = $true
    # $instructions.RegisterScheduler = $true
}

if ($CleanNodeModules) {
    $instructions.CleanNodeModules = $true;
}

if ($RestartDocker) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateServerVersion = $true
    $instructions.ValidateCorrectDocker = $true
    $instructions.StopDocker = $true
    $instructions.StartDocker = $true
}

if ($SwitchEnv) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopPreviousDocker = $true
    $instructions.UninstallNode = $true
    $instructions.InstallNode = $true
    $instructions.ValidateServerVersion = $true
    $instructions.StartDocker = $true
    $instructions.ValidateCorrectDocker = $true
    $instructions.InstallStudio = $true
}

if ($ValidatePublish) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateServerVersion = $true
    $instructions.ValidateWorkspace = $true
    $instructions.ValidateCorrectDocker = $true
    $instructions.PublishWorkspace = $true
    $instructions.RestartServer = $true
}

if ($Publish) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateServerVersion = $true
    $instructions.ValidateCorrectDocker = $true
    $instructions.PublishWorkspace = $true
    $instructions.RestartServer = $true
}

if ($InstallNodeModules) {
    $instructions.InstallNodeModules = $true
}

if ($InstallStudio) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateServerVersion = $true
    $instructions.ValidateCorrectDocker = $true
    $instructions.InstallStudio = $true
}

if ($ImportData) {
    $instructions.ImportData = $true
}

if ($DontValidateImplementationMasterBranch) {
    $instructions.ValidateImplementationMasterBranch = $false
}

if ($DontValidateServerVersion) {
    $instructions.ValidateServerVersion = $false
}

if ($DontRestartServer) {
    $instructions.RestartServer = $false
}

if ($instructions.ValidateImplementationMasterBranch) {
    Validate-Implementation-Master-Branch `
        -ImplementationDir $Root `
        -MasterBranchName "origin/master" `
        -GitRebase:$instructions.GitRebase
}

$dockerComposeFile = $null
if (($Root -match "Triglav") -and !($Root -match "TriglavCore")) {
    $dockerComposeFile = "docker-compose-si.yml"
}
else {
    $dockerComposeFile = "docker-compose.yml"
}

$dockerComposeProject = $null
if ($Root -match "TriglavCore") {
    $dockerComposeProject = "-p triglav_core"
}
else {
    $dockerComposeProject = ""
}

$dockerComposeFilePrevious = $null
if (($PreviousRoot -match "Triglav") -and !($PreviousRoot -match "TriglavCore")) {
    $dockerComposeFilePrevious = "docker-compose-si.yml"
}
else {
    $dockerComposeFilePrevious = "docker-compose.yml"
}

$dockerComposeProjectPrevious = $null
if ($PreviousRoot -match "TriglavCore") {
    $dockerComposeProjectPrevious = "-p triglav_core"
}
else {
    $dockerComposeProjectPrevious = ""
}

if ($PreviousRoot) {
    $startingLocation = Get-Location
    try {
        Set-Location $PreviousRoot
        if ($instructions.StopPreviousDocker) {
            Run-Command-Stop-On-Error "docker-compose -f $dockerComposeFilePrevious $dockerComposeProjectPrevious stop"
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
        
        if ($instructions.CleanNodeModules) {
            Run-Command-Stop-On-Error "echo no | git clean -fdx"
        }
        else {
            Run-Command-Stop-On-Error "echo no | git clean -fdx -e node_modules"
        }
        
        Run-Command-Stop-On-Error "git reset --hard"
        
        if (!($gitStashOutput -match "No local changes to save")) {
            Run-Command-Stop-On-Error "git stash pop"
        }
        
        $printoutAssetsDir = [io.path]::combine($Root, "printout-assets")
        if (!(Test-Path $printoutAssetsDir)) {
            Run-Command-Stop-On-Error "New-Item -Path $printoutAssetsDir -ItemType Directory"
        }

        Run-Command-Stop-On-Error "Remove-Item -Recurse -Force web-test-framework"
    }

    # if ($instructions.UninstallNode) {
    #     $node = Get-Node-Info
    #     $uninstall = $true

    #     if ($Root -match "TriglavCore") {
    #         if ($node.DisplayVersion -eq "16.20.2") {
    #             $uninstall = $false;
    #         }
    #     }
    #     else {
    #         if ($node.DisplayVersion -eq "18.20.2") {
    #             $uninstall = $false
    #         }
    #     }

    #     # if (($Root -match "TriglavCore") -and ($node.DisplayVersion -eq "16.20.2")) {
    #     #     $uninstall = $false
    #     # }
    #     # elseif ($node.DisplayVersion -eq "18.20.2") {
    #     #     $uninstall = $false
    #     # }

    #     if ($node -and $uninstall) {
    #         Run-Command "msiexec /x `"C:\Users\VojkoD.ADFT\Downloads\node-v18.20.2-x64.msi`" /quiet /log `"C:\Users\VojkoD.ADFT\Downloads\node-uninstall-v18.20.2-x64.log`" | Out-Default"            
    #         Run-Command "msiexec /x `"C:\Users\VojkoD.ADFT\Downloads\node-v16.20.2-x64.msi`" /quiet /log `"C:\Users\VojkoD.ADFT\Downloads\node-uninstall-v16.20.2-x64.log`" | Out-Default"
    #     }
    # }

    $serverName = $null
    if ($Root -match "signal") {
        $serverName = "signal-server-1"
    }
    elseif ($Root -match "dva") {
        $serverName = "dva-server-1"
    }
    elseif ($Root -match "VHDemoCommercial") {
        $serverName = "commercial-server-1"
    }
    elseif ($Root -match "TriglavCore") {
        $serverName = "triglav_core-server-1"
    }
    elseif ($Root -match "Triglav") {
        $serverName = "triglav-server-1"
    }
    elseif ($Root -match "CID") {
        $serverName = "cid-server-1"
    }
    else {
        Write-Error "Unknown server name" -ErrorAction Stop
    }

    if ($instructions.StopDocker) {
        Run-Command-Stop-On-Error "docker-compose -f $dockerComposeFile $dockerComposeProject stop"
    }

    if ($instructions.RemoveDocker) {
        if ($DontRemoveVolumes) {
            Run-Command-Stop-On-Error "docker-compose -f $dockerComposeFile $dockerComposeProject down"
        }
        else {
            Run-Command-Stop-On-Error "docker-compose -f $dockerComposeFile $dockerComposeProject down -v"
        }
    }

    if ($instructions.InitDocker) {
        Run-Command-Stop-On-Error "docker-compose -f $dockerComposeFile $dockerComposeProject pull"
        Run-Command-Stop-On-Error "docker-compose -f $dockerComposeFile $dockerComposeProject up -d"
    }

    if ($instructions.StartDocker) {
        Run-Command-Stop-On-Error "docker-compose -f $dockerComposeFile $dockerComposeProject start"
    }

    if ($instructions.ValidateServerVersion) {
        Validate-Server-Version -ImplementationDir $Root -ServerName $serverName
    }

    if ($instructions.ValidateCorrectDocker) {
        if (!(docker ps | Select-String $serverName)) {
            Write-Error "Currently Docker containers for different environment are running. $serverName expected" -ErrorAction Stop
        }
    }

    # if (($instructions.InstallESAnalysisIcuPlugin) -and ($Root -match "signal")) {
    #     Run-Command-Stop-On-Error "docker exec -it signal-es-1 bin/elasticsearch-plugin install analysis-icu"
    #     Run-Command-Stop-On-Error "docker restart signal-es-1"
    # }
    
    # if ($instructions.InstallNode) {
    #     $node = Get-Node-Info

    #     if (!$node) {
    #         if ($Root -match "TriglavCore") {
    #             Run-Command-Stop-On-Error "msiexec /i `"C:\Users\VojkoD.ADFT\Downloads\node-v16.20.2-x64.msi`" /quiet /log `"C:\Users\VojkoD.ADFT\Downloads\node-install-v16.20.2-x64.log`" NATIVETOOLSCHECKBOX=1 | Out-Default"
    #         }
    #         else {
    #             Run-Command-Stop-On-Error "msiexec /i `"C:\Users\VojkoD.ADFT\Downloads\node-v18.20.2-x64.msi`" /quiet /log `"C:\Users\VojkoD.ADFT\Downloads\node-install-v18.20.2-x64.log`" NATIVETOOLSCHECKBOX=1 | Out-Default"
    #         }
    #     }
    # }

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
            
            if (($commandOutput -match "401 Unauthorized") -or `
                ($commandOutput -match "503 Service Unavailable") -or `
                ($commandOutput -match "500 Internal Server Error") -or `
                ($commandOutput -match "Couldn't find package") `
            ) {
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
    elseif (($Root -match "Triglav") -and !($Root -match "TriglavCore")) {
        $publishEnv = "local.si"
    }
    elseif ($Root -match "CID") {
        $publishEnv = "si"
    }
    else {
        $publishEnv = "local"
    }

    if ($instructions.ValidateWorkspace) {
        Run-Command-Stop-On-Error "yarn run validate-workspace -e $publishEnv"
    }
    
    if ($instructions.PublishWorkspace) {

        Run-Command-Stop-On-Error "yarn run publish-workspace -e $publishEnv" 2>&1 | Tee-Object -Variable commandOutput

        $runAgain = $false
        do {
            $runAgain = $false
            
            # if (($commandOutput -match "was deadlocked on lock resources with another process") -or `
            #     ($commandOutput -match "BusinessException.*?skupina s kodo OTP ne obstaja")
            if ($commandOutput -match "Token exchange failed with the following error: TimeoutError: Timeout awaiting 'request'") {
                $runAgain = $true
            }
            elseif ($LASTEXITCODE) {
                Write-Error "FAILED ($LASTEXITCODE)!" -ErrorAction Stop
            }
        } while ($runAgain)
    }

    if ($instructions.ExecutePostPublishScripts) {
        if ($Root -match "signal") {
            Run-Command-Stop-On-Error ".\build.ps1 -ExecutePostPublishScripts"
        }
    }
    
    if ($instructions.RestartServer) {
        Run-Command-Stop-On-Error "docker restart $serverName"
    }

    if ($instructions.ImportData -and !$DontRemoveVolumes) {
        if (($Root -match "Triglav") -and !($Root -match "TriglavCore")) {
            $count = 1;
            do {
                $runAgain = $false
                Start-Sleep 15s
                Run-Command "yarn run import-gurs -e local.si" 2>&1 | Tee-Object -Variable commandOutput
                
                if (($commandOutput -match "socket hang up") -or `
                    ($commandOutput -match "Request failed with status code") `
                ) {
                    $runAgain = $true
                }
                elseif ($LASTEXITCODE) {
                    Write-Error "FAILED ($LASTEXITCODE)!" -ErrorAction Stop
                }

                if ($count -gt 3) {
                    break;
                }
                $count++
                
            } while ($runAgain)
        }
        
        if (($Root -match "Triglav") -and !($Root -match "TriglavCore")) {
            Run-Command-Stop-On-Error "yarn run import-test-data -e local.si"
        }
        elseif ($Root -match "CID") {
            Run-Command-Stop-On-Error "yarn import-test-data -e si"
        }
    }

    if ($instructions.InstallStudio) {
        Run-Command-Stop-On-Error "ops download:studio -v $(Get-AdInsure-Server-Version $serverName) -i"
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