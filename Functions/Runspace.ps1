
Function Get-RunspaceIntuneDevices{

    <#
    .SYNOPSIS
    This function is used to get Intune Managed Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Intune Managed Device
    .EXAMPLE
    Get-RunspaceIntuneDevices
    Returns all managed devices but excludes EAS devices registered within the Intune Service
    .EXAMPLE
    Get-RunspaceIntuneDevices -IncludeEAS
    Returns all managed devices including EAS devices registered within the Intune Service
    .NOTES
    NAME: Get-RunspaceIntuneDevices
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [hashtable]$Runspace,

        [Parameter(Mandatory=$true)]
        [hashtable]$ParentRunspace,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Windows','Android','MacOS','iOS')]
        [string]$Platform,

        [Parameter(Mandatory=$false)]
        [string]$Filter,

        [Parameter(Mandatory=$false)]
        [Alias('IncludeEAS')]
        [switch]$All,

        [Parameter(Mandatory=$false)]
        [switch]$ExcludeMDM,

        [Parameter(Mandatory=$false)]
        [switch]$Expand,

        [Parameter(Mandatory=$false)]
        $ListObject
    )

    Update-UIProgress -Runspace $Runspace -StatusMsg ("Retrieving Device list...") -Indeterminate

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/managedDevices"

    $filterQuery=$null

    if($All.IsPresent){ $Count_Params++ }
    if($ExcludeMDM.IsPresent){ $Count_Params++ }

    if($Count_Params -gt 1){
        write-warning "Multiple parameters set, specify a single parameter -All, -ExcludeMDM or no parameter against the function"
        break
    }

    $OrQuery = @()
    $AndQuery = @()

    If($All){
        #include all queries by leaving filter empty
    }
    Elseif($ExcludeMDM){
        $OrQuery += "managementAgent eq 'configurationManagerClientEas'"
        $OrQuery += "managementAgent eq 'easIntuneClient'"
        $OrQuery += "managementAgent eq 'eas'"
    }
    Else{
        $OrQuery += "managementAgent eq 'configurationManagerClientMdm'"
        $OrQuery += "managementAgent eq 'configurationManagerClient'"
        $OrQuery += "managementAgent eq 'intuneClient'"
        $OrQuery += "managementAgent eq 'mdm'"
        $OrQuery += "managementAgent eq 'easMdm'"
    }

    If($PSBoundParameters.ContainsKey('Filter')){
        #TEST $Filter = '46VEYL1'
        $AndQuery += "contains(deviceName,'$($Filter)')"
    }

    #TEST $Platform = 'Windows'
    If($PSBoundParameters.ContainsKey('Platform')){
        $AndQuery += "operatingSystem eq '$($Platform)'"
    }

    #append ?$filter once, then apply orquery and andquery
    If($OrQuery -or $AndQuery){
        $filterQuery = @('?$filter=')
        If($OrQuery.count -ge 1){
            $filterQuery += "(" + ($OrQuery -join ' or ') + ")"
        }
        If($filterQuery.count -ge 2 -and $AndQuery.count -ge 1){
            $filterQuery += ' and '
        }
        If($AndQuery.count -ge 1){
            $filterQuery += "(" + ($AndQuery -join ' and ') + ")"
        }
        $filterQuery = $filterQuery -join ''
    }Else{
        $filterQuery = $null
    }

    $allPages = @()

    $uri = "$Global:GraphEndpoint/$graphApiVersion/$Resource" + $filterQuery

    Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

    $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
        try {
            #$runspace = $syncHash
            #Using -Passthru with Invoke-IDMGraphRequests will out graph data including next link and context. Value contains devices. No Passthru will out value only
            $Runspace.GraphData.MDMDevices = (Invoke-IDMGraphRequests -Uri $uri -ErrorAction Stop)
        }
        catch {
            Update-UIProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Color Red
            Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Type Error
        }
    })

    If($Expand)
    {
        $i=0
        $Devices = @()
        #Populate AAD devices using splat for filter and platform to minimize seach field
        # this is becuse if results are more than gropah will show, the results coudl be skewed.

        $AzureDeviceParam = @{
            Runspace=$Runspace
            ParentRunspace=$Runspace
        }
        If($PSBoundParameters.ContainsKey('Filter')){
            $AzureDeviceParam += @{Filter = $Filter}
        }
        If($PSBoundParameters.ContainsKey('Platform')){
            $AzureDeviceParam += @{Platform = $Platform}
        }

        Get-RunspaceAzureDevices @AzureDeviceParam

        #collect stale objects
        $StaleDate = (Get-Date).AddDays(-90)
        $StaleObj = $AADObjects | Where {$_.approximateLastSignInDateTime -le $StaleDate}

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{

            $Runspace.Data.IntuneDevices = @()

            #TEST $Resource = $Response | Where deviceName -eq 'DTOLAB-46VEYL1'
            Foreach($Resource in $Runspace.GraphData.MDMDevices)
            {
                $i++
                If($PSBoundParameters.ContainsKey('ListObject'))
                {
                    Update-UIProgress -Runspace $Runspace -PercentComplete ($i/$Runspace.GraphData.MDMDevices.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$Runspace.GraphData.MDMDevices.count,$Resource.deviceName)
                    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Resource.deviceName,$ListObject.Name) -Type Info
                    $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                        $ListObject.Items.Add($Resource.deviceName) | Out-Null
                    })
                }

                $OutputItem = New-Object PSObject
                #first add all properties of Intune device
                Foreach($p in $Resource | Get-Member -MemberType NoteProperty){
                    $OutputItem | Add-Member NoteProperty $p.name -Value $Resource.($p.name)
                }

                #TEST $LinkedIntuneDevice = $Runspace.GraphData.AADDevices | Where displayName -eq 'DTOLAB-46VEYL1'
                If($LinkedIntuneDevice = $Runspace.GraphData.AADDevices | Where deviceId -eq $Resource.azureADDeviceId){

                    Foreach($p in $LinkedIntuneDevice | Get-Member -MemberType NoteProperty){
                        switch($p.name){
                            'id' {$OutputItem | Add-Member NoteProperty "azureADObjectId" -Value $LinkedIntuneDevice.($p.name) -Force}
                            'deviceMetadata' {<#For internal use only.#>}
                            'alternativeSecurityIds' {<#For internal use only.#>}
                            default {$OutputItem | Add-Member NoteProperty $p.name -Value $LinkedIntuneDevice.($p.name) -Force}
                        }
                    }
                    # Add the object to our array of output objects
                }
                $Runspace.Data.IntuneDevices += $OutputItem
            }
        })
    }
    Else{
        If($PSBoundParameters.ContainsKey('ListObject'))
        {

            $i=0
            Foreach($Device in $Devices.Where({ $null -ne $_ }))
            {
                $i++
                Update-UIProgress -Runspace $Runspace -PercentComplete ($i/$Devices.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$Devices.count,$Device.deviceName)
                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Device.deviceName,$ListObject.Name) -Type Info
                $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                    $ListObject.Items.Add($Device.deviceName) | Out-Null
                })
            }

        }
        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            $Runspace.Data.IntuneDevices = @()
            $Runspace.Data.IntuneDevices = $Runspace.GraphData.MDMDevices
        })
    }

    #Update-UIProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Added {0} items to list" -f $Devices.count) -Color Green
    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Found {0} devices" -f $Devices.count) -Type Info

    #return $Devices.Where({ $null -ne $_ })
    #$Runspace.Data.IntuneDevices = @()
    #$Runspace.Data.IntuneDevices += $Devices.Where({ $null -ne $_ })
}



