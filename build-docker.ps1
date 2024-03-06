param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    
    [switch]$CleanPublish = $false,

    [switch]$Publish = $false,
    [switch]$ValidatePublish = $false,

    [switch]$DontValidateImplementationMasterBranch = $false,
    
    [switch]$GitRebase = $false
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
    
        git fetch
  
        if ($GitRebase) {
            Run-Command-Stop-On-Error "git rebase --autostash $MasterBranchName"
        }
    
        if (git branch --show-current) {
            git merge-base --is-ancestor $MasterBranchName $(git branch --show-current)
            if ($LASTEXITCODE -gt 0) {
                Write-Error "There are new changes in $MasterBranchName. It should be merged into current branch." -ErrorAction Stop
            }
        }
    }
    finally {
        Set-Location $startingLocation
    }
}

$instructions = @{
    ValidateImplementationMasterBranch = $false
    GitRebase                          = $false
    Clean                              = $false
    RemoveDocker                       = $false
    InitDocker                         = $false
    InstallNodeModules                 = $false
    ValidateWorkspace                  = $false
    PublishWorkspace                   = $false
    RestartServer                      = $false
}

if ($CleanPublish) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.Clean = $true
    $instructions.RemoveDocker = $true
    $instructions.InitDocker = $true
    $instructions.InstallNodeModules = $true
    $instructions.ValidateWorkspace = $true
    $instructions.PublishWorkspace = $true
    $instructions.RestartServer = $true
}

if ($Publish) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.PublishWorkspace = $true
    $instructions.RestartServer = $true
}

if ($ValidatePublish) {
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateWorkspace = $true
    $instructions.PublishWorkspace = $true
    $instructions.RestartServer = $true
}

if ($DontValidateImplementationMasterBranch) {
    $instructions.ValidateImplementationMasterBranch = $false
}

if ($GitRebase) {
    $instructions.GitRebase = $true
}

$startingLocation = Get-Location
try {
    Set-Location $Root

    if ($instructions.ValidateImplementationMasterBranch) {
        Validate-Implementation-Master-Branch `
            -ImplementationDir $Root `
            -MasterBranchName "origin/master" `
            -GitRebase:$instructions.GitRebase
    }

    if ($instructions.RemoveDocker) {
        Run-Command-Stop-On-Error "docker-compose down -v"
    }

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
    
    if ($instructions.InitDocker) {
        Run-Command-Stop-On-Error "docker-compose up -d"
    }

    if ($instructions.InstallNodeModules) {
        Run-Command-Stop-On-Error "yarn install-modules"
    }

    if ($instructions.ValidateWorkspace) {
        Run-Command-Stop-On-Error "yarn run validate-workspace -e docker"
    }
    
    if ($instructions.PublishWorkspace) {
        Run-Command-Stop-On-Error "yarn run publish-workspace -e docker"
    }
    
    if ($instructions.RestartServer) {
        Run-Command-Stop-On-Error "docker restart dva-server-1"
    }
}
finally {
    Set-Location $startingLocation
}