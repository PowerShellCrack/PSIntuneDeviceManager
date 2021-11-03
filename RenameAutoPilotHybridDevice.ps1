
<#
.SYNOPSIS
    Renames device using specific naming convention

.DESCRIPTION
    Renames device using serial, chassis and office name ad naming convention

.EXAMPLE
    .\RenameAutoPilotHybridDevice.ps1

.NOTES
    Author		: Dick Tracy II <richard.tracy@microsoft.com>
	Source	    : https://www.powershellcrack.com/
    Version		: 1.0.0
    #Requires -Version 3.0
#>

<#
## STORE THESE STEPS ELSEWHERE
##*=============================================

#How to “Obfuscate" password (encrypt & decrypt)

#STEP 1 - create random passphase (256 AES). Save the output as a variable (copy/paste)
#NOTE: this key is unique; the same key must be used to decrypt
$AESKey = New-Object Byte[] 32
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($AESKey)
Write-host ('$AESKey = @(' + ($AESKey -join ",").ToString() + ')')

#STEP 2 - Encrypt password with AES key. Save the output as a variable (copy/paste)
$AESEncryptedPassword = ConvertTo-SecureString -String '!QAZ1qaz!QAZ1qaz' -AsPlainText -Force | ConvertFrom-SecureString -Key $AESKey
Write-host ('$ADEncryptedPassword = "' + $AESEncryptedPassword + '"')

#STEP 3 - Store as useable credentials; converts encrypted key into secure key for use (used in the script)
$SecurePass = $ADEncryptedPassword | ConvertTo-SecureString -Key $AESKey
$credential = New-Object System.Management.Automation.PsCredential($ADUser, $SecurePass)

#STEP 4 - Test password output (clear text) from creds
$credential.GetNetworkCredential().password

##*=============================================
#>

##*=============================================
##* Variables
##*=============================================
#Generate AES key
$AESKey = @(230,69,177,190,75,214,231,63,142,85,221,38,174,145,77,7,79,129,30,78,194,205,177,239,194,219,126,7,206,212,71,29)

#add username with domain
$ADUser = 'dtolab\sccm.svc'

#Encrypt password (use AESkey and steps above)
$ADEncryptedPassword = '76492d1116743f0423413b16050a5345MgB8ADAAWQBnADYAYwBsAEsANgBsADAARABEAHMATABGAEgAeQBGAEEASgBPAEEAPQA9AHwANwBhAGYANwBkAGYAZAAxADYAMgAzAGMAYwBlADkAMgBiADQAYgA2ADQAYQBjAGEAOQBlADkAZgBmADYAYgAwADMAZQBkAGIAMgBjADEAOQAxADMAZgBmADYANwBlADMANg
AyADAANAA0AGEAMQBiADkAMQA2ADUAZQA3ADkAMQAyADcAYQBmADYAZQAzAGYAMgAwAGQAOQA3ADEANQAzAGEAOQA4ADAAYwA1ADUAOAA4ADIAYwBjADAAZAA3ADMA'

$PrefixCheck = 'DTOLAB'
##*=============================================
##* FUNCTIONS
##*=============================================

