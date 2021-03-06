
param(
  [string]
  $Root = "c:\code\sava",
  
  [ValidateSet("hr", "si")]
  [string]
  $Layer = "hr",
  
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
      Write-Output $Description
    }
    
    $currentLocation = Get-Location
    Write-Output "$currentLocation> $Command"

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

      if (($job.JobStateInfo.State -eq "Failed") -or ($ErrorCheck -and ($jError -match $ErrorCheck))) {
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
  Write-Output "Removing node modules"

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

    # Write-Output $commandLine.CommandLine

    if ($commandLine.CommandLine -match $Command) {
      Write-Output "Stopping $($commandLine.CommandLine)"
      Stop-Process $processId.ProcessId
    }
  }
}

function Parse-Json-Stop-On-Error {
  param(
    [parameter(Mandatory=$true)]
    [string]$Filename
  )

  $json = ConvertFrom-Json ([IO.File]::ReadAllText($Filename))
  if (!$json) {
    Write-Error "Unable to parse $Filename" -ErrorAction Stop
  }

  return $json
}

function Validate-Impl-Env-Local-Json {
  param(
    [parameter(Mandatory=$true)]
    [string]$ImplEnvLocalJsonFilename,

    [parameter(Mandatory=$true)]
    [string]$MonoImplSettingsJsonFilename,

    [parameter(Mandatory=$true)]
    [string]$Layer  
  )

  if (!(Test-Path $ImplEnvLocalJsonFilename)) {
    Write-Error "Missing $ImplEnvLocalJsonFilename" -ErrorAction Stop
  }
  
  if (!(Test-Path $MonoImplSettingsJsonFilename)) {
    Write-Error "Missing $MonoImplSettingsJsonFilename" -ErrorAction Stop
  }

  $parsedImplEnvLocalJson = Parse-Json-Stop-On-Error $ImplEnvLocalJsonFilename
  $parsedMonoImplSettingsJson = Parse-Json-Stop-On-Error $MonoImplSettingsJsonFilename
  
  $requiredJsonTargetlayer = $null
  $requiredJsonCurrency = $null
  
  if ($Layer -eq "si") {
    $requiredJsonTargetlayer = "sava-si"
    $requiredJsonCurrency = "EUR"
  } elseif ($Layer -eq "hr") {
    $requiredJsonTargetlayer = "sava-hr"
    $requiredJsonCurrency = "HRK"
  } else {
    Write-Error "Unsupported layer $Layer during $ImplEnvLocalJsonFilename validation" -ErrorAction Stop
  }
  
  if ($parsedImplEnvLocalJson.targetLayer -ne $requiredJsonTargetlayer) {
    Write-Error "Target layer must be $requiredJsonTargetlayer in $ImplEnvLocalJsonFilename" -ErrorAction Stop
  }
  
  if ($parsedImplEnvLocalJson.localCurrency -ne $requiredJsonCurrency) {
    Write-Error "Currency must be $requiredJsonCurrency in $ImplEnvLocalJsonFilename" -ErrorAction Stop
  }
  
  if ($parsedImplEnvLocalJson.documentIndex -ne $parsedMonoImplSettingsJson.appSettings.AdInsure.Settings.General.ESIndexPrefix) {
    Write-Error "Document index must be $($parsedMonoImplSettingsJson.appSettings.AdInsure.Settings.General.ESIndexPrefix) in $MonoImplSettingsJsonFilename" -ErrorAction Stop
  }  
}

function Validate-Platform-Version {
  param(
    [parameter(Mandatory=$true)]
    [string]$ImplementationDir,

    [parameter(Mandatory=$true)]
    [string]$MonoDir
  )

  try {

    Push-Location
    Set-Location $MonoDir
  
    $requiredPlatformVersion = [IO.File]::ReadAllText([io.path]::combine($ImplementationDir, "PLATFORM_VERSION"))
    $correctTag = git tag --points-at HEAD | Select-String $requiredPlatformVersion
    if (!$correctTag) {
      Write-Error "Mono $requiredPlatformVersion is required" -ErrorAction Stop
    }
  
  } finally {
    Pop-Location
  }
}

if (!(Test-Path $Root)) {
  Write-Error "Directory $Root does not exist!" -ErrorAction Stop
}

$implementationDir = [io.path]::combine($Root, "implementation")
$monoDir = [io.path]::combine($Root, "mono")
$monoClientDir = [io.path]::combine($monoDir, "client")
$monoConfDir = [io.path]::combine($monoDir, "server", "AdInsure.Server", "conf")
$adiEnvDir = [io.path]::combine($implementationDir, ".adi", "environments")
$implEnvLocalJsonFilename = [io.path]::combine($adiEnvDir, "environment.local.json")
$monoImplSettingsJsonFilename = [io.path]::combine($monoConfDir, "implSettings.json")

if (!(Test-Path $implementationDir) -or !(Test-Path $monoDir) -or !(Test-Path $monoClientDir)) {
  Write-Error "Wrong directory structure in $Root mono, mono\client and implementation dirs expected!" -ErrorAction Stop
}

