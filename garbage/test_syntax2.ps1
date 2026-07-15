$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile("c:\cursor\weknows\latestedr\endpoint\endpoint_setup.ps1", [ref]$null, [ref]$errs)
if ($errs) { foreach ($e in $errs) { Write-Host "$($e.Message) at line $($e.Extent.StartLineNumber)" } } else { Write-Host "No syntax errors" }
