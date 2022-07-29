
param(
  [string]
  $Root = "c:\code\sava",
  
  [ValidateSet("hr", "si", "generali-hu", "signal")]
  [string]
  $Layer = "hr",
  
  [string]
  $MasterBranchName = "origin/master",

  [switch]$Clean = $false,

  [switch]$BuildDotNetOnly = $false,
  [switch]$BuildImplementationOnly = $false,
  [switch]$InstallImplementationNodePackagesOnly = $false,
  [switch]$PublishOnly = $false,
  [switch]$DontValidatePlatformVersion = $false,
  [switch]$DontValidateImplementationMasterBranch = $false,
  [switch]$DontValidateWorkspace = $false,
  [switch]$StartServersOnly = $false
)

$sharedFunctions = {
  function Run-Command {
    param (
      [Parameter(Mandatory=$true)]
      [string]$Command,
  
      [string]$Description,

      [ref]$CommandOutput
    )
  
    if ($Description) {
      Write-Output $Description
    }
    
    $currentLocation = Get-Location
    Write-Output "$currentLocation> $Command"

    Invoke-Expression $Command | Tee-Object -Variable ieo

    if ($CommandOutput) {
      $CommandOutput.Value = $ieo
    }
  }
}

. $sharedFunctions


function Run-Command-Stop-On-Error {
  param (
    [Parameter(Mandatory=$true)]
    [string]$Command,

    [string]$Description,

    [ref]$CommandOutput
  )

  $o = $null

  Run-Command -Description $Description -Command $Command -CommandOutput ([ref]$o)
  $commandLastExitCode = $LASTEXITCODE

  if ($CommandOutput) {
    $CommandOutput.Value = $o
  }

  if ($commandLastExitCode -ne 0) {
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

    [switch]$Retry = $false
  )

  do {
    if ($CleanUpCommand) {
      Run-Command-Stop-On-Error $CleanUpCommand
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

      if (($job.JobStateInfo.State -eq "Failed") -or ($job.JobStateInfo.State -eq "Stopped") -or ($ErrorCheck -and ($jError -match $ErrorCheck)) -or ($ErrorCheck -and ($jOut -match $ErrorCheck))) {
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

      if ($jError -match $SuccessCheck) {
        break
      }
    }
  } while ($runAgain)
}

function Remove-Node-Modules {
  param(
    [parameter(Mandatory=$true)]
    [string]$Dir
  )

  Write-Output "Removing node modules $Dir"

  Get-ChildItem -Path $Dir -Filter node_modules -Recurse -ErrorAction SilentlyContinue -Force |
  ForEach-Object {
    $nodeModulesDir = $_.FullName
    Run-Command "Remove-Item -Recurse -Force `"$nodeModulesDir`""
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
    [string]$ImplEnvLocalJsonPath,

    [parameter(Mandatory=$true)]
    [string]$MonoImplSettingsJsonFilename,

    [parameter(Mandatory=$true)]
    [string]$Layer  
  )

  if (!(Test-Path $ImplEnvLocalJsonPath)) {
    Write-Error "Missing $ImplEnvLocalJsonPath" -ErrorAction Stop
  }
  
  if (!(Test-Path $MonoImplSettingsJsonFilename)) {
    Write-Error "Missing $MonoImplSettingsJsonFilename" -ErrorAction Stop
  }

  $parsedImplEnvLocalJson = Parse-Json-Stop-On-Error $ImplEnvLocalJsonPath
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
    Write-Error "Unsupported layer $Layer during $ImplEnvLocalJsonPath validation" -ErrorAction Stop
  }
  
  if ($parsedImplEnvLocalJson.targetLayer -ne $requiredJsonTargetlayer) {
    Write-Error "Target layer must be $requiredJsonTargetlayer in $ImplEnvLocalJsonPath" -ErrorAction Stop
  }
  
  if ($parsedImplEnvLocalJson.localCurrency -ne $requiredJsonCurrency) {
    Write-Error "Currency must be $requiredJsonCurrency in $ImplEnvLocalJsonPath" -ErrorAction Stop
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

  $startingLocation = Get-Location

  try {

    Set-Location $MonoDir
  
    $requiredPlatformVersion = [IO.File]::ReadAllText([io.path]::combine($ImplementationDir, "PLATFORM_VERSION"))
    $correctTag = git tag --points-at HEAD | Select-String $requiredPlatformVersion
    if (!$correctTag) {
      Write-Error "Mono $requiredPlatformVersion is required" -ErrorAction Stop
    }
  
  } finally {
    Set-Location $startingLocation
  }
}

function Validate-Implementation-Master-Branch {
  param(
    [parameter(Mandatory=$true)]
    [string]$ImplementationDir,

    [parameter(Mandatory=$true)]
    [string]$MasterBranchName
  )

  $startingLocation = Get-Location

  try {
    Set-Location $ImplementationDir
  
    Run-Command-Stop-On-Error "git fetch"
  
    if (git branch --show-current) {
      git merge-base --is-ancestor $MasterBranchName $(git branch --show-current)
      if ($LASTEXITCODE -gt 0) {
        Write-Error "There are new changes in $MasterBranchName. It should be merged into current branch." -ErrorAction Stop
      }
    }
  
  } finally {
    Set-Location $startingLocation
  }
}

function Set-All-Values {
  param(
    [parameter(Mandatory=$true)]
    [hashtable]$Hashtable,

    [parameter(Mandatory=$true)]
    $Value
  )

  $keys = $Hashtable.Keys | ForEach-Object ToString
  foreach ($key in $keys) {
    $Hashtable[$key] = $Value
  }
}

function All-Values-Are {
  param(
    [parameter(Mandatory=$true)]
    [array]$Arr,

    [parameter(Mandatory=$true)]
    $Value
  )

  foreach ($e in $arr) {
    if ($e -ne $Value) {
      return $false
    }
  }

  return $true
}

function Start-Adinsure-Server-In-Background {
  param(
    [parameter(Mandatory=$true)]
    [string]$MonoDir,

    [parameter(Mandatory=$true)]
    [ScriptBlock]$InitializationScript
  )

  Start-Server-In-Background `
    -Command ".\build.ps1 -RunServer" `
    -SuccessCheck "AdInsure is initialized and ready to use\." `
    -Dir $MonoDir `
    -InitializationScript $InitializationScript
}

function Stop-Adinsure-Server {

  Find-And-Stop-Process `
    -ProcessName "AdInsure.Server.exe" `
    -Command 'AdInsure\.Server\.exe.*?run --urls http://\*:60000' 
}

$startingLocation = Get-Location

try {

  $instructions = @{
    ValidatePlatformVersion = $false
    ValidateImplementationMasterBranch = $false
    StopAdInsureServer = $false
    StopAngularClient = $false
    StopIdentityServer = $false
    StopScheduler = $false
    BuildAdInsureServer = $false
    RestoreDatabase = $false
    BuildImplementation = $false
    ExecuteImplementationDatabaseScripts = $false
    InstallImplementationNodePackages = $false
    ImportCSV = $false
    StartIdentityServer = $false
    StartAdInsureServer = $false
    ValidateWorkspace = $false
    PublishWorkspace = $false
    ExecuteImplementationPostPublishDatabaseScripts = $false
    InstallAngularNodePackages = $false
    StartAngularClient = $false
  }

  if ($PublishOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateWorkspace = $true
    $instructions.PublishWorkspace = $true
  }

  if ($BuildDotNetOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StopIdentityServer = $true
    $instructions.StopScheduler = $true
    $instructions.BuildAdInsureServer = $true
    $instructions.BuildImplementation = $true
    $instructions.StartIdentityServer = $true
    $instructions.StartAdInsureServer = $true
  }

  if ($BuildImplementationOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StopScheduler = $true
    $instructions.BuildImplementation = $true
    $instructions.StartAdInsureServer = $true
  }

  if ($InstallImplementationNodePackagesOnly) {
    $instructions.InstallImplementationNodePackages = $true
  }

  if ($StartServersOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StopIdentityServer = $true
    $instructions.StopAngularClient = $true
    $instructions.StartIdentityServer = $true
    $instructions.StartAdInsureServer = $true
    $instructions.StartAngularClient = $true
  }

  if (All-Values-Are @($PublishOnly, $BuildDotNetOnly, $StartServersOnly, $BuildImplementationOnly, $InstallImplementationNodePackagesOnly) -Value $false) {
    Set-All-Values $instructions -Value $true
  }

  if ($DontValidatePlatformVersion) {
    $instructions.ValidatePlatformVersion = $false
  }

  if ($DontValidateImplementationMasterBranch) {
    $instructions.ValidateImplementationMasterBranch = $false
  }

  if ($DontValidateWorkspace) {
    $instructions.ValidateWorkspace = $false
  }

  if (!(Test-Path $Root)) {
    Write-Error "Directory $Root does not exist!" -ErrorAction Stop
  }

  $implementationDir = [io.path]::combine($Root, "implementation")
  $implementationConfigurationDir = [io.path]::combine($implementationDir, "configuration")
  $printoutAssetsDir = [io.path]::combine($implementationDir, "printout-assets")
  $monoDir = [io.path]::combine($Root, "mono")
  $monoClientDir = [io.path]::combine($monoDir, "client")
  $monoConfDir = [io.path]::combine($monoDir, "server", "AdInsure.Server", "conf")
  $adiEnvDir = [io.path]::combine($implementationDir, ".adi", "environments")
  $monoImplSettingsJsonFilename = [io.path]::combine($monoConfDir, "implSettings.json")

  $implEnvLocalJsonFilename = $null
  if (($Layer -ne "generali-hu") -and ($Layer -ne "signal")) {
    $implEnvLocalJsonFilename = "environment.local.$Layer.json"
  } else {
    $implEnvLocalJsonFilename = "environment.local.json"
  }
  $implEnvLocalJsonPath = [io.path]::combine($adiEnvDir, $implEnvLocalJsonFilename)

  if (!(Test-Path $implementationDir) -or !(Test-Path $monoDir) -or !(Test-Path $monoClientDir) -or !(Test-Path $implementationConfigurationDir)) {
    Write-Error "Wrong directory structure in $Root mono, mono\client and implementation dirs expected!" -ErrorAction Stop
  }

  # Validate-Impl-Env-Local-Json `
  #   -Layer $Layer `
  #   -ImplEnvLocalJsonPath $implEnvLocalJsonPath `
  #   -MonoImplSettingsJsonFilename $monoImplSettingsJsonFilename

  if ($instructions.ValidateImplementationMasterBranch) {
    Validate-Implementation-Master-Branch `
      -ImplementationDir $implementationDir `
      -MasterBranchName $MasterBranchName
  }

  if ($instructions.ValidatePlatformVersion) {
    Validate-Platform-Version `
      -MonoDir $monoDir `
      -ImplementationDir $implementationDir
  }

  if ($instructions.StopAdInsureServer) {
    Stop-Adinsure-Server
  }

  if ($instructions.StopAngularClient) {
    Find-And-Stop-Process `
      -ProcessName "node.exe" `
      -Command 'node\.exe.*?@angular\\cli\\bin\\ng.*?serve'
  }

  if ($instructions.StopIdentityServer) {
    Find-And-Stop-Process `
      -ProcessName "AdInsure.IdentityServer.exe" `
      -Command 'AdInsure\.IdentityServer\.exe"  run'
  }

  if ($instructions.StopScheduler) {
    Find-And-Stop-Process `
      -ProcessName "iisexpress.exe" `
      -Command 'iisexpress\.exe"  /config:".*?AdInsure\.Scheduler\\config\\applicationhost\.config" /site:"Scheduler\.Web" /apppool:"Scheduler\.Web AppPool"'     
  }

  Set-Location $Root

  if ($Clean) {


    # $dockerService = Get-Service docker

    # # if ($dockerService.Status -eq "Running") {
    # Write-Output "Stopping docker"
    # Stop-Service $dockerService
    # # }

    # # if ($dockerService.Status -eq "Stopped") {
    # Write-Output "Starting docker"
    # Start-Service $dockerService
    # # }

    # Run-Command-Stop-On-Error "docker start db_mssql_dev"

    Remove-Node-Modules -Dir $Root

    Write-Output "Cleaning mono"

    Set-Location $monoDir

    try {
      # Run-Command-Stop-On-Error "Move-Item -Path identityServer\src\AdInsure.IdentityServer\appsettings.json -Destination .. -Force"
      # Run-Command-Stop-On-Error "Move-Item -Path server\AdInsure.Server\conf\databaseConfiguration.json -Destination .. -Force"
      Run-Command-Stop-On-Error "Move-Item -Path server\AdInsure.Server\conf\implSettings.json -Destination .. -Force"

      $gitStashOutput = Run-Command "git stash --include-untracked"
      Write-Output $gitStashOutput

      Run-Command "echo no | git clean -fdx"
      Run-Command "git reset --hard"

      if (!($gitStashOutput -match "No local changes to save")) {
        Run-Command-Stop-On-Error "git stash pop"
      }
    } finally {
      # Run-Command-Stop-On-Error "Move-Item -Destination identityServer\src\AdInsure.IdentityServer -Path ..\appsettings.json -Force"
      # Run-Command-Stop-On-Error "Move-Item -Destination server\AdInsure.Server\conf -Path ..\databaseConfiguration.json -Force"
      Run-Command-Stop-On-Error "Move-Item -Destination server\AdInsure.Server\conf -Path ..\implSettings.json -Force"
    }

    Write-Output "Cleaning implementation"

    Set-Location $implementationDir

    # try {
      # Run-Command-Stop-On-Error "Move-Item -Path .adi\environments\environment.local.json -Destination .. -Force"

    $gitStashOutput = Run-Command "git stash --include-untracked"
    Write-Output $gitStashOutput

    Run-Command "echo no | git clean -fdx"
    Run-Command "git reset --hard"

    if (!($gitStashOutput -match "No local changes to save")) {
      Run-Command-Stop-On-Error "git stash pop"
    }
    # } finally {
      # Run-Command-Stop-On-Error "Move-Item -Destination .adi\environments -Path ..\environment.local.json -Force"
    # }

    if (!(Test-Path -Path $printoutAssetsDir)) {
      New-Item -Path $printoutAssetsDir -ItemType Directory
    }

    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f db_mssql_dev" `
      -Command 'docker run -p 1433:1433 --name db_mssql_dev -m 3g registry.adacta-fintech.com/adinsure/mono/ops/mssql:6-latest-prepublished-ltsc2019' `
      -SuccessCheck "VERBOSE: Started SQL Server"

    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f signal_pdf" `
      -Command "docker run -p 9423:9423 --name signal_pdf -v `"${printoutAssetsDir}:/assets/printout-assets`" --env JAVA_OPTIONS=`"-Xmx2g -Dcom.realobjects.pdfreactor.webservice.securitySettings.defaults.allowFileSystemAccess=true`" --platform=linux realobjects/pdfreactor:10" `
      -SuccessCheck "INFO: Started @\d+ms"

    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f es" `
      -Command 'docker run -p 9200:9200 -m 4g -e "discovery.type=single-node" --platform=linux --name es -h es elasticsearch:7.9.0' `
      -Retry `
      -SuccessCheck "Active license is now \[BASIC\]; Security is disabled" `
      -ErrorCheck "failure in a Windows system call: The virtual machine or container with the specified identifier is not running"    

    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f amq" `
      -Command 'docker run -p 61616:61616 -p 8161:8161 --platform=linux --name amq rmohr/activemq:5.15.9' `
      -Retry `
      -SuccessCheck "INFO \| jolokia-agent: Using policy access restrictor classpath:\/jolokia-access.xml" `
      -ErrorCheck "encountered an error during hcsshim::System::waitBackground: failure in a Windows system call: The virtual machine or container with the specified identifier is not running"

    # Start-Server-In-Background `
    #   -InitializationScript $sharedFunctions `
    #   -CleanUpCommand 'docker rm -f oracle' `
    #   -Command 'docker run -p 1521:1521 --name oracle registry.adacta-fintech.com/ops/infra/oracle-xe:18.4-1709' `
    #   -Retry
  }

  Set-Location $monoDir

  if ($instructions.BuildAdInsureServer) {
    Run-Command-Stop-On-Error ".\build.ps1 -Build -SkipBasic"
  }
  
  if ($instructions.RestoreDatabase) {
    if (($Layer -ne "generali-hu") -and ($Layer -ne "signal")) {
      Run-Command-Stop-On-Error ".\build.ps1 -Restore -DatabaseType Oracle -SkipBasic -DatabaseOracleSID ORCLCDB"
    } else {
      Run-Command-Stop-On-Error ".\build.ps1 -Restore -DatabaseType MSSQL -SkipBasic"
    } 
  }

  Set-Location $implementationDir

  if ($instructions.BuildImplementation) {
    Run-Command-Stop-On-Error ".\build.ps1 -Build -TargetLayer $Layer"
  }

  # Write-Output "Current location before fail - $(Get-Location)"
  # Write-Error "FAILED!" -ErrorAction Stop
  
  if ($instructions.ExecuteImplementationDatabaseScripts) {
    Run-Command-Stop-On-Error ".\build.ps1 -ExecuteScripts -TargetLayer $Layer"
  }
  
  if ($instructions.InstallImplementationNodePackages) {
    if ($InstallImplementationNodePackagesOnly) {
      Remove-Node-Modules -Dir $implementationDir
    }

    do {
      $runAgain = $false
      $yarnInstallOutput = $null
      
      Run-Command-Stop-On-Error "yarn install" -CommandOutput ([ref]$yarnInstallOutput)

      if ($yarnInstallOutput -match "Request failed.*?401 Unauthorized") {
        $runAgain = $true
      }
    } while ($runAgain)
  }

  if (($Layer -like "hr") -and ($instructions.ImportCSV)) {
    Run-Command-Stop-On-Error ".\build.ps1 -ImportCSV"
  }

  if ($instructions.StartIdentityServer) {
    Start-Server-In-Background `
      -Command ".\build.ps1 -RunIS" `
      -SuccessCheck "Using launch settings from \.\\identityServer\\src\\AdInsure\.IdentityServer\\Properties\\launchSettings\.json" `
      -Dir $monoDir `
      -InitializationScript $sharedFunctions `
      -ErrorCheck "Unable to start Kestrel\."
  }

  if ($instructions.StartAdInsureServer) {
    
    # Run-Command "docker stop db_mssql_dev"
    # Run-Command "docker start db_mssql_dev"

    Start-Adinsure-Server-In-Background `
      -MonoDir $monoDir `
      -InitializationScript $sharedFunctions
  }

  if ($instructions.ValidateWorkspace) {
    Run-Command-Stop-On-Error "yarn run validate-workspace -e $implEnvLocalJsonFilename" #-CommandOutput ([ref]$validateWorkspaceOutput)
  }
  
  if ($instructions.PublishWorkspace) {

    do {

      $runAgain = $false
      $publishWorkspaceOutput = $null
      
      # TODO: remove command output and just use return
      Run-Command "yarn run publish-workspace -e $implEnvLocalJsonFilename" -CommandOutput ([ref]$publishWorkspaceOutput)

      if (($publishWorkspaceOutput -match "\[ERROR\].*?Invocation of script 'Publish workspace' failed.*?Token exchange failed.*?TimeoutError") `
        -or ($publishWorkspaceOutput -match "failed, reason: socket hang up") `
        -or ($publishWorkspaceOutput -match "Could not create ADO\.NET connection for transaction") `
      ) {

        Stop-Adinsure-Server

        Run-Command "docker stop db_mssql_dev"
        Run-Command "docker start db_mssql_dev"

        Start-Adinsure-Server-In-Background `
          -MonoDir $monoDir `
          -InitializationScript $sharedFunctions

        $runAgain = $true
      }
      elseif ($LASTEXITCODE -ne 0) {
        Write-Error "Publish Workspace FAILED!" -ErrorAction Stop
      }
    } while ($runAgain)
  }
  
  if ($instructions.ExecuteImplementationPostPublishDatabaseScripts -and ($Layer -ne "generali-hu") -and ($Layer -ne "signal")) {
    Run-Command-Stop-On-Error ".\build.ps1 -ExecutePostPublishScripts -TargetLayer $Layer"
  }

  Set-Location $monoClientDir

  if ($instructions.InstallAngularNodePackages) {
    Run-Command-Stop-On-Error "yarn install"
  }
  
  if ($instructions.StartAngularClient) {
    Start-Server-In-Background `
      -Command "yarn run start" `
      -SuccessCheck "Compiled successfully\." `
      -Dir $monoClientDir `
      -InitializationScript $sharedFunctions
  }

} finally {
  Set-Location $startingLocation
}