Validate-Impl-Env-Local-Json `
  -Layer $Layer `
  -ImplEnvLocalJsonFilename $implEnvLocalJsonFilename `
  -MonoImplSettingsJsonFilename $monoImplSettingsJsonFilename

try {
  Push-Location
  Set-Location $implementationDir

  Run-Command-Stop-On-Error "git fetch"

  # if ((Get-Date (git log origin/master --pretty=format:"%cd" --date=iso -n 1)) -gt (Get-Date (git log --pretty=format:"%cd" --date=iso -n 1))) {
  git merge-base --is-ancestor origin/master $(git branch --show-current)
  if ($LASTEXITCODE -gt 0) {
    # Write-Error "Master is ahead of current branch" -ErrorAction Stop
    Write-Error "There are new changes in master. It should be merged into current branch." -ErrorAction Stop
  }

} finally {
  Pop-Location
}

Validate-Platform-Version `
  -MonoDir $monoDir `
  -ImplementationDir $implementationDir

Find-And-Stop-Process `
  -ProcessName "AdInsure.Server.exe" `
  -Command 'AdInsure\.Server\.exe.*?run --urls http://\*:60000'  

# Find-And-Stop-Process `
#   -ProcessName "docker.exe" `
#   -Command 'docker\.exe.*?run -p 9200:9200 -m 4g -e discovery\.type=single-node --name es elasticsearch:7\.9\.0'

Find-And-Stop-Process `
  -ProcessName "node.exe" `
  -Command 'node\.exe.*?@angular\\cli\\bin\\ng.*?serve'

Find-And-Stop-Process `
  -ProcessName "iisexpress.exe" `
  -Command 'iisexpress\.exe.*?/path:.*?AdInsure\.IdentityServer /port:60001'

try {

  Push-Location
  Set-Location $Root

  if ($Clean) {
    Remove-Node-Modules

    try {

      Write-Output "Cleaning mono"

      Push-Location
      Set-Location .\mono

      try {
        Run-Command-Stop-On-Error "Move-Item -Path identityServer\src\AdInsure.IdentityServer\Web.config -Destination .. -Force"
        Run-Command-Stop-On-Error "Move-Item -Path server\AdInsure.Server\conf\databaseConfiguration.json -Destination .. -Force"
        Run-Command-Stop-On-Error "Move-Item -Path server\AdInsure.Server\conf\implSettings.json -Destination .. -Force"

        Run-Command "echo no | git clean -fdx"
        Run-Command "git reset --hard"
      } finally {
        Run-Command-Stop-On-Error "Move-Item -Destination identityServer\src\AdInsure.IdentityServer -Path ..\Web.config -Force"
        Run-Command-Stop-On-Error "Move-Item -Destination server\AdInsure.Server\conf -Path ..\databaseConfiguration.json -Force"
        Run-Command-Stop-On-Error "Move-Item -Destination server\AdInsure.Server\conf -Path ..\implSettings.json -Force"
      }

    } finally {
      Pop-Location  
    }

    try {

      Write-Output "Cleaning implementation"

      Push-Location
      Set-Location .\implementation

      try {
        Run-Command-Stop-On-Error "Move-Item -Path .adi\environments\environment.local.json -Destination .. -Force"

        $gitStashOutput = Run-Command "git stash --include-untracked"
        Write-Output $gitStashOutput
    
        Run-Command "echo no | git clean -fdx"
        Run-Command "git reset --hard"
    
        if (!($gitStashOutput -match "No local changes to save")) {
          Run-Command-Stop-On-Error "git stash pop"
        }
      } finally {
        Run-Command-Stop-On-Error "Move-Item -Destination .adi\environments -Path ..\environment.local.json -Force"
      }

    } finally {
      Pop-Location  
    }

    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f es" `
      -Command 'docker run -p 9200:9200 -m 4g -e "discovery.type=single-node" --name es elasticsearch:7.9.0' `
      -Retry `
      -SuccessCheck "Active license is now \[BASIC\]; Security is disabled" `
      -ErrorCheck "failure in a Windows system call: The virtual machine or container with the specified identifier is not running"    

    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f amq" `
      -Command 'docker run -p 61616:61616 -p 8161:8161 --name amq registry.adacta-fintech.com/adinsure/platform/amq' `
      -Retry `
      -SuccessCheck "INFO \| jolokia-agent: Using policy access restrictor classpath:\/jolokia-access.xml" # `
      # -ErrorCheck "failure in a Windows system call: The virtual machine or container with the specified identifier is not running"         
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

    Run-Command-Stop-On-Error ".\build.ps1 -Build -TargetLayer $Layer"
    Run-Command-Stop-On-Error ".\build.ps1 -ExecuteScripts -TargetLayer $Layer"
    Run-Command-Stop-On-Error "yarn install"

    if ($Layer -like "hr") {
      Run-Command-Stop-On-Error ".\build.ps1 -ImportCSV"
    }

    Start-Server-In-Background `
      -Command ".\build.ps1 -RunIS" `
      -SuccessCheck "IIS Express is running\." `
      -Dir $monoDir `
      -InitializationScript $sharedFunctions 

    Start-Server-In-Background `
      -Command ".\build.ps1 -RunServer" `
      -SuccessCheck "AdInsure is initialized and ready to use\." `
      -Dir $monoDir `
      -InitializationScript $sharedFunctions

    Run-Command-Stop-On-Error "yarn run validate-workspace" # -e environment.local.json

    do {
      Run-Command "yarn run publish-workspace" # -e environment.local.json
    } while ($LASTEXITCODE -ne 0)

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
      -SuccessCheck "Compiled successfully\." `
      -Dir $monoClientDir `
      -InitializationScript $sharedFunctions
    
  } finally {
    Pop-Location  
  }  

} finally {
  Pop-Location  
}

