
param(
  [string]$Root = "c:\code\sava",
  [string]$Layer = "hr",
  [switch]$Clean
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

function Start-Server-In-Background {
  param(
    [parameter(Mandatory=$true)]
    [ScriptBlock]$InitializationScript,

    [string]$Dir,

    [parameter(Mandatory=$true)]
    [string]$Command,

    [string]$CleanUpCommand,

    [parameter(Mandatory=$true)]
    [string]$SuccessCheck,

    [string]$ErrorCheck,

    [switch]$Retry
  )

  do {
    if ($CleanUpCommand) {
      Run-Command $CleanUpCommand
    }

    $runAgain = $false

    $job = Start-Job -InitializationScript $InitializationScript -ArgumentList $Dir,$Command -ScriptBlock {
      param(
        [string]$Dir,
  
        [parameter(Mandatory=$true)]
        [string]$Command
      )
  
      if ($Dir) {
        Set-Location $Dir
      }
      
      Run-Command $Command
    }

    while ($true) {

      Receive-Job $job -OutVariable jOut -ErrorVariable jError

      if ($job.JobStateInfo.State -eq "Failed" -or $ErrorCheck -and $jError -match $ErrorCheck) {
        if ($Retry) {
          $runAgain = $true
        } else {
          Write-Error "FAILED!" -ErrorAction Stop
        }
      }

      if ($job.JobStateInfo.State -eq "Completed") {
        break
      }

      if ($jOut -match $SuccessCheck) {
        break
      }
    }
  } while ($runAgain)
}

function Remove-Node-Modules {
  Write-Host "Removing node modules"

  Get-ChildItem -Path $Root -Filter node_modules -Recurse -ErrorAction SilentlyContinue -Force |
  ForEach-Object {
    $nodeModulesDir = $_.FullName
    Run-Command "Remove-Item -Recurse -Force $nodeModulesDir"
  }
}

function Find-And-Stop-Process {
  param(
    [parameter(Mandatory=$true)]
    [string]$ProcessName,

    [parameter(Mandatory=$true)]
    [string]$Command
  )

  Get-WmiObject Win32_Process -Filter "name = '$ProcessName'" | ForEach-Object {
    $process = $_
    $commandLine = Select-Object -InputObject $process "CommandLine"
    $processId = Select-Object -InputObject $process "ProcessId"

    # Write-Host $commandLine.CommandLine

    if ($commandLine.CommandLine -match $Command) {
      Write-Host "Stopping" $commandLine.CommandLine
      Stop-Process $processId.ProcessId
    }
  }
}

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
  Set-Location $monoDir

  $requiredPlatformVersion = Get-Content ([io.path]::combine($implementationDir, "PLATFORM_VERSION"))
  $correctTag = git tag --points-at HEAD | Select-String $requiredPlatformVersion
  if (-not $correctTag) {
    Write-Error "Mono $requiredPlatformVersion is required" -ErrorAction Stop
  }

} finally {
  Pop-Location  
}

Find-And-Stop-Process `
  -ProcessName "AdInsure.Server.exe" `
  -Command 'AdInsure\.Server\.exe.*?run --urls http://\*:60000'  

Find-And-Stop-Process `
  -ProcessName "docker.exe" `
  -Command 'docker\.exe.*?run -p 9200:9200 -m 4g -e discovery\.type=single-node --name es elasticsearch:7\.9\.0'

Find-And-Stop-Process `
  -ProcessName "node.exe" `
  -Command 'node\.exe.*?@angular\\cli\\bin\\ng.*?serve'

Find-And-Stop-Process `
  -ProcessName "iisexpress.exe" `
  -Command 'iisexpress\.exe.*?/path:.*?AdInsure\.IdentityServer /port:60001'

try {

  Push-Location
  Set-Location $Root

  Start-Server-In-Background `
    -InitializationScript $sharedFunctions `
    -CleanUpCommand "docker rm -f es" `
    -Command 'docker run -p 9200:9200 -m 4g -e "discovery.type=single-node" --name es elasticsearch:7.9.0' `
    -Retry `
    -SuccessCheck ".*?Active license is now \[BASIC\]; Security is disabled.*?" `
    -ErrorCheck ".*?failure in a Windows system call: The virtual machine or container with the specified identifier is not running.*?"

  if ($Clean) {
    Remove-Node-Modules

    try {

      Push-Location
      Set-Location .\implementation

      try {
        Run-Command-Stop-On-Error "Move-Item -Path .adi\environments\environment.local.json -Destination .. -Force"

        $gitStashOutput = Run-Command "git stash --include-untracked"
    
        Run-Command "echo no | git clean -fdx"
        Run-Command "git reset --hard"
    
        if ($gitStashOutput -notmatch ".*?No local changes to save") {
          Run-Command-Stop-On-Error "git stash pop"
        }
      } finally {
        Run-Command-Stop-On-Error "Move-Item -Destination .adi\environments -Path ..\environment.local.json -Force"
      }

    } finally {
      Pop-Location  
    }
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

    $runAgain = $false
    do {
      Run-Command "yarn run publish-workspace -e environment.local.json"
      $runAgain = ($LASTEXITCODE -ne 0)
    } while ($runAgain)

    if ($Layer -like "HR") {
      Run-Command-Stop-On-Error ".\build.ps1 -ExecutePostPublishScripts -TargetLayer $Layer"
    }

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

