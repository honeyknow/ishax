$svcName = "ISHAXAmsiWatcher"
sc.exe create $svcName binPath= "`"C:\path`"" start= auto obj= LocalSystem DisplayName= "ISHAX AMSI ETW Watcher" | Out-Null
