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

function Validate-Server-Version {
    param(
        [parameter(Mandatory = $true)]
        [string]$ImplementationDir
    )
  
    $startingLocation = Get-Location
  
    try {
        Set-Location $ImplementationDir
    
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

        $serverVersion = (Get-Item "$([System.IO.Path]::GetTempPath())/Adacta.AdInsure.Core.API.dll").VersionInfo.FileVersion
        if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
            Write-Error "FAILED ($LASTEXITCODE)! Unable to get server version from dll" -ErrorAction Stop
        }
        
        $implPlatformVersion = "$(cat PLATFORM_VERSION).0"

        if ($implPlatformVersion -ne $serverVersion) {
            Write-Error "Server version missmatch server: $serverVersion, platform: $implPlatformVersion" -ErrorAction Stop
        }
    }
    finally {
        Set-Location $startingLocation
    }
}

$instructions = @{
    ValidateImplementationMasterBranch = $false
    StopPreviousDocker                 = $false
    GitRebase                          = $false
    Clean                              = $false
    RemoveDocker                       = $false
    InitDocker                         = $false
    ValidateServerVersion              = $false
    StartDocker                        = $false
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
    $instructions.RemoveDocker = $true
    $instructions.InitDocker = $true
    $instructions.ValidateServerVersion = $true
    $instructions.InstallNodeModules = $true
    $instructions.ExecutePrePublishScripts = $true
    $instructions.ValidateWorkspace = $true
    $instructions.PublishWorkspace = $true
    $instructions.ExecutePostPublishScripts = $true
    $instructions.RestartServer = $true
    $instructions.InstallStudio = $true
    $instructions.RegisterScheduler = $true
}

if ($SwitchEnv) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopPreviousDocker = $true
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
        if (!(Test-Path -Path $printoutAssetsDir)) {
            Run-Command-Stop-On-Error "New-Item -Path $printoutAssetsDir -ItemType Directory"
        }
    }

    if ($instructions.RemoveDocker) {
        Run-Command-Stop-On-Error "docker-compose down -v"
    }

    if ($instructions.InitDocker) {
        Run-Command-Stop-On-Error "docker-compose pull"
        Run-Command-Stop-On-Error "docker-compose up -d"
    }

    if ($instructions.ValidateServerVersion) {
        Validate-Server-Version `
            -ImplementationDir $Root
    }

    if ($instructions.StartDocker) {
        Run-Command-Stop-On-Error "docker-compose start"
    }

    if ($instructions.InstallNodeModules) {
        do {
            $runAgain = $false
            $command = ""

            if ($Root -match "signal") {
                $command = "yarn install"
            }
            elseif ($Root -match "dva") {
                $command = "yarn install-modules"
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
    if ($Root -match "signal") {
        $publishEnv = "local"
    }
    elseif ($Root -match "dva") {
        $publishEnv = "docker"
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

        Run-Command-Stop-On-Error "docker restart $serverName"
    }

    if ($instructions.InstallStudio) {
        Run-Command-Stop-On-Error "ops download:studio -v $(cat PLATFORM_VERSION) -i"
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