Function Test-IsDomainJoined{
    <#
    .SYNOPSIS
        Determine is the device is domain joined or not

    .DESCRIPTION
        Determine is the device is domain joined or not

    .PARAMETER PassThru
        A switch to return the domain name instead of boolean

    .NOTES
        Author		: Dick Tracy II <richard.tracy@microsoft.com>
	    Source	    : https://www.powershellcrack.com/
        Version		: 1.0.0
    #>
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


Function Get-ADUserOffice {
    <#
    .SYNOPSIS
        Get Active directory users Office attribute

    .DESCRIPTION
        Get Active directory users Office attribute using adsisearcher

    .PARAMETER User
        Specify a users instead of list of users

    .PARAMETER AllProperties
        A switch to return to all properties of user instead of office

    .PARAMETER Credential
        Use alternate credentials when pulling AD objects

    .NOTES
        Author		: Dick Tracy II <richard.tracy@microsoft.com>
	    Source	    : https://www.powershellcrack.com/
        Version		: 1.0.0
    #>
    param(
        [parameter(Mandatory = $false)]
        [String]$User,
        [parameter(Mandatory = $false)]
        [switch]$AllProperties,
        [parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )

    #Define the Credential
    #$Credential = Get-Credential -Credential $Credential

    # Create an ADSI Search
    $Searcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher

    # Get only the Group objects
    $Searcher.Filter = "(objectCategory=User)"

    # Limit the output to 50 objects
    $Searcher.SizeLimit = 0
    $Searcher.PageSize = 10000

    # Get the current domain
    $DomainDN = $(([adsisearcher]"").Searchroot.path)

    If($Credential){
        # Create an object "DirectoryEntry" and specify the domain, username and password
        $Domain = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList $DomainDN,$($Credential.UserName),$($Credential.GetNetworkCredential().password)
    }

    # Add the Domain to the search
    #$Searcher.SearchRoot = $Domain

    #set the properties to parse
    $props=@('displayname','userprincipalname','givenname','sn','samaccountname','physicaldeliveryofficename','objectsid')
    [void]$Searcher.PropertiesToLoad.AddRange($props)

    $Results = @()
    # Execute the Search; build object with properties
    $Searcher.FindAll() | %{
         Try{
             $Object = New-Object PSObject -Property @{
                DisplayName = $($_.Properties.displayname)
                UserPrincipalName = $($_.Properties.userprincipalname)
                GivenName = $($_.Properties.givenname)
                SamAccountName = $($_.Properties.samaccountname)
                Surname=$($_.Properties.sn)
                Office=$($_.Properties.physicaldeliveryofficename)
                SID=(new-object System.Security.Principal.SecurityIdentifier $_.Properties.objectsid[0],0).Value
                DN=$_.Path
            }
            $Results += $Object
        }
        Catch{
            #unable to grab attributes
        }
    }

    #return user and properties if specified
    If($User){
        If($AllProperties){
            $Results | Where SamAccountName -eq $User
        }Else{
            $Results | Where SamAccountName -eq $User | Select -ExpandProperty Office
        }
    }
    Else{
        If($AllProperties){
            $Results
        }Else{
            $Results | Select -ExpandProperty Office
        }
    }
}

##*=============================================
##* MAIN
##*=============================================
Write-Host "Grabbing computer information...."
#get bios information and serial
$Bios = Get-WMIObject -Class Win32_Bios
#grab computer details
$System = Get-WMIObject -Class Win32_ComputerSystemProduct
#get chassis information
$Enclosure = Get-WMIObject -Class Win32_SystemEnclosure

#if the computer name does not start with the prefix check, assume computer is renamed properly and exit process
If($env:COMPUTERNAME -notmatch "^$PrefixCheck"){
    Write-Host ("Device name [{0}] does not start with [{1}], no need to continue." -f $env:COMPUTERNAME, $PrefixCheck)
    Exit 0
    #Break
}

Write-Host "Determining Chassis type abbreviation..."
#determine the type of device
#lenovo will always default
If($System.Name -match 'Lenovo'){
    $Type='L'
}
Else
{
    #get the chassis type and determine the type value
    Switch ($Enclosure.ChassisTypes)
    {
        "1" {$Type="L"} #Other
        "2" {$Type="D"} #Virtual Machine
        "3" {$Type="D"} #Desktop
        "4" {$Type="D"} #Low Profile Desktop
        "5" {$Type="D"} #Pizza Box
        "6" {$Type="D"} #Mini Tower
        "7" {$Type="D"} #Tower
        "8" {$Type="L"} #Portable
        "9" {$Type="L"} #Laptop
        "10" {$Type="L"} #Notebook
        "11" {$Type="T"} #Handheld
        "12" {$Type="D"} #Docking Station
        "13" {$Type="L"} #All-in-One
        "14" {$Type="L"} #Sub-Notebook
        "15" {$Type="D"} #Space Saving
        "16" {$Type="D"} #Lunch Box
        "17" {$Type="D"} #Main System Chassis
        "18" {$Type="L"} #Expansion Chassis
        "19" {$Type="L"} #Sub-Chassis
        "20" {$Type="L"} #Bus Expansion Chassis
        "21" {$Type="L"} #Peripheral Chassis
        "22" {$Type="L"} #Storage Chassis
        "23" {$Type="L"} #Rack Mount Chassis
        "24" {$Type="D"} #Sealed-Case PC
        "30" {$Type="T"} #Tablet
        "31" {$Type="L"} #Convertible
        "32" {$Type="L"} #Detachable
        Default {$Type="L"} #Unknown
    }
}

#convert encrypted passwrd into secure string for creds
$SecurePass = $ADEncryptedPassword | ConvertTo-SecureString -Key $AESKey
$credential = New-Object System.Management.Automation.PsCredential($ADUser, $SecurePass)

Write-Host "Determining User Office abbreviation..."

$username = (gwmi win32_computersystem | select -ExpandProperty Username).split('\')[1]
#grab current users office attribute
$OfficeName = Get-ADUserOffice -User $username -Credential $creds

#convert office name into 2 char Abbreviation
switch($OfficeName){
    'DTREM' {$OfficeDN = 'RM'}
    'DTFIN' {$OfficeDN = 'FN'}
    'DTADM' {$OfficeDN = 'AD'}
    default {$OfficeDN = 'RM'}
}

#build new name; combining each value
[String]$NewComputername = [String]::Concat(($Bios.SerialNumber).ToUpper(),'-', $OfficeDN, $Type)


#Attempt to Rename device
Try{
    Rename-Computer -ComputerName $env:ComputerName -NewName $NewComputername -DomainCredential $creds -force -ErrorAction Stop
}Catch{
    Throw $_.Exception.Message
}
