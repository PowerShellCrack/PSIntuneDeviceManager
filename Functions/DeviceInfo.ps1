
#region FUNCTION: convert chassis Types to friendly name
Function ConvertTo-ChassisType{
    [CmdletBinding()]
    Param($ChassisId)
    Switch ($ChassisId)
        {
            "1" {$Type = "Other"}
            "2" {$Type = "Virtual Machine"}
            "3" {$Type = "Desktop"}
            "4" {$type = "Low Profile Desktop"}
            "5" {$type = "Pizza Box"}
            "6" {$type = "Mini Tower"}
            "7" {$type = "Tower"}
            "8" {$type = "Portable"}
            "9" {$type = "Laptop"}
            "10" {$type = "Notebook"}
            "11" {$type = "Handheld"}
            "12" {$type = "Docking Station"}
            "13" {$type = "All-in-One"}
            "14" {$type = "Sub-Notebook"}
            "15" {$type = "Space Saving"}
            "16" {$type = "Lunch Box"}
            "17" {$type = "Main System Chassis"}
            "18" {$type = "Expansion Chassis"}
            "19" {$type = "Sub-Chassis"}
            "20" {$type = "Bus Expansion Chassis"}
            "21" {$type = "Peripheral Chassis"}
            "22" {$type = "Storage Chassis"}
            "23" {$type = "Rack Mount Chassis"}
            "24" {$type = "Sealed-Case PC"}
            "30" {$type = "Tablet"}
            "31" {$type = "Convertible"}
            "32" {$type = "Detachable"}
            Default {$type = "Unknown"}
         }
    Return $Type
}
#endregion

#region FUNCTION: Grab all machine platform details
Function Get-PlatformInfo {
# Returns device Manufacturer, Model and BIOS version, populating global variables for use in other functions/ validation
# Note that platformType is appended to psobject by Get-PlatformValid - type is manually defined by user to ensure accuracy
    [CmdletBinding()]
    [OutputType([PsObject])]
    Param(
        [string]$DeviceName = 'localhost'
    )
    try{
        $CIMSystemEncloure = Get-CIMInstance Win32_SystemEnclosure -ComputerName $DeviceName -ErrorAction Stop
        $CIMComputerSystem = Get-CIMInstance CIM_ComputerSystem -ComputerName $DeviceName -ErrorAction Stop
        $CIMBios = Get-CIMInstance Win32_BIOS -ComputerName $DeviceName -ErrorAction Stop

        $ChassisType = ConvertTo-ChassisType -ChassisId $CIMSystemEncloure.chassistypes

        [boolean]$Is64Bit = [boolean]((Get-WmiObject -Class 'Win32_Processor' -ComputerName $DeviceName | Where-Object { $_.DeviceID -eq 'CPU0' } | Select-Object -ExpandProperty 'AddressWidth') -eq 64)
        If ($Is64Bit) { [string]$envOSArchitecture = '64-bit' } Else { [string]$envOSArchitecture = '32-bit' }

        New-Object -TypeName PsObject -Property @{
            "computerName" = [system.environment]::MachineName
            "computerDomain" = $CIMComputerSystem.Domain
            "platformBIOS" = $CIMBios.SMBIOSBIOSVersion
            "platformManufacturer" = $CIMComputerSystem.Manufacturer
            "platformModel" = $CIMComputerSystem.Model
            "AssetTag" = $CIMSystemEncloure.SMBiosAssetTag
            "SerialNumber" = $CIMBios.SerialNumber
            "Architecture" = $envOSArchitecture
            "Chassis" = $ChassisType
            }
    }
    catch{Write-Output "CRITICAL" "Failed to get information from Win32_Computersystem/ Win32_BIOS"}
}
#endregion


