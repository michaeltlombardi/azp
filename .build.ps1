<#
.SYNOPSIS
  Build tasks for the project to ease local flows.
.DESCRIPTION
  This script is used with `Invoke-Build` as a unified interface to project workflows.
  For the hugo tasks, it checks to see if a valid version of hugo is available before
  attempting to build or serve the site.
.EXAMPLE
  Invoke-Build

  Builds the site in the public folder.
.EXAMPLE
  Invoke-Build -Task Clean

  Removes the public folder and all files in it.
.EXAMPLE
  Invoke-Build -Task Serve

  Starts a live server that watches for changes, making site available at https://localhost:1313
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Script:Requirements = @{
  Hugo = @{
    Installed  = $false
    Extended   = $false
    Version    = $null
    CommitHash = $null
    Platform   = $null
    BuildDate  = $null
    VendorInfo = $null
  }
}

$Script:HugoOutputFolder = "$PSScriptRoot/public"

$Script:HugoVersionPattern = @(
  '^hugo '                       # App name, always beginning of line
  'v?(?<Version>\d+\.\d+\.\d+)'  # Version is always three digits, may be prepended by a v
  '-(?<CommitHash>\w+)'          # Commit hash always follows version
  '(?<Extended>\+extended)?'     # Hugo may be extended, but it may not
  ' (?<Platform>(\w|\/)+)'       # Platform is usually os/architecture
  ' BuildDate=(?<BuildDate>\S+)' # Build Date is ISO8601
  ' VendorInfo=(?<Vendor>\w+)'   # Always includes vendor, only gohugoio is official
) -join ''

$Script:LastLineEmpty = $false

task Clean {
  if (Test-Path -Path $Script:HugoOutputFolder) {
    Remove-Item -Path $Script:HugoOutputFolder -Recurse -Force
  }
}

Function Write-ConsoleLog {
  [CmdletBinding(DefaultParameterSetName = 'Text')]
  param(
    [parameter(Mandatory, ParameterSetName = 'Text')]
    [AllowEmptyString()]
    [string[]]$Text,

    [parameter(ParameterSetName = 'Text')]
    [hashtable]$TextStyle,

    [parameter(ParameterSetName = 'Object')]
    [object[]]$InputObject,

    [parameter(ParameterSetName = 'Object')]
    [ValidateSet('List', 'Table')]
    [string]$ObjectFormatter = 'List',

    [parameter(ParameterSetName = 'Object')]
    [hashtable]$ObjectStyle
  )

  begin {
    $EolPattern = "(`r`n|`r|`n)"

    if ($TextStyle.Count -eq 0) {
      $TextStyle = @{
        Emphasis = $PSStyle.Italic
        Color    = $PSStyle.Foreground.BrightCyan
      }
    }

    if ($ObjectStyle.Count -eq 0) {
      $ObjectStyle = @{
        Header = $PSStyle.Bold + $PSStyle.Foreground.BrightCyan
        Body   = $PSStyle.Foreground.BrightYellow
      }
    }
  }

  process {
    if ($Text.Count) {
      $Text | ForEach-Object -Process {
        [string[]]$Lines = $_ -match $EolPattern ? ($_ -split $EolPattern) : $_

        foreach ($Line in $Lines) {
          if ([string]::IsNullOrEmpty($Line)) {
            if (!$Script:LastLineEmpty) {
              $Script:LastLineEmpty = $true
              $Line
            }
          } else {
            $Script:LastLineEmpty = $false
            if ($Line -match '(\||\+)') {
              $TextStyle.Color + "`t$Line" + $PSStyle.Reset
            } else {
              $TextStyle.Emphasis + $TextStyle.Color + "`t$Line" + $PSStyle.Reset
            }
          }
        }
      }
    } else {
      $InputObject | ForEach-Object -Process {
        $IO = $_
        switch ($ObjectFormatter) {
          'List' { $IO | Format-List }
          'Table' { $IO | Format-Table }
        }
      } | Out-String -Stream | ForEach-Object -Process {
        if ([string]::IsNullOrEmpty($_)) {
          if (!$Script:LastLineEmpty) {
            $Script:LastLineEmpty = $true
            $_
          }
        } else {
          $Script:LastLineEmpty = $false
          $Parts = ([System.Management.Automation.Internal.StringDecorated]$_).ToString('PlainText') -split '(\s+:\s+)', 3
          @(
            "`t$($ObjectStyle.Header)$($Parts[0..1] -join '')$($PSStyle.Reset)"
              ($PSStyle.Foreground.Yellow + $Parts[2] + $PSStyle.Reset)
          ) -join ''
        }
      }
    }
  }
}

task Build Clean, CheckHugo, {
  exec { hugo } | ForEach-Object {
    if ($_ -match $Script:HugoVersionPattern) {
      Write-ConsoleLog -InputObject ([pscustomobject]$Script:Requirements.Hugo)
    } else {
      Write-ConsoleLog -Text $_
    }
  }
}

task Serve Clean, CheckHugo, {
  exec { hugo serve } | ForEach-Object {
    if ($_ -match $Script:HugoVersionPattern) {
      Write-ConsoleLog -InputObject ([pscustomobject]$Script:Requirements.Hugo)
    } else {
      Write-ConsoleLog -Text $_
    }
  }
}

task CheckHugo {
  if (Get-Command -Name hugo -CommandType Application -ErrorAction SilentlyContinue) {
    $Script:Requirements.Hugo.Installed = $true
    if ((hugo version) -match $HugoVersionPattern) {
      $Script:Requirements.Hugo.Extended = ![string]::IsNullOrEmpty($Matches.Extended)
      $Script:Requirements.Hugo.Version = $Matches.Version
      $Script:Requirements.Hugo.CommitHash = $Matches.CommitHash
      $Script:Requirements.Hugo.Platform = $Matches.Platform
      $Script:Requirements.Hugo.BuildDate = Get-Date -Date $Matches.BuildDate
      $Script:Requirements.Hugo.Vendor = $Matches.Vendor
    }
  }

  if (!$Script:Requirements.Hugo.Installed) {
    $Message = @(
      'hugo does not appear to be installed.'
      'Is it in the default path?'
      'If not, did you pass it to the **HugoPath** parameter?'
    ) -join ' '
    throw $Message
  } elseif (!$Script:Requirements.Hugo.Extended) {
    $Message = @(
      'hugo is installed but not the extended version.'
      'This site requires hugo extended for post-processing.'
      'Install hugo extended.'
      "If you don't install it in your default system path,"
      'make sure you pass it to the **HugoPath** parameter.'
    ) -join ' '
    throw $Message
  } else {
    $Message = @(
      $PSStyle.Bold + $PSStyle.Foreground.BrightMagenta + "`thugo extended" + $PSStyle.Reset
      'is installed at version'
      $PSStyle.Foreground.BrightYellow + $Script:Requirements.Hugo.Version + $PSStyle.Reset
    ) -join ' '
    $Message
  }
}

task . Build