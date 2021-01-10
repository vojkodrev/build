
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
  param(
    [parameter(Mandatory=$true)]
    [ScriptBlock]$InitializationScript
  )
  
  do {
    Run-Command "docker rm -f es"

    $retry = $false

    $job = Start-Job -InitializationScript $InitializationScript -ScriptBlock {
      Run-Command 'docker run -p 9200:9200 -m 4g -e "discovery.type=single-node" --name es elasticsearch:7.9.0'
    }   

    while ($true) {

      Receive-Job $job -OutVariable jOut -ErrorVariable jError

      if ($jError -match ".*?failure in a Windows system call: The virtual machine or container with the specified identifier is not running*?") {
        $retry = $true
      }

      if ($job.JobStateInfo.State -eq "Completed") {
        break
      }

      if ($jOut -match ".*?Active license is now \[BASIC\]; Security is disabled.*?") {
        break
      }
    }
  } while ($retry)
}

function Start-Server-In-Background {
  param(
    [parameter(Mandatory=$true)]
    [ScriptBlock]$InitializationScript,

    [parameter(Mandatory=$true)]
    [string]$Dir,

    [parameter(Mandatory=$true)]
    [string]$Command,

    [parameter(Mandatory=$true)]
    [string]$SuccessCheck
  )
  
  $job = Start-Job -InitializationScript $InitializationScript -ArgumentList $Dir,$Command -ScriptBlock {
    param(
      [parameter(Mandatory=$true)]
      [string]$Dir,

      [parameter(Mandatory=$true)]
      [string]$Command
    )

    Set-Location $Dir
    Run-Command $Command
  }

  while ($true) {

    Receive-Job $job -OutVariable jOut -ErrorVariable jError

    if ($job.JobStateInfo.State -eq "Failed") {
      Write-Error "FAILED!" -ErrorAction Stop
    }

    if ($job.JobStateInfo.State -eq "Completed") {
      break
    }

    if ($jOut -match $SuccessCheck) {
      break
    }
  }
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
$monoClientDir = [io.path]::combine($monoDir, "client")

if (!(Test-Path $implementationDir) -or !(Test-Path $monoDir) -or !(Test-Path $monoClientDir)) {
  Write-Error "Wrong directory structure in $Root mono, mono\client and implementation dirs expected!" -ErrorAction Stop
}

try {

  Push-Location
  Set-Location $Root

  Start-ES-Docker-In-Background -InitializationScript $sharedFunctions

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

    Start-Server-In-Background `
      -Command ".\build.ps1 -RunIS" `
      -SuccessCheck ".*?IIS Express is running\..*?" `
      -Dir $monoDir `
      -InitializationScript $sharedFunctions 

    Start-Server-In-Background `
      -Command ".\build.ps1 -RunServer" `
      -SuccessCheck ".*?AdInsure is initialized and ready to use\..*?" `
      -Dir $monoDir `
      -InitializationScript $sharedFunctions

    Run-Command-Stop-On-Error "yarn run validate-workspace -e environment.local.json"
    Run-Command-Stop-On-Error "yarn run publish-workspace -e environment.local.json"

    Run-Command-Stop-On-Error ".\build.ps1 -ExecutePostPublishScripts -TargetLayer $Layer"

  } finally {
    Pop-Location  
  }

  try {

    Push-Location
    Set-Location .\mono\client

    Run-Command-Stop-On-Error "yarn install"
    
    Start-Server-In-Background `
      -Command "yarn run start" `
      -SuccessCheck ".*?Compiled successfully\..*?" `
      -Dir $monoClientDir `
      -InitializationScript $sharedFunctions
    
  } finally {
    Pop-Location  
  }  

} finally {
  Pop-Location  
}

