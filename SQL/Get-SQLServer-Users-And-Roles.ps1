[CmdletBinding(SupportsShouldProcess=$true)]
param ( 
	[Parameter(Mandatory=$true)]	
    [string] $instance
)

$current_dir = $PWD.Path

. (Join-PATH $ENV:SCRIPTS_HOME "Libraries\Standard_Functions.ps1")
. (Join-PATH $ENV:SCRIPTS_HOME "Libraries\SharePoint_Functions.ps1")
Import-Module sqlps -EA Stop -DisableNameChecking

Set-Location $current_dir

$server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $instance

$users = @()
foreach( $database in $server.Databases ) {
    foreach( $user in ($database.Users | Where {!($_.IsSystemObject)} ) ) {
        $users += (New-Object PSObject -Property @{
            Login = $user.Login
            User = $user.Name
            Database = $database
            Roles = $user.EnumRoles()
            ObjectPermissions = $database.EnumObjectPermissions($user.Name)
        })
    }
} 

return $users

