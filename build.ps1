
param(
  [string]$Root = "c:\code\sava",
  [string]$Layer = "hr"
)

$sharedFunctions = {
  function Run-Command {
    param (
      [Parameter(Mandatory=$true)]
      [string]$Command,
  
      [string]$Description
    )
  
    if ($Description) {
      Write-Host $Description
    }
    
    $currentLocation = Get-Location
    Write-Host "$currentLocation> $Command"

    Invoke-Expression $Command
  }
}

. $sharedFunctions


function Run-Command-Stop-On-Error {
  param (
    [Parameter(Mandatory=$true)]
    [string]$Command,

    [string]$Description
  )

  Run-Command -Description $Description -Command $Command

  if ($LASTEXITCODE -ne 0) {
    Write-Error "FAILED!" -ErrorAction Stop
  }
}

function Start-ES-Docker-In-Background {
  
  do {
    Run-Command "docker rm -f es"

    $retry = $false

    $startESJob = Start-Job -InitializationScript $sharedFunctions -ScriptBlock {
      Run-Command 'docker run -p 9200:9200 -m 4g -e "discovery.type=single-node" --name es elasticsearch:7.9.0'
    }   

    while ($true) {

      Receive-Job $startESJob -OutVariable jOut -ErrorVariable jError

      if ($jError -match ".*?failure in a Windows system call: The virtual machine or container with the specified identifier is not running*?") {
        $retry = $true
      }

      if ($startESJob.JobStateInfo.State -eq "Completed") {
        break
      }

      if ($jOut -match ".*?Active license is now \[BASIC\]; Security is disabled\.*?") {
        break
      }
    }
  } while ($retry)
}

function Remove-Node-Modules {
  Write-Host "Removing node modules"

  Get-ChildItem -Path $Root -Filter node_modules -Recurse -ErrorAction SilentlyContinue -Force |
  ForEach-Object {
    $nodeModulesDir = $_.FullName
    Run-Command "Remove-Item -Recurse -Force $nodeModulesDir"
  }
}

Write-Host "Root:" $Root
Write-Host "Layer:" $Layer

if (!(Test-Path $Root)) {
  Write-Error "Directory $Root does not exist!" -ErrorAction Stop
}

$implementationDir = [io.path]::combine($Root, "implementation")
$monoDir = [io.path]::combine($Root, "mono")

if (!(Test-Path $implementationDir) -or !(Test-Path $monoDir)) {
  Write-Error "Wrong directory structure in $Root mono and implementation dirs expected!" -ErrorAction Stop
}

try {

  Push-Location
  Set-Location $Root

  Start-ES-Docker-In-Background

  Remove-Node-Modules
  
  try {

    Push-Location
    Set-Location .\implementation

    try {
      Run-Command-Stop-On-Error "Move-Item -Path .adi\environments\environment.local.json -Destination .. -Force"

      Run-Command "git stash --include-untracked"
      $stashExitCode = $LASTEXITCODE
  
      Run-Command "echo no | git clean -fdx"
      Run-Command "git reset --hard"
  
      if ($stashExitCode -eq 0) {
        Run-Command-Stop-On-Error "git stash pop"
      }
    } finally {
      Run-Command-Stop-On-Error "Move-Item -Destination .adi\environments -Path ..\environment.local.json -Force"
    }

  } finally {
    Pop-Location  
  }

  try {

    Push-Location
    Set-Location .\mono

    Run-Command-Stop-On-Error ".\build.ps1 -Build -SkipBasic"
    Run-Command-Stop-On-Error ".\build.ps1 -Restore -DatabaseType Oracle -SkipBasic"

  } finally {
    Pop-Location  
  }

  try {

    Push-Location
    Set-Location .\implementation

    Run-Command-Stop-On-Error ".\build.ps1 -Build -ExecuteScripts -TargetLayer $Layer"
    Run-Command-Stop-On-Error "yarn install"

    if ($Layer -like "hr") {
      Run-Command-Stop-On-Error ".\build.ps1 -ImportCSV"
    }

  } finally {
    Pop-Location  
  }

} finally {
  Pop-Location  
}