Function Get-RunspaceAzureDevices{
    <#
    .SYNOPSIS
    This function is used to get Azure Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Azure Device

    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [hashtable]$Runspace,

        [Parameter(Mandatory=$true)]
        [hashtable]$ParentRunspace,

        [Parameter(Mandatory=$false)]
        [ValidateSet('DisplayName','StartWithDisplayName','NOTStartWithDisplayName')]
        [string]$FilterBy = 'StartWithDisplayName',

        [Parameter(Mandatory=$false)]
        [string]$Filter,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Windows','Android','MacOS','iOS')]
        [string]$Platform,

        [switch]$Passthru
    )
    Begin{
        # Defining Variables
        $graphApiVersion = "beta"
        $Resource = "devices"

        If($FilterBy -eq 'SearchDisplayName' -and -NOT($Headers['ConsistencyLevel'])){
            $Headers += @{ConsistencyLevel = 'eventual'}
        }

        $filterQuery=$null
    }
    Process{
        $Query = @()

        If($PSBoundParameters.ContainsKey('Platform')){
            $Query += "operatingSystem eq '$($Platform)'"
        }

        If($PSBoundParameters.ContainsKey('Filter')){
             switch($FilterBy){
                'DisplayName' {$Query += "displayName eq '$Filter'";$Operator='filter'}
                'StartWithDisplayName' {$Query += "startswith(displayName, '$Filter')";$Operator='filter'}
                'NOTStartWithDisplayName' {$Query += "NOT startsWith(displayName, '$Filter')";$Operator='filter'}
                'SearchDisplayName' {$Query += "`"displayName:$Filter`"";$Operator='search'}
                default {$Query += "startswith(displayName, '$Filter')";$Operator='filter'}
            }
        }

        #build query filter if exists
        If($Query.count -ge 1){
            $filterQuery = "`?`$$Operator=" + ($Query -join ' and ')
        }

        $uri = "$Global:GraphEndpoint/$graphApiVersion/$Resource" + $filterQuery

        Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            try {
                #Using -Passthru with Invoke-IDMGraphRequests will out graph data including next link and context. Value contains devices. No Passthru will out value only
                $Runspace.GraphData.AADDevices = (Invoke-IDMGraphRequests -Uri $uri -Headers $Headers -ErrorAction Stop)
            }
            catch {
                Update-UIProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Color Red
                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Type Error
            }
        })
    }
    End{
        If($Passthru){
            return $Runspace.GraphData.AADDevices
        }
    }
}
