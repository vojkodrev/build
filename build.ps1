
param(
  [string]
  $Root = "c:\code\sava",
  
  [ValidateSet("hr", "si", "generali-hu", "signal", "re", "triglav-si")]
  [string]
  $Layer = "hr",
  
  [string]
  $MasterBranchName = "origin/master",

  [switch]$Clean = $false,
  [switch]$CleanNodeModules = $false,
  
  [switch]$ForcePublish = $false,
  [switch]$RestartAdInsureServerAfterPublish = $false,
  [switch]$GitRebase = $false,

  [switch]$BuildDotNetOnly = $false,
  [switch]$BuildImplementationOnly = $false,
  [switch]$BuildMockIntegrationServiceOnly = $false,
  [switch]$InstallImplementationNodePackagesOnly = $false,
  [switch]$PublishOnly = $false,
  [switch]$CleanESOnly = $false,
  [switch]$CleanAMQOnly = $false,
  [switch]$ExecuteImplementationDatabaseScriptsOnly = $false,
  [switch]$DontValidatePlatformVersion = $false,
  [switch]$DontValidateBasicVersion = $false,
  [switch]$DontValidateImplementationMasterBranch = $false,
  [switch]$DontValidateWorkspace = $false,
  [switch]$DontStartScheduler = $false,
  [switch]$StartServersOnly = $false,
  [switch]$StartAdInsureServerOnly = $false,
  [switch]$StartSchedulerOnly = $false,
  [switch]$PublishSchedulerJobsOnly = $false,
  [switch]$StopSchedulerOnly = $false,
  [switch]$ClearAdInsureServerLogsOnly = $false
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

  if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $null)) {
    Write-Error "FAILED ($LASTEXITCODE)!" -ErrorAction Stop
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

      if (($job.JobStateInfo.State -eq "Failed") `
        -or ($job.JobStateInfo.State -eq "Stopped") `
        -or ($ErrorCheck -and ($jError -match $ErrorCheck)) `
        -or ($ErrorCheck -and ($jOut -match $ErrorCheck)) `
      ) {
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

    [string]$Command
  )

  Get-WmiObject Win32_Process -Filter "name = '$ProcessName'" | ForEach-Object {
    $process = $_
    $commandLine = Select-Object -InputObject $process "CommandLine"
    $processId = Select-Object -InputObject $process "ProcessId"

    # Write-Output $commandLine.CommandLine

    if (($Command -and $commandLine.CommandLine -match $Command) -or (!$Command)) {
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
  } elseif ($Layer -eq "signal") {
    $requiredJsonTargetlayer = "signal"
    $requiredJsonCurrency = "HUF"
  } elseif ($Layer -eq "triglav-si") {
    $requiredJsonTargetlayer = "triglav-si"
    $requiredJsonCurrency = "EUR"
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
    [string]$Dir,

    [parameter(Mandatory=$true)]
    [string]$Desc
  )

  $startingLocation = Get-Location

  try {

    Set-Location $Dir
  
    $requiredPlatformVersion = [IO.File]::ReadAllText([io.path]::combine($ImplementationDir, "PLATFORM_VERSION"))
    # $correctTag = git tag --points-at HEAD | Select-String $requiredPlatformVersion
    $correctBranch = git rev-parse --abbrev-ref HEAD | Select-String $requiredPlatformVersion
    if (!$correctBranch) {
      Write-Error "$Desc $requiredPlatformVersion is required" -ErrorAction Stop
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

    if ($GitRebase) {
      Run-Command-Stop-On-Error "git rebase --autostash origin/master"
    }
  
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
    ValidateBasicVersion = $false
    ValidateImplementationMasterBranch = $false
    CleanES = $false
    CleanAMQ = $false
    StopAdInsureServer = $false
    StopAngularClient = $false
    StopIdentityServer = $false
    StopScheduler = $false
    StopMockIntegrationService = $false
    StopSimulatedDMS = $false
    BuildAdInsureServer = $false
    RestoreDatabase = $false
    BuildImplementation = $false
    ExecuteImplementationDatabaseScripts = $false
    InstallImplementationNodePackages = $false
    ImportCSV = $false
    StartIdentityServer = $false
    ClearAdInsureServerLogs = $false
    StartAdInsureServer = $false
    StartMockIntegrationService = $false
    StartSimulatedDMS = $false
    ValidateWorkspace = $false
    PublishWorkspace = $false
    ExecuteImplementationPostPublishDatabaseScripts = $false
    InstallAngularNodePackages = $false
    StartAngularClient = $false
    StartScheduler = $false
    PublishSchedulerJobs = $false
  }

  if ($CleanESOnly) {
    $instructions.CleanES = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StartAdInsureServer = $true
  }

  if ($CleanAMQOnly) {
    $instructions.CleanAMQ = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StartAdInsureServer = $true
  }

  if ($PublishOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateBasicVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.ValidateWorkspace = $true
    $instructions.PublishWorkspace = $true
  }

  if ($BuildDotNetOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateBasicVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StopIdentityServer = $true
    $instructions.StopMockIntegrationService = $true
    $instructions.StopSimulatedDMS = $true
    $instructions.StopScheduler = $true
    $instructions.BuildAdInsureServer = $true
    $instructions.BuildImplementation = $true
    $instructions.StartIdentityServer = $true
    $instructions.StartAdInsureServer = $true
    $instructions.StartScheduler = $true
    $instructions.StartMockIntegrationService = $true
    $instructions.StartSimulatedDMS = $true
  }

  if ($BuildMockIntegrationServiceOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateBasicVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopMockIntegrationService = $true
    $instructions.StartMockIntegrationService = $true
  }

  if ($BuildImplementationOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateBasicVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StopScheduler = $true
    $instructions.StopMockIntegrationService = $true
    $instructions.StopSimulatedDMS = $true
    $instructions.BuildImplementation = $true
    $instructions.StartAdInsureServer = $true
    $instructions.StartMockIntegrationService = $true
    $instructions.StartSimulatedDMS = $true
    $instructions.StartScheduler = $true
  }

  if ($InstallImplementationNodePackagesOnly) {
    $instructions.InstallImplementationNodePackages = $true
  }

  if ($StartServersOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateBasicVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StopIdentityServer = $true
    $instructions.StopAngularClient = $true
    $instructions.StopMockIntegrationService = $true
    $instructions.StopSimulatedDMS = $true
    $instructions.StopScheduler = $true
    $instructions.StartIdentityServer = $true
    $instructions.StartAdInsureServer = $true
    $instructions.StartAngularClient = $true
    $instructions.StartMockIntegrationService = $true
    $instructions.StartSimulatedDMS = $true
    $instructions.StartScheduler = $true
  }

  if ($StartAdInsureServerOnly) {
    $instructions.ValidatePlatformVersion = $true
    $instructions.ValidateBasicVersion = $true
    $instructions.ValidateImplementationMasterBranch = $true
    $instructions.StopAdInsureServer = $true
    $instructions.StartAdInsureServer = $true
  }

  if ($StartSchedulerOnly) {
    $instructions.StartScheduler = $true
  }

  if ($StopSchedulerOnly) {
    $instructions.StopScheduler = $true
  }

  if ($PublishSchedulerJobsOnly) {
    $instructions.StartScheduler = $true
    $instructions.PublishSchedulerJobs = $true
  }

  if ($ExecuteImplementationDatabaseScriptsOnly) {
    $instructions.ExecuteImplementationDatabaseScripts = $true
  }
  
  if ($ClearAdInsureServerLogsOnly) {
    $instructions.StopAdInsureServer = $true
    $instructions.ClearAdInsureServerLogs = $true
    $instructions.StartAdInsureServer = $true
  }

  if (All-Values-Are @( `
      $PublishOnly, `
      $BuildDotNetOnly, `
      $StartServersOnly, `
      $StartAdInsureServerOnly, `
      $BuildImplementationOnly, `
      $BuildMockIntegrationServiceOnly, `
      $InstallImplementationNodePackagesOnly, `
      $CleanESOnly, `
      $CleanAMQOnly, `
      $ExecuteImplementationDatabaseScriptsOnly, `
      $StartSchedulerOnly, `
      $StopSchedulerOnly, `
      $PublishSchedulerJobsOnly, `
      $ClearAdInsureServerLogsOnly `
    ) -Value $false `
  ) {
    Set-All-Values $instructions -Value $true
  }

  if ($DontValidatePlatformVersion) {
    $instructions.ValidatePlatformVersion = $false
  }

  if ($DontValidateBasicVersion) {
    $instructions.ValidateBasicVersion = $false
  }

  if ($DontValidateImplementationMasterBranch) {
    $instructions.ValidateImplementationMasterBranch = $false
  }

  if ($DontValidateWorkspace) {
    $instructions.ValidateWorkspace = $false
  }

  if ($DontStartScheduler) {
    $instructions.StartScheduler = $false
  }

  if (!(Test-Path $Root)) {
    Write-Error "Directory $Root does not exist!" -ErrorAction Stop
  }

  $implementationDir = [io.path]::combine($Root, "implementation")
  $implementationConfigurationDir = [io.path]::combine($implementationDir, "configuration")
  $implementationSchedulerDir1 = [io.path]::combine($implementationDir, ".build", 'scheduler')
  $implementationSchedulerDir2 = [io.path]::combine($implementationDir, 'scheduler')
  $printoutAssetsDir = [io.path]::combine($implementationDir, "printout-assets")
  $monoDir = [io.path]::combine($Root, "mono")
  $basicDir = [io.path]::combine($Root, "basic")
  $adinsureServerLogsDir = [io.path]::combine($Root, "logs")
  $schedulerRootDir = [io.path]::combine($Root, "scheduler")
  $schedulerSolutionDir = [io.path]::combine($schedulerRootDir, "src")
  $monoClientDir = [io.path]::combine($monoDir, "client")
  $monoConfDir = [io.path]::combine($monoDir, "server", "AdInsure.Server", "conf")
  $adiEnvDir = [io.path]::combine($implementationDir, ".adi", "environments")
  $monoImplSettingsJsonFilename = [io.path]::combine($monoConfDir, "implSettings.json")
  $monoImplSettingsJsonTmpFilename = [io.path]::combine($monoDir, "..", "implSettings.json")

  $implEnvLocalJsonFilename = $null
  if (($Layer -eq "generali-hu") `
    -or ($Layer -eq "signal") `
    -or ($Layer -eq "re") `
    -or ($Layer -eq "triglav-si") `
  ) {
    $implEnvLocalJsonFilename = "environment.local.json"
  } else {
    $implEnvLocalJsonFilename = "environment.local.$Layer.json"
  }
  $implEnvLocalJsonPath = [io.path]::combine($adiEnvDir, $implEnvLocalJsonFilename)

  if (!(Test-Path $implementationDir) -or !(Test-Path $monoDir) -or !(Test-Path $monoClientDir) -or !(Test-Path $implementationConfigurationDir)) {
    Write-Error "Wrong directory structure in $Root mono, mono\client and implementation dirs expected!" -ErrorAction Stop
  }

  if (Test-Path $monoImplSettingsJsonTmpFilename) {
    Run-Command "Move-Item -Destination $monoImplSettingsJsonFilename -Path $monoImplSettingsJsonTmpFilename -Force"  
  }

  Validate-Impl-Env-Local-Json `
    -Layer $Layer `
    -ImplEnvLocalJsonPath $implEnvLocalJsonPath `
    -MonoImplSettingsJsonFilename $monoImplSettingsJsonFilename

  if ($instructions.ValidateImplementationMasterBranch) {
    Validate-Implementation-Master-Branch `
      -ImplementationDir $implementationDir `
      -MasterBranchName $MasterBranchName
  }

  if ($instructions.ValidatePlatformVersion) {
    Validate-Platform-Version `
      -Dir $monoDir `
      -Desc "Mono" `
      -ImplementationDir $implementationDir
  }

  if ((Test-Path $basicDir) -and ($instructions.ValidateBasicVersion)) {
    Validate-Platform-Version `
      -Dir $basicDir `
      -Desc "Basic" `
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
      -ProcessName "Scheduler.Web.exe"
  }

  if ($instructions.StopMockIntegrationService) {
    Find-And-Stop-Process `
      -ProcessName "dotnet.exe" `
      -Command 'dotnet\.exe" run --project \.\\plugins\\MockIntegrationService\\MockIntegrationService\.csproj run --urls http://\*:60009 --verbosity n'     
  }

  if ($instructions.StopSimulatedDMS) {
    Find-And-Stop-Process `
      -ProcessName "dotnet.exe" `
      -Command 'dotnet\.exe" run --project \.\\plugins\\AdActaDMSSimulation\\AdActaDMSSimulatedServer\\AdActaDMSSimulatedServer\.csproj run --urls http://\*:60010 --verbosity n'     
  }

  Set-Location $Root

  if ($Clean) {

    # Run-Command "net stop docker"
    # Run-Command-Stop-On-Error "wsl --shutdown"
    # Run-Command-Stop-On-Error "net start docker"

    if ($CleanNodeModules) {
      Remove-Node-Modules -Dir $Root
    }

    Write-Output "Cleaning mono"

    Set-Location $monoDir

    try {
      Run-Command-Stop-On-Error "cp $monoImplSettingsJsonFilename $env:Temp"

      $gitStashOutput = Run-Command "git stash --include-untracked"
      Write-Output $gitStashOutput

      Run-Command "echo no | git clean -fdx -e node_modules"
      Run-Command "git reset --hard"

      if (!($gitStashOutput -match "No local changes to save")) {
        Run-Command-Stop-On-Error "git stash pop"
      }
    }
    finally {
      Run-Command-Stop-On-Error "cp $env:Temp\implSettings.json $monoImplSettingsJsonFilename"
    }

    Write-Output "Cleaning implementation"

    Set-Location $implementationDir

    $gitStashOutput = Run-Command "git stash --include-untracked"
    Write-Output $gitStashOutput

    Run-Command "echo no | git clean -fdx -e node_modules"
    Run-Command "git reset --hard"

    if (!($gitStashOutput -match "No local changes to save")) {
      Run-Command-Stop-On-Error "git stash pop"
    }

    if (!(Test-Path -Path $printoutAssetsDir)) {
      New-Item -Path $printoutAssetsDir -ItemType Directory
    }

    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f db_mssql_dev" `
      -Command 'docker run -p 1433:1433 --name db_mssql_dev -m 3g registry.adacta-fintech.com/adinsure/mono/ops/mssql:empty' `
      -SuccessCheck "SQL Server is now ready for client connections\. This is an informational message; no user action is required" `
      -Retry `
      -ErrorCheck "(The requested resource is in use)|(Error waiting for container: failed to shutdown container)"

    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f signal_pdf" `
      -Command "docker run -p 9423:9423 --name signal_pdf -v `"${printoutAssetsDir}:/assets/printout-assets`" --env JAVA_OPTIONS=`"-Xmx2g -Dcom.realobjects.pdfreactor.webservice.securitySettings.defaults.allowFileSystemAccess=true`" --platform=linux realobjects/pdfreactor:10" `
      -SuccessCheck "INFO: Started @\d+ms"


    # Start-Server-In-Background `
    #   -InitializationScript $sharedFunctions `
    #   -CleanUpCommand 'docker rm -f oracle' `
    #   -Command 'docker run -p 1521:1521 --name oracle registry.adacta-fintech.com/ops/infra/oracle-xe:18.4-1709' `
    #   -Retry
  }

  if ($Clean -or $instructions.CleanES) {
    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f es" `
      -Command 'docker run -p 9200:9200 -m 4g -e "discovery.type=single-node" --platform=linux --name es -h es elasticsearch:7.16.2' `
      -Retry `
      -SuccessCheck "Active license is now \[BASIC\]; Security is disabled" `
      -ErrorCheck "failure in a Windows system call: The virtual machine or container with the specified identifier is not running"    
  }

  if ($Clean -or $instructions.CleanAMQ) {
    Start-Server-In-Background `
      -InitializationScript $sharedFunctions `
      -CleanUpCommand "docker rm -f amq" `
      -Command 'docker run -p 61616:61616 -p 8161:8161 --platform=linux -m 5g --name amq --env ACTIVEMQ_OPTS="-Xms4g -Xmx5g -DXmx=1024m -DXss=600k" rmohr/activemq:5.15.9' `
      -Retry `
      -SuccessCheck "INFO \| jolokia-agent: Using policy access restrictor classpath:\/jolokia-access.xml" `
      -ErrorCheck "encountered an error during hcsshim::System::waitBackground: failure in a Windows system call: The virtual machine or container with the specified identifier is not running"  
  }  

  Set-Location $monoDir

  if ($instructions.BuildAdInsureServer) {
    if ($Layer -ne "re") {
      Run-Command-Stop-On-Error ".\build.ps1 -Build -SkipBasic"
    } else {
      Run-Command-Stop-On-Error ".\build.ps1 -Build"
    }
  }
  
  if ($instructions.RestoreDatabase) {
    if (($Layer -eq "generali-hu") `
      -or ($Layer -eq "signal") `
      -or ($Layer -eq "triglav-si") `
    ) {
      Run-Command-Stop-On-Error ".\build.ps1 -Restore -DatabaseType MSSQL -SkipBasic"
    } elseif ($Layer -eq "re") {
      Run-Command-Stop-On-Error ".\build.ps1 -Restore -DatabaseType MSSQL"
    } else {
      Run-Command-Stop-On-Error ".\build.ps1 -Restore -DatabaseType Oracle -SkipBasic -DatabaseOracleSID ORCLCDB"
    } 
  }

  Set-Location $implementationDir

  if ($instructions.BuildImplementation) {
    Run-Command-Stop-On-Error ".\build.ps1 -Build -TargetLayer $Layer"
  }

  if ($instructions.ExecuteImplementationDatabaseScripts) {
    Run-Command-Stop-On-Error ".\build.ps1 -ExecuteScripts -TargetLayer $Layer"
    # Write-Error "FAILED!" -ErrorAction Stop
  }
  
  if ($instructions.InstallImplementationNodePackages) {
    # if ($InstallImplementationNodePackagesOnly) {
    #   Remove-Node-Modules -Dir $implementationDir
    # }

    do {
      $runAgain = $false
      Run-Command "yarn install" 2>&1 | Tee-Object -Variable yarnInstallOutput
      
      # Write-Output "====================================================="
      # Write-Output $yarnInstallOutput
      # Write-Output "====================================================="

      if ( `
        ($yarnInstallOutput -match "401 Unauthorized") `
        -or ($yarnInstallOutput -match "error Couldn't find package") `
      ) {
        $runAgain = $true
      }
      elseif ($LASTEXITCODE -ne 0) {
        Write-Error "FAILED!" -ErrorAction Stop
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

  if ($instructions.ClearAdInsureServerLogs) {
    Write-Output "Clearing adinsure logs"
    do {
      $runAgain = $false
      
      try {
        Remove-Item "$([io.path]::combine($adinsureServerLogsDir, "adInsure.log"))"
      }
      catch {
        $runAgain = $true
        Start-Sleep 1
      }
    } while ($runAgain)
  }

  if ($instructions.StartAdInsureServer) {
    Start-Adinsure-Server-In-Background `
      -MonoDir $monoDir `
      -InitializationScript $sharedFunctions
  }

  if (($Layer -eq 'signal') -and $instructions.StartMockIntegrationService) {
    Start-Server-In-Background `
      -Command ".\build.ps1 -RunMockService 2>&1" `
      -SuccessCheck "Content root path:.*?plugins\\MockIntegrationService\\" `
      -ErrorCheck "The plugin credential provider could not acquire credentials\. Authentication may require manual action\." `
      -Dir $implementationDir `
      -InitializationScript $sharedFunctions
  }

  if (($Layer -eq 'signal') -and $instructions.StartSimulatedDMS) {
    Start-Server-In-Background `
      -Command ".\build.ps1 -RunSimulatedDMS 2>&1" `
      -SuccessCheck "Content root path:.*?plugins\\AdActaDMSSimulation\\" `
      -ErrorCheck "The plugin credential provider could not acquire credentials\. Authentication may require manual action\." `
      -Dir $implementationDir `
      -InitializationScript $sharedFunctions
  }

  if ($instructions.ValidateWorkspace) {
    Run-Command-Stop-On-Error "yarn run validate-workspace -e $implEnvLocalJsonFilename"
    # Run-Command-Stop-On-Error "yarn run translate-workspace -e $implEnvLocalJsonFilename"
  }

  if ($instructions.PublishWorkspace) {

    do {
      $runAgain = $false
      $publishWorkspaceOutput = $null

      if ($ForcePublish) {
        Run-Command "yarn run publish-workspace -e $implEnvLocalJsonFilename -f 2>&1" | Tee-Object -Variable publishWorkspaceOutput
      }
      else {
        Run-Command "yarn run publish-workspace -e $implEnvLocalJsonFilename 2>&1" | Tee-Object -Variable publishWorkspaceOutput
      }
      
      # Write-Output "====================================================="
      # Write-Output $publishWorkspaceOutput
      # Write-Output "====================================================="

      # if ($publishWorkspaceOutput -match "There is already an object named") {
      #   $runAgain = $true
      # }
      # else
      if (($publishWorkspaceOutput -match "Could not create ADO\.NET connection for transaction") `
        -or ($publishWorkspaceOutput -match "ECONNREFUSED") `
        -or ($publishWorkspaceOutput -match "TimeoutError: Timeout awaiting 'request'") `
        -or ($publishWorkspaceOutput -match "failed, reason: socket hang up") `
        -or ($publishWorkspaceOutput -match "Invalid configuration: cacheMemoryLimitMegabytes") `
      ) {
        Stop-Adinsure-Server

        Start-Adinsure-Server-In-Background `
          -MonoDir $monoDir `
          -InitializationScript $sharedFunctions

        $runAgain = $true
      }
      elseif ($LASTEXITCODE -ne 0) {
        Write-Error "FAILED!" -ErrorAction Stop
      }
    } while ($runAgain)

    if (($publishWorkspaceOutput -match "MessageRoute") `
      -or $RestartAdInsureServerAfterPublish `
    ) {
      Stop-Adinsure-Server

      Start-Adinsure-Server-In-Background `
        -MonoDir $monoDir `
        -InitializationScript $sharedFunctions
    }
  }
  
  if ($instructions.ExecuteImplementationPostPublishDatabaseScripts `
    -and ($Layer -ne "generali-hu") `
    -and ($Layer -ne "re") `
    -and ($Layer -ne "triglav-si") `
  ) {
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

  if (Test-Path $schedulerRootDir) {
    if ($instructions.StartScheduler) {
      Start-Server-In-Background `
        -Command "dotnet run --project .\Scheduler.Web\" `
        -SuccessCheck "Microsoft\.Hosting\.Lifetime Application started\. Press Ctrl\+C to shut down\." `
        -Dir $schedulerSolutionDir `
        -InitializationScript $sharedFunctions

      if (Test-Path $implementationSchedulerDir1) {
        if ($instructions.PublishSchedulerJobs) {
          Set-Location $implementationSchedulerDir1
          Run-Command-Stop-On-Error ".\import.ps1"
        }
      }
    
      if (Test-Path $implementationSchedulerDir2) {
        if ($instructions.PublishSchedulerJobs) {
          Set-Location $implementationSchedulerDir2
          Run-Command-Stop-On-Error ".\import.ps1"
        }
      }
    }
  }
} finally {
  Set-Location $startingLocation
}

