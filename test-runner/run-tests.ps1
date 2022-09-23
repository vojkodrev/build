param(
  [string]
  $TestDir = "C:\code\Signal\implementation\configuration\@config-signal\integration\test\api"
)

function Run-Command {
  param (
    [Parameter(Mandatory=$true)]
    [string]$Command
  )

  $currentLocation = Get-Location
  Write-Output "$currentLocation> $Command"

  Invoke-Expression $Command
}

function Run-Command-Stop-On-Error {
  param (
    [Parameter(Mandatory=$true)]
    [string]$Command
  )

  Run-Command -Command $Command
  $commandLastExitCode = $LASTEXITCODE

  if ($commandLastExitCode -ne 0) {
    Write-Error "FAILED!" -ErrorAction Stop
  }
}

$startingDir = Get-Location

try {
  Set-Location $TestDir

  node $PSScriptRoot\get-all-tests\get-all-tests.js -d $TestDir | ForEach-Object { 
    $testTitle = $_

    do {
      $runAgain = $false
      
      Run-Command "yarn run test-api -f `"$testTitle`"" | Tee-Object -Variable testApiOutput

      if ($testApiOutput -match "Service operation error: Oneway timed out after 1000 milliseconds") {

        Run-Command "docker stop amq"
        Run-Command-Stop-On-Error "docker start amq"
        Run-Command-Stop-On-Error "C:\code\build-sava\build.ps1 -Root C:\code\Signal\ -Layer signal -StartServersOnly -DontValidateImplementationMasterBranch"

        $runAgain = $true
      }
    } while ($runAgain)
  }
}
finally {
  Set-Location $startingDir
}