Function Get-NewDeviceName {
    param(
        [string]$Device,
        [string]$Query,
        [hashtable]$RegexRules,
        [ValidateSet('No Abbr','Chassis','Manufacturer','Model')]
        [string]$AbbrType,
        [string]$AbbrKey,
        [ValidateSet('Before Prefix','After Prefix','After Regex')]
        [string]$AbbrPos,
        [string]$Prefix,
        [int]$AddDigits,
        [ValidateSet('In Front','At End')]
        [string]$DigitPos
    )

    #grab regex rules and build array
    $regexArray = @()
    If($RegexRules.count -gt 0){
        If($RegexRules['RuleRegex1']){$regexArray += $RegexRules['RuleRegex1']}
        If($RegexRules['RuleRegex2']){$regexArray += $RegexRules['RuleRegex2']}
        If($RegexRules['RuleRegex3']){$regexArray += $RegexRules['RuleRegex3']}
        If($RegexRules['RuleRegex4']){$regexArray += $RegexRules['RuleRegex4']}
    
        $r=0
        #save query to working sample for processing
        $WorkingSample = $Query
    
        #loop through each regex rule to break apart working sample
        Foreach($Regex in $regexArray){
            $r++
            #$RegexResult = $RegexResult -match $Regex;$Matches[0]
            #if it is the last reqex rule, combine all reges results into one
            If($r -eq $regexArray.count){
                $RegexResult = [String]::Concat($WorkingSample,([regex]($Regex)).matches($Query).Value)
                If($RegexResult.count -gt 1){$RegexResult=$RegexResult | Select -First 1}
            }Else{
                $WorkingSample = ([regex]($Regex)).matches($WorkingSample).Value
            }
        }
        #Trim any beginning or ending spaces
        $RegexResult = $RegexResult.Trim()
    }
    Else{
        $RegexResult = $Query
    }

    If($PSBoundParameters.ContainsKey('AbbrKey')){
        $KeyLookup = $AbbrKey.split(',').Trim()
        $KeyArray = @{}
        Foreach($Type in $KeyLookup){
            $KeyArray.Add($Type.Split('=')[0],$Type.Split('=')[1])
        }
    }

    If([string]::IsNullOrEmpty($Device)){$Device = 'localhost'}
    switch($AbbrType){
        'Chassis' {
            If($PSBoundParameters.ContainsKey('AbbrKey')){
                $DeviceInfo = Get-PlatformInfo -DeviceName $Device
                $Abbr = $KeyArray[$DeviceInfo.Chassis]
            }Else{
                $Abbr = (Get-PlatformInfo -DeviceName $Device).Chassis.SubString(0,3).ToUpper()
            }
        }
        'Manufacturer' {
            If($PSBoundParameters.ContainsKey('AbbrKey')){
                $DeviceInfo = Get-PlatformInfo -DeviceName $Device
                $Abbr = $KeyArray[$DeviceInfo.platformManufacturer]
            }Else{
                $Abbr = (Get-PlatformInfo -DeviceName $Device).platformManufacturer.SubString(0,3).ToUpper()
            }
        }
        'Model' {
            If($PSBoundParameters.ContainsKey('AbbrKey')){
                $DeviceInfo = Get-PlatformInfo -DeviceName $Device
                $Abbr = $KeyArray[$DeviceInfo.platformModel]
            }Else{
                $Abbr = (Get-PlatformInfo -DeviceName $Device).platformModel.SubString(0,3).ToUpper()
            }
        }
        default {}
    }

    $Result = $null

    switch($AbbrPos){
        'Before Prefix'         {
            $Result = ($Abbr + $Prefix + $RegexResult)
        }
        'After Prefix'  {
            $Result = ($Prefix + $Abbr + $RegexResult)
        }
        'After Regex'          {
            $Result = ($Prefix + $RegexResult + $Abbr)
        }
        default{
            $Result = ($Prefix + $RegexResult)
        }
    }

    If($PSBoundParameters.ContainsKey('AddDigits')){
        switch($DigitPos){
            'In Front' {
                $Result = [String]::Concat((Get-RandomNumericString -length $AddDigits),$Result)
            }

            'At End' {
                $Result = [String]::Concat($Result,(Get-RandomNumericString -length $AddDigits))
            }
        }
    }

    #be sure to cut off last if longer than 15
    If($Result.length -gt 15){
        return $Result.subString(0, 15)
    }Else{
        return $Result
    }
}