param (
   [ValidateSet("sqlcmd","sqlpackage", "docker")]
   [string[]]$Install,
   [string]$SaPassword
)

if ("docker" -in $Install) {
   Write-Output "docker install"
   if ($ismacos) {
      brew cask install docker
      # allow the app to run without confirmation
      xattr -d -r com.apple.quarantine /Applications/Docker.app

      # preemptively do docker.app's setup to avoid any gui prompts
      sudo /bin/cp /Applications/Docker.app/Contents/Library/LaunchServices/com.docker.vmnetd /Library/PrivilegedHelperTools
      sudo /bin/cp /Applications/Docker.app/Contents/Resources/com.docker.vmnetd.plist /Library/LaunchDaemons/
      sudo /bin/chmod 544 /Library/PrivilegedHelperTools/com.docker.vmnetd
      sudo /bin/chmod 644 /Library/LaunchDaemons/com.docker.vmnetd.plist
      sudo /bin/launchctl load /Library/LaunchDaemons/com.docker.vmnetd.plist
      open -g -a Docker.app
      Start-Sleep 5
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
   }

   if ($islinux) {
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
   }

   if ($iswindows) {
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d microsoft/mssql-server-windows-developer
   }
   
   Write-Output "Waiting for docker to start"
   Start-Sleep -Seconds 10
}

if ("sqlcmd" -in $Install) {
   Write-Output "sqlcmd install"
   
}

if ("sqlpackage" -in $Install) {
   Write-Output "sqlpackage install"
   Write-Output "jk"
}