
#region FUNCTION: Check if running in ISE
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {
        return ($null -ne $psISE);
    }
    catch {
        return $false;
    }
}
#endregion

#region FUNCTION: Check if running in Visual Studio Code
Function Test-VSCode{
    if($env:TERM_PROGRAM -eq 'vscode') {
        return $true;
    }
    Else{
        return $false;
    }
}
#endregion

#region FUNCTION: Find script path for either ISE or console
Function Get-ScriptPath {
    <#
        .SYNOPSIS
            Finds the current script path even in ISE or VSC
        .LINK
            Test-VSCode
            Test-IsISE
    #>
    param(
        [switch]$Parent
    )

    Begin{}
    Process{
        if ($PSScriptRoot -eq "")
        {
            if (Test-IsISE)
            {
                $ScriptPath = $psISE.CurrentFile.FullPath
            }
            elseif(Test-VSCode){
                $context = $psEditor.GetEditorContext()
                $ScriptPath = $context.CurrentFile.Path
            }Else{
                $ScriptPath = (Get-location).Path
            }
        }
        else
        {
            $ScriptPath = $PSCommandPath
        }
    }
    End{

        If($Parent){
            Split-Path $ScriptPath -Parent
        }Else{
            $ScriptPath
        }
    }
}
#endregion

function Confirm-Elevated {
    $UserWP = New-Object Security.Principal.WindowsPrincipal( [Security.Principal.WindowsIdentity]::GetCurrent( ) )
    try {
        if ($UserWP.IsInRole( [Security.Principal.WindowsBuiltInRole]::Administrator )) {
            $WPFtxtElevated.Text = 'Yes'
		    $WPFtxtElevated.Foreground = '#FF0BEA00'
            Write-OutputBox -OutputBoxMessage "User has local administrative rights and was launched elevated" -Type "INFO: " -Object Tab1
            return $true
        }
        else {
            Write-OutputBox -OutputBoxMessage "The tool requires local administrative rights and was not launched elevated" -Type "ERROR: " -Object Tab1
            $WPFtxtElevated.Text = 'No'
            $WPFtxtElevated.Foreground = '#FFFF0000'
            return $false
        }
    }
    catch [System.Exception] {
        Write-OutputBox -OutputBoxMessage "An error occured when attempting to query for elevation, possible due to issues contacting the domain or the tool is launched in a sub-domain. If used in a sub-domain, check the override checkbox to enable this tool" -Type "WARNING: " -Object Tab1
    }
}

function Test-RSATModule {
    param(
	    [switch]$PassThru
	)
    $RSAT = Get-Module -list ActiveDirectory
    #Get-Command -module ActiveDirectory
    If ($RSAT) {
        If($PassThru){$RSAT.Version.ToString()}Else{return $true}
    } Else {
        return $false
    }
}

function Test-CMModule {
    #https://docs.microsoft.com/en-us/powershell/sccm/overview?view=sccm-ps
    param(
	    [string]$CMSite
	)
    $CMPath = 'C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin'

    If($null -ne $env:SMS_ADMIN_UI_PATH){
        #Set-Location "$env:SMS_ADMIN_UI_PATH\..\"
        #Import-Module .\ConfigurationManager.psd1
        Import-Module "$(Split-Path $env:SMS_ADMIN_UI_PATH)\ConfigurationManager"    # Imports ConfigMgr PowerShell module
    }
    $CM = Get-Module -Name ConfigurationManager
    #Get-Command -module ActiveDirectory
    If ($CM) {
        If($CMSite){
            Try{
                Set-Location "$CMSite`:"
                #New-PSDrive -Name $CMSite `
                #    -PSProvider "AdminUI.PS.Provider\$CMSite" `
                #    -Root $CMServer `
                #    -ErrorAction Stop
            }
            Catch{}
            Finally{
                $CM.Version
            }
        }Else{
            return $true
        }
    } Else {
        return $false
    }
}


function Get-ParameterOption {
    param(
        $Command,
        $Parameter
    )

    $parameters = Get-Command -Name $Command | Select-Object -ExpandProperty Parameters
    $type = $parameters[$Parameter].ParameterType
    if($type.IsEnum) {
        [System.Enum]::GetNames($type)
    } else {
        $parameters[$Parameter].Attributes.ValidValues
    }
}
#endregion

Function Get-RandomAlphanumericString {
	[CmdletBinding()]
	Param (
        [int] $length = 8
	)

	Begin{
	}
	Process{
        return ( -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count $length  | % {([char]$_).ToString().ToUpper()}) )
	}
}

Function Generate-RandomName{
    "$(Get-RandomAlphanumericString -length 3)$(Get-random -Minimum 1000000 -Maximum 9999999)$(Get-RandomAlphanumericString -length 2)"

}

Function Get-RandomNumericString {
	[CmdletBinding()]
	Param (
        [int]$length
	)

	If($length -eq 0){
	    Return $null
	}Else{
        return ( (1..$length) | ForEach-Object { Get-Random -Minimum 0 -Maximum 9 } ) -join ''
	}

}

