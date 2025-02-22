
$packageid = "nexus-repository"
$version = '3.19.1-01'
$url = "https://download.sonatype.com/nexus/3/nexus-$version-win64.zip"
$checksum = '44B8D1175932EE95B4D8CC06AE5F15DFA609AF0B'
$checksumtype = 'SHA1'
$silentargs = "-q -console -dir `"$installfolder`""
$validExitCodes = @(0)

$packageName= 'nexus-repository'
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$OSBits = Get-ProcessorBits

If (!(Get-ProcessorBits -eq 64))
{
  Throw "Sonatype Nexus Repository 3.0 and greater only supports 64-bit Windows."
}

$nexusversionedfolder = "nexus-$version"
$TargetFolder = "$env:programdata\nexus"
$ExtractFolder = "$env:temp\NexusExtract"
$TargetDataFolder = "$env:programdata\sonatype-work"
$NexusConfigFile = "$TargetDataFolder\nexus3\etc\nexus.properties"
$servicename = 'nexus'
$NexusPort = '8081'

$pp = Get-PackageParameters
  
if ($pp.Port) {
  $NexusPort = $pp.Port
  Write-Host "/Port was used, Nexus will listen on port $NexusPort."
}

If (Test-Path "$env:ProgramFiles\nexus\bin")
{
  Throw "Previous version of Nexus 3 installed by setup.exe is present, please uninstall before running this package."
}

If ([bool](Get-Service $servicename -ErrorAction SilentlyContinue))
{
  Write-Warning "Nexus web app is already present, shutting it down so that we can upgrade it."
  Stop-Service $servicename -force
}

If (Test-Path "$ExtractFolder") {Remove-Item "$ExtractFolder" -Recurse -Force}

Install-ChocolateyZipPackage -PackageName $packageName -unziplocation "$ExtractFolder" -url $url -checksum $checksum -checksumtype $checksumtype -url64 $url -checksum64 $checksum -checksumtype64 $checksumtype

Write-Host "Copying files to '$TargetFolder' with overwrite"
#$VerbosePreference = Continue
Copy-Item "$ExtractFolder\$nexusversionedfolder" "$TargetFolder" -Force -Recurse
#$VerbosePreference = SilentlyContinue

If (!(Test-Path "$TargetDataFolder"))
{
  Move-Item "$extractfolder\sonatype-work" "$TargetDataFolder"
}
else 
{
  Write-Warning "`"$TargetDataFolder`" already exists, not overwriting, residual data from previous installs will not be reset."
}

Remove-Item "$ExtractFolder" -Force -Recurse

Start-ChocolateyProcessAsAdmin -ExeToRun "$TargetFolder\bin\nexus.exe" -Statements "/install $servicename" -validExitCodes $validExitCodes

#Update Port
If ($NexusPort -ne '8081')
{
  $service = Start-Service $servicename -PassThru
  $Service.WaitForStatus('Running', '00:02:00')
  Start-Sleep 120
  If (Test-Path "$NexusConfigFile")
  {
    Write-Host "Configuring Nexus to listen on port $NexusPort."
    (Get-Content "$NexusConfigFile") -replace "^#\s*application-port=.*$", "application-port=$NexusPort" | Set-Content "$NexusConfigFile"
    Stop-Service $servicename
  }
  else 
  {
    Write-Warning "Cannot find `"$NexusConfigFile`", skipping configuring Nexus to listen on port $NexusPort."
  }
}

$service = Start-Service $servicename -PassThru
Write-Host "Waiting for Nexus service to be completely ready"
$Service.WaitForStatus('Running', '00:02:00')

If ($Service.Status -ine 'Running') 
{
  Write-Warning "The Nexus Repository service ($servicename) did not start."
}
else 
{
  #Even though windows reports service is ready - web url will not respond until Nexus is actually ready to serve content
  Start-Sleep 120
}


$generatedadminpasswordfile = "$TargetDataFolder\nexus3\admin.password"
If (Test-Path $generatedadminpasswordfile) {
  $passwddata = Get-Content $generatedadminpasswordfile
}


Write-Warning "`r`n"
Write-Warning "*******************************************************************************************"
Write-Warning "*"
Write-Warning "*  You MAY receive the error 'localhost refused to connect.' until Nexus is fully started."
Write-Warning "*"
Write-Warning "*  For new installs, you must login as admin to complete some setup steps"
Write-Warning "*  You can manage the repository by typing 'start http://localhost:$NexusPort'"
Write-Warning "*"
Write-Warning "*  The default user is 'admin'"
Write-Warning "*  ADMIN PASSWORD:"
Write-Warning "*    NEW INSTALLS: The password generated for your instance is recorded"
Write-Warning "*       in '$generatedadminpasswordfile'"
Write-Warning "*    UPGRADES/REINSTALLS: If you upgraded (or uninstalled and reinstalled) without cleaning"
Write-Warning "*      up $TargetDataFolder - the password will be the same as it was before and the password file"
Write-Warning "*      will not exist."
Write-Warning "*    RESET PASSWORD WITH INSTALL: Uninstall Nexus and remove the directory '$TargetDataFolder'"
Write-Warning "*      and then reinstall.  This time a password file will be generated."
Write-Warning "*"
Write-Warning "*  Nexus availability is controlled via the service `"$servicename`""
Write-Warning "*  Use the following command to open port $NexusPort for access from off this machine (one line):"
Write-Warning "*   netsh advfirewall firewall add rule name=`"Nexus Repository`" dir=in action=allow "
Write-Warning "*   protocol=TCP localport=$NexusPort"
Write-Warning "*******************************************************************************************"
