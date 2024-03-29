[CmdletBinding(SupportsShouldProcess=$true)]
param ( 
	[Parameter(Mandatory=$true)]
	[string] $webApp,
	
	[Parameter(Mandatory=$true)]
	[string[]] $features
)

foreach ( $feature in $features ) 	{
	Disable-SPFeature -Identity $feature -Url $webApp -Confirm:$false -Verbose
    Start-Sleep 1 
	Enable-SPFeature -Identity $feature -Url $webApp -Verbose 
}

$servers = Get-SPServer | where { $_.Role -ne "Invalid" } | Select -Expand Address 

Invoke-Command -computer $servers -ScriptBlock {
	Write-Host "Restarting IIS on $ENV:COMPUTERNAME"
	iisreset 
	Restart-Service sptimerv4 -verbose
}
	