Function Test-IsDomainJoined{
    param(
	    [switch]$PassThru
	)
    ## Variables: Domain Membership
    [boolean]$IsMachinePartOfDomain = (Get-WmiObject -Class 'Win32_ComputerSystem' -ErrorAction 'SilentlyContinue').PartOfDomain
    [string]$envMachineWorkgroup = ''
    [string]$envMachineADDomain = ''
    If ($IsMachinePartOfDomain) {
    	If($Passthru){
        	[string]$envMachineADDomain = (Get-WmiObject -Class 'Win32_ComputerSystem' -ErrorAction 'SilentlyContinue').Domain | Where-Object { $_ } | ForEach-Object { $_.ToLower() }
            return $envMachineADDomain
	    }Else{
            return $true
	    }
    }
    Else {
    	If($Passthru){
            [string]$envMachineWorkgroup = (Get-WmiObject -Class 'Win32_ComputerSystem' -ErrorAction 'SilentlyContinue').Domain | Where-Object { $_ } | ForEach-Object { $_.ToUpper() }
            return $envMachineWorkgroup

        }Else{
            return $false
        }
    }

}


Function Get-WellKnownOU{
    Param(
        [ValidateSet('Default Computers','Default Users','NTDS','Microsoft','Program Data','ForeignSecurityPrincipals','Deleted','Infrastructure','LostAndFound','System','Domain Controllers','Computers Root')]
        [string]$KnownOU
    )

    switch($KnownOU){
        'Default Computers'         {$ObjectID = 'B:32:AA312825768811D1ADED00C04FD8D5CD'}
        'Default Users'             {$ObjectID = 'B:32:A9D1CA15768811D1ADED00C04FD8D5CD'}
        'NTDS'                      {$ObjectID = 'B:32:6227F0AF1FC2410D8E3BB10615BB5B0F'}
        'Microsoft'                 {$ObjectID = 'B:32:F4BE92A4C777485E878E9421D53087DB'}
        'Program Data'              {$ObjectID = 'B:32:09460C08AE1E4A4EA0F64AEE7DAA1E5A'}
        'ForeignSecurityPrincipals' {$ObjectID = 'B:32:22B70C67D56E4EFB91E9300FCA3DC1AA'}
        'Deleted'                   {$ObjectID = 'B:32:18E2EA80684F11D2B9AA00C04F79F805'}
        'Infrastructure'            {$ObjectID = 'B:32:2FBAC1870ADE11D297C400C04FD8D5CD'}
        'LostAndFound'              {$ObjectID = 'B:32:AB8153B7768811D1ADED00C04FD8D5CD'}
        'System'                    {$ObjectID = 'B:32:AB1D30F3768811D1ADED00C04FD8D5CD'}
        'Domain Controllers'        {$ObjectID = 'B:32:A361B2FFFFD211D1AA4B00C04FD7D83A'}
        'Computers Root'            {$ObjectID = 'B:32:AB1D30F3768811D1ADED00C04FD8D5CD'}
        default                     {$ObjectID = 'B:32:AA312825768811D1ADED00C04FD8D5CD'}
    }

    $a = [adsisearcher]'(&(objectclass=domain))'
    $a.SearchScope = 'base'
    $a.FindOne().properties.wellknownobjects | ForEach-Object {

        if ($_ -match ('^' + $ObjectID + ':(.*)$'))
        {
            #$matches[1]
            $SearchOU = $matches[1]
        }
    }

    If($KnownOU -eq 'Computers Root'){
        return $SearchOU.replace('System','Computers')
    }Else{
        return $SearchOU
    }
}


Function Resolve-ActualPath{
    [CmdletBinding()]
    param(
        [string]$FileName,
        [string]$WorkingPath,
        [Switch]$Parent
    )

    Try{
        $FullPath = Resolve-Path $FileName -ErrorAction Stop
    }
    Catch{
        $FullPath = Join-Path -Path $WorkingPath -ChildPath $FileName
    }

    Try{
        $ResolvedPath = Resolve-Path $FullPath -ErrorAction $ErrorActionPreference
    }
    Catch{
        Throw ("{0}" -f $_.Exception.Message)
    }
    Finally{
        If($Parent){
            $Return = Split-Path $ResolvedPath -Parent
        }Else{
            $Return = $ResolvedPath
        }
        $Return
    }
}

Function Get-CMSiteCode{
    param(
        [string]$ComputerName = 'localhost'
    )
    Try{
        $([WmiClass]"\\$ComputerName\ROOT\ccm:SMS_Client").getassignedsite() | Select -ExpandProperty sSiteCode
    }
    Catch{

    }
}


Function ConvertTo-ByteString {
    Param(
    [Parameter(ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [long]$number
    )

    Begin{
        $sizes = 'B','KB','MB','GB','TB','PB'
    }
    Process {
        #
        if ($number -eq 0) {return '0 B'}
        $size = [math]::Log($number,1024)
        $size = [math]::Floor($size)
        $num = $number / [math]::Pow(1024,$size)
        $num = "{0:N2}" -f $num
        return "$num $($sizes[$size])"
        #
    }
    End{}
}
