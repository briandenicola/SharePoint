param ( 
    [string[]] $servers,
    [string] $cert_subject,
    [switch] $export
    
)

$remove_pfx_sb = { 
    param( 
        [string] $subject,
        [switch] $export
    ) 
       
    . (Join-PATH $ENV:SCRIPTS_HOME "Libraries\Standard_Functions.ps1")
    
    if ( $export ) { 
        $pass = "abc123"
        $path = Join-Path "D:\Certs\" ($subject + "-export-" + (Get-Date).ToString("yyyyMMddmmhhss") + ".pfx")
        
        if ( -not (Test-Path "D:\Certs") ) { mkdir "D:\Certs" }
    
        Export-Certificate -subject $subject -pfxPass $pass -file $path
    }
    
    Remove-Certificate -subject $subject
}

$ans = Read-Host "This script will remove $cert_subject on the following servers - $servers.`n Do you wish to continue (y/n)"
if ( $ans -match "Y|y" ) { 
    Invoke-Command -Computer $servers -ScriptBlock $remove_pfx_sb -ArgumentList $cert_subject, $export
}
else { 
    Write-Host "Script has been canceled"
}