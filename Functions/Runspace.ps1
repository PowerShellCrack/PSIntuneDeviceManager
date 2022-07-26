
Function Get-IDMDeviceInRunspace{

    <#
    .SYNOPSIS
    This function is used to get Intune Managed Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Intune Managed Device
    .EXAMPLE
    Get-IDMDeviceInRunspace
    Returns all managed devices but excludes EAS devices registered within the Intune Service
    .EXAMPLE
    Get-IDMDeviceInRunspace -IncludeEAS
    Returns all managed devices including EAS devices registered within the Intune Service
    .NOTES
    NAME: Get-IDMDeviceInRunspace
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
        [switch]$IncludeEAS,

        [Parameter(Mandatory=$false)]
        [switch]$ExcludeMDM,

        [Parameter(Mandatory=$false)]
        [switch]$Expand,

        [Parameter(Mandatory=$false)]
        $ListObject,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )

    Update-IDMProgress -Runspace $Runspace -StatusMsg ("Retrieving Device list...") -Indeterminate

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/managedDevices"

    $Query = @()
    $Count_maParams = 0
    if($IncludeEAS.IsPresent){$Count_maParams++}

    if($ExcludeMDM.IsPresent){
        $Count_maParams++
        $Query += "managementAgent eq 'eas'"
    }

    if($IncludeEAS -eq $false -and $ExcludeMDM -eq $false){
        $Query += "managementAgent eq 'easmdm'"
        $Query += "managementAgent eq 'mdm'"
        Write-Warning "EAS Devices are excluded by default, please use -IncludeEAS if you want to include those devices"
    }

    If($PSBoundParameters.ContainsKey('Filter')){
        $Query += "contains(deviceName,'$($Filter)')"
    }

    If($PSBoundParameters.ContainsKey('Platform')){
        $Query += "operatingSystem eq '$($Platform)'"
    }

    $filterQuery = "`?`$filter=" + ($Query -join ' and ')


    if($Count_maParams -gt 1){
        write-error "Multiple parameters set, specify a single parameter -IncludeEAS, -ExcludeMDM or no parameter against the function"
    }
    else {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource" + $filterQuery
    }

    Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

    $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
        try {
            #$Runspace.GraphData.MDMDevices = (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop).Value
            $Runspace.GraphData.MDMDevices = Invoke-IDMGraphRequests -Uri $uri -Headers $AuthToken -Passthru -ErrorAction Stop
        }
        catch {
            Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Color Red
            Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Type Error
        }
    })

    If($Expand)
    {
        $i=0
        $Devices = @()
        #Populate AAD devices
        Get-IDMAzureDevicesInRunspace -Runspace $Runspace -ParentRunspace $Runspace -AuthToken $AuthToken

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{

            $Runspace.Data.IntuneDevices = @()

            #TEST $Resource = $Response | Where deviceName -eq 'DTOLAB-46VEYL1'
            Foreach($Resource in $Runspace.GraphData.MDMDevices)
            {
                $i++
                If($PSBoundParameters.ContainsKey('ListObject'))
                {
                    Update-IDMProgress -Runspace $Runspace -PercentComplete ($i/$Runspace.GraphData.MDMDevices.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$Runspace.GraphData.MDMDevices.count,$Resource.deviceName)
                    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Resource.deviceName,$ListObject.Name) -Type Info
                    $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                        $ListObject.Items.Add($Resource.deviceName) | Out-Null
                    })
                }

                #Add additional Properties to devices
                $OutputItem = New-Object PSObject
                Foreach($p in $Resource | Get-Member -MemberType NoteProperty){
                    $OutputItem | Add-Member NoteProperty $p.name -Value $Resource.($p.name)
                }
                #$AADObjects | Where displayName -eq 'DTOLAB-46VEYL1'
                If($FilteredObj = $Runspace.GraphData.AADDevices | Where deviceId -eq $Resource.azureADDeviceId){
                    # Create a new object to store this information
                    $OutputItem | Add-Member NoteProperty "azureADObjectId" -Value $FilteredObj.id -Force
                    $OutputItem | Add-Member NoteProperty "accountEnabled" -Value $FilteredObj.accountEnabled -Force
                    $OutputItem | Add-Member NoteProperty "deviceVersion" -Value $FilteredObj.deviceVersion -Force
                    $OutputItem | Add-Member NoteProperty "enrollmentProfileName" -Value $FilteredObj.enrollmentProfileName -Force
                    $OutputItem | Add-Member NoteProperty "enrollmentType" -Value $FilteredObj.enrollmentType -Force
                    $OutputItem | Add-Member NoteProperty "isCompliant" -Value $FilteredObj.isCompliant -Force
                    $OutputItem | Add-Member NoteProperty "mdmAppId" -Value $FilteredObj.mdmAppId -Force
                    $OutputItem | Add-Member NoteProperty "physicalIds" -Value $FilteredObj.physicalIds -Force
                    $OutputItem | Add-Member NoteProperty "extensionAttributes " -Value $FilteredObj.extensionAttributes -Force
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
                Update-IDMProgress -Runspace $Runspace -PercentComplete ($i/$Devices.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$Devices.count,$Device.deviceName)
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

    #Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Added {0} items to list" -f $Devices.count) -Color Green
    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Found {0} devices" -f $Devices.count) -Type Info

    #return $Devices.Where({ $null -ne $_ })
    #$Runspace.Data.IntuneDevices = @()
    #$Runspace.Data.IntuneDevices += $Devices.Where({ $null -ne $_ })
}



Function Get-IDMAzureDevicesInRunspace{
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
        [string]$FilterBy,

        [Parameter(Mandatory=$false)]
        [string]$Filter,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken,

        [switch]$Passthru
    )
    Begin{

        # Defining Variables
        $graphApiVersion = "beta"
        $Resource = "devices"
        If($FilterBy -and $Filter){
            switch($FilterBy){
                'DisplayName' {$uri = "https://graph.microsoft.com/beta/devices?`$filter=displayName eq '$Filter'"}

                'StartWithDisplayName' {$uri = "https://graph.microsoft.com/beta/devices?`$filter=startswith(displayName, '$Filter')"}

                'NOTStartWithDisplayName'{ $uri = "https://graph.microsoft.com/beta/devices?`$filter=NOT startsWith(displayName, '$Filter')"}
            }

        }Else{
            $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
        }
    }
    Process{
        Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            try {
                #$Runspace.GraphData.AADDevices = (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop).value
                $Runspace.GraphData.AADDevices = Invoke-IDMGraphRequests -Uri $uri -Headers $AuthToken -Passthru -ErrorAction Stop
            }
            catch {
                Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Color Red
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


Function Get-IDMIntuneAssignmentsInRunspace{
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Runspace,

        [Parameter(Mandatory=$false)]
        [hashtable]$ParentRunspace,

        [Parameter(Mandatory=$true,ParameterSetName='TargetArea')]
        [ValidateSet('Devices','Users')]
        [string]$Target,

        [Parameter(Mandatory=$true,ParameterSetName='TargetArea')]
        [string]$TargetId,

        [Parameter(Mandatory=$true,ParameterSetName='TargetSet')]
        [hashtable]$TargetSet,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Windows','Android','MacOS','iOS')]
        [string]$Platform = 'Windows',

        [Parameter(Mandatory=$false)]
        $ListObject,

        [Parameter(Mandatory=$false)]
        [switch]$IncludePolicySetInherits,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken,

        [Parameter(Mandatory=$false)]
        [switch]$Passthru
    )

    If($PSBoundParameters.ContainsKey('Runspace')){
        Update-IDMProgress -Runspace $Runspace -StatusMsg ("Retrieving assignments...") -Indeterminate
    }

    $graphApiVersion = "beta"

    #First get all Azure AD groups this device is a member of.
    $UriResources = @()
    #TEST $TargetSet = @{devices=$syncHash.Data.SelectedDevice.azureADObjectId;users=$syncHash.Data.AssignedUser.id}
    If($TargetSet)
    {
        $UriResources += $TargetSet.GetEnumerator() | %{"https://graph.microsoft.com/$graphApiVersion/$($_.Name)/$($_.Value)/memberOf"}
    }
    Else{
        $UriResources += "https://graph.microsoft.com/$graphApiVersion/$($Target.ToLower())/memberOf"
    }

    #loop through each Intune Component, then get assignments for each
    Switch($Platform){
        'Windows' {
                $PlatformType = @('microsoftStore',
                                'win32LobApp',
                                'windows',
                                'officeSuiteApp',
                                'sharedPC',
                                'editionUpgrade',
                                'webApp'
                )

                $PlatformComponents = @(
                    'deviceManagement/windowsAutopilotDeploymentProfiles'
                    'deviceManagement/deviceCompliancePolicies'
                    'deviceManagement/deviceComplianceScripts'
                    'deviceManagement/deviceConfigurations'
                    'deviceManagement/deviceEnrollmentConfigurations'
                    'deviceManagement/deviceHealthScripts'
                    'deviceManagement/deviceManagementScripts'
                    'deviceManagement/roleScopeTags'
                    'deviceManagement/windowsQualityUpdateProfiles'
                    'deviceManagement/windowsFeatureUpdateProfiles'
                    'deviceAppManagement/windowsInformationProtectionPolicies'
                    'deviceAppManagement/mdmWindowsInformationProtectionPolicies'
                    'deviceAppManagement/mobileApps'
                    'deviceAppManagement/policysets'
                )
        }

        'Android' {$PlatformType = @('android',
                                    'webApp',
                                    'aosp'
                                    )
        }

        'MacOS'   {$PlatformType = @('IOS',
                                    'macOS',
                                    'webApp'
                                    )
        }

        'iOS'     {$PlatformType = @('ios',
                                    'webApp'
                                    )
        }
    }

    #Add component URIs
    $UriResources += $PlatformComponents | %{ "https://graph.microsoft.com/$graphApiVersion/$($_)"}

    $GraphRequests = $UriResources | Invoke-IDMGraphRequests -Headers $AuthToken -Threads $UriResources.Count -Passthru

    If($PSBoundParameters.ContainsKey('ParentRunspace')){
        $ParentRunspace.Window.Dispatcher.Invoke("Normal",[action]{
            $ParentRunspace.GraphData.PlatformResources = $GraphRequests
        })
    }

    $DeviceGroups = ($GraphRequests | Where {$_.uri -like '*/devices/*/memberOf'})
    $UserGroups = ($GraphRequests | Where {$_.uri -like '*/users/*/memberOf'})

    If($PSBoundParameters.ContainsKey('ParentRunspace')){
        $ParentRunspace.Window.Dispatcher.Invoke("Normal",[action]{
            $ParentRunspace.Data.DeviceGroups = $DeviceGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }}
            $ParentRunspace.Data.UserGroups = $UserGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }}
        })
    }

    $DeviceGroupMembers = $DeviceGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }},@{N='Target';E={'Devices'}}
    $UserGroupMembers = $UserGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }},@{N='Target';E={'Users'}}

    #combine device and users memberships
    $AllGroupMembers = @()
    $AllGroupMembers = $DeviceGroupMembers + $UserGroupMembers



    <#
    $GraphRequests.'@odata.type' | Select -unique
    $GraphRequests.type | Select -unique
    ($GraphRequests.Value | Where '@odata.type' -eq '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration')
    ($GraphRequests.Value | Where '@odata.type' -eq '#microsoft.graph.deviceEnrollmentLimitConfiguration')
    ($GraphRequests.Value | Where '@odata.type' -eq '#microsoft.graph.deviceEnrollmentWindowsHelloForBusinessConfiguration')
    ($GraphRequests.Value | Where '@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration')
    #>
    $PlatformResources = ($GraphRequests | Where {$_.'@odata.type' -match ($PlatformType -join '|')}) |
                                            Select id,uri,
                                                @{N='type';E={Set-IDMResourceFriendlyType -Category (split-path $_.uri -leaf) -ODataType $_.'@odata.type'}},
                                                @{N='name';E={Set-IDMResourceFriendlyName -Name $_.displayName -LicenseType $_.licenseType -ODataType $_.'@odata.type'}},
                                                @{N='Assigned';E={If('isAssigned' -in ($_ | Get-Member -MemberType NoteProperty).Name){[boolean]$_.isAssigned}}}

    <#
    $PlatformResources[35]
    $PlatformResources[418]
    $PlatformResources = $GraphRequests| Select id,@{N='type';E={Set-IDMResourceFriendlyType -Category (split-path $_.uri -leaf) -ODataType $_.'@odata.type'}}, @{N='name';E={If($_.licenseType){$_.displayName + ' (' + $_.licenseType + ')'}Else{$_.displayName}}},@{N='Assigned';E={If('isAssigned' -in ($_ | Get-Member -MemberType NoteProperty).Name){[boolean]$_.isAssigned}}} | ft
    $PlatformResources = $GraphRequests| Select id,uri,@{N='type';E={Set-IDMResourceFriendlyType -Category (split-path $_.uri -leaf) -ODataType $_.'@odata.type'}}, @{N='name';E={If($_.licenseType){$_.displayName + ' (' + $_.licenseType + ')'}Else{$_.displayName}}},'@odata.type',@{N='Assigned';E={If('isAssigned' -in ($_ | Get-Member -MemberType NoteProperty).Name){[boolean]$_.isAssigned}}} | ft
    $PlatformResources.type | Select -unique
    $PlatformResources | Where type -eq 'Policy Set'
    $PlatformResources.type
    #>
    #get Assignments of all resource suing multithreading
    $ResourceAssignments = $PlatformResources | %{ $_.uri + '/' + $_.id + '/assignments'} | Invoke-IDMGraphRequests -Headers $AuthToken -Passthru
    #$ResourceAssignments.count


    $AssignmentList= @()

    If($PSBoundParameters.ContainsKey('ParentRunspace')){
        $ParentRunspace.Window.Dispatcher.Invoke("Normal",[action]{
                $ParentRunspace.Data.DeviceAssignments = @()
                $ParentRunspace.Data.UserAssignments = @()
        })
    }
    #TEST $Assignment = $ResourceAssignments[0]
    #TEST $Assignment = ($ResourceAssignments | Where Source -eq 'policySets')[0]
    $i=0
    Foreach($Assignment in $ResourceAssignments)
    {
        $ReferenceResource = $PlatformResources | Where { $Assignment.uri -eq ($_.uri + '/' + $_.id + '/assignments')}
        $AssignmentGroup = '' | Select Id,Name,Type,Mode,Target,Platform,Group,GroupType,GroupId,Assigned
        $AssignmentGroup.Id = $Assignment.id
        $AssignmentGroup.Name = $ReferenceResource.name
        $AssignmentGroup.Type = $ReferenceResource.Type
        #$AssignmentGroup.Target = $Assignment.target
        $AssignmentGroup.Platform = $Platform
        $AssignmentGroup.Assigned = $ReferenceResource.Assigned

        If($Assignment.intent){
            $AssignmentGroup.Mode = (Get-Culture).TextInfo.ToTitleCase($Assignment.intent)
        }Else{
            $AssignmentGroup.Mode = 'Assigned'
        }

        #Grab Policyset info
        If($Assignment.source -eq 'policySets' -and $IncludePolicySetInherits){
            $PolicySet = $True
            $PolicySetDetails = $PlatformResources | Where id -eq $Assignment.sourceId
            If(!$PolicySetDetails){
                $PolicySet = $False
            }
        }
        Else{
            $PolicySet = $False
        }

        switch($Assignment.target.'@odata.type'){
            '#microsoft.graph.allLicensedUsersAssignmentTarget' {
                $AddToGroup = $true
                $AssignmentGroup.Group = 'All Users'
                #$ResourceAssignments += $AssignmentGroup
                $AssignmentGroup.GroupType = 'Built-In'
                $AssignmentGroup.Target = 'Users'
            }

            '#microsoft.graph.allDevicesAssignmentTarget' {
                $AddToGroup = $true
                $AssignmentGroup.Group = 'All Devices'
                $AssignmentGroup.GroupType = 'Built-In'
                $AssignmentGroup.Target = 'Devices'
            }

            '#microsoft.graph.exclusionGroupAssignmentTarget' {
                $AssignmentGroup.Mode = 'Excluded'
                $TargetAssignments = $Assignment.target | Where '@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget'
                #$Group = $TargetAssignments.GroupId[-1]
                Foreach($Group in $TargetAssignments.GroupId)
                {
                    If($Group -in $AllGroupMembers.id){
                        $GroupDetails = ($AllGroupMembers | Where id -eq $Group)
                        $AddToGroup = $true
                        $AssignmentGroup.GroupId = $GroupDetails.id
                        $AssignmentGroup.Group = $GroupDetails.displayName
                        $AssignmentGroup.GroupType = $GroupDetails.GroupType
                        $AssignmentGroup.Target = $GroupDetails.Target
                    }Else{
                        $AddToGroup = $false
                    }
                }
            }

            '#microsoft.graph.groupAssignmentTarget' {
                $TargetAssignments = $Assignment.target | Where '@odata.type' -eq '#microsoft.graph.groupAssignmentTarget'
                Foreach($Group in $TargetAssignments.GroupId)
                {
                    If($Group -in $AllGroupMembers.id){
                        $GroupDetails = ($AllGroupMembers | Where id -eq $Group)
                        $AddToGroup = $true
                        $AssignmentGroup.GroupId = $GroupDetails.id
                        $AssignmentGroup.Group = $GroupDetails.displayName
                        $AssignmentGroup.GroupType = $GroupDetails.GroupType
                        $AssignmentGroup.Target = $GroupDetails.Target
                    }Else{
                        $AddToGroup = $false
                    }
                }
            }
            default {$AddToGroup = $false}
        }#end switch

        If($AddToGroup){
            #update assignment group columns if policy is set
            If($PolicySet){
                $AssignmentGroup.Mode = 'Applied (Inherited)'
                $AssignmentGroup.Group = ($AssignmentGroup.Group + ' (' + $AssignmentGroup.GroupType + ')')
                #$AssignmentGroup.Group = ('PolicySet: ' + $PolicySet.displayName)
                #$AssignmentGroup.GroupType = ($AssignmentGroup.Group + ' (Inherited)')
                $AssignmentGroup.GroupType = ('PolicySet: ' + $PolicySetDetails.name)
            }

            If($PSBoundParameters.ContainsKey('ParentRunspace')){
                $ParentRunspace.Window.Dispatcher.Invoke("Normal",[action]{
                    If($AssignmentGroup.Target -eq 'Devices'){
                        $ParentRunspace.Data.DeviceAssignments += $AssignmentGroup
                    }
                    If($AssignmentGroup.Target -eq 'Users'){
                        $ParentRunspace.Data.UserAssignments += $AssignmentGroup
                    }
                })

                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Device.deviceName,$ListObject.Name) -Type Info
            }

            If($PSBoundParameters.ContainsKey('ListObject'))
            {
                $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                    $ListObject.Items.Add($AssignmentGroup) | Out-Null
                })
            }

            If($PSBoundParameters.ContainsKey('Runspace')){
                Update-IDMProgress -Runspace $Runspace -PercentComplete ($i/$ResourceAssignments.count * 100) -StatusMsg ("[{0} of {1}] :: Adding assignment to list: {2}" -f $i,$ResourceAssignments.count,$Assignment.Name)
            }

            $AssignmentList += $AssignmentGroup
        }
        $i++

    }#end assignment loop

    If($Passthru){
        #$AssignmentList | ft
        Return $AssignmentList
    }
}


Function Invoke-IDMGraphRequests{
    <#
    .SYNOPSIS
     Invoke Rest method in multithread
    .DESCRIPTION
     Invoke Rest method using the get method but do it using a pool of runspaces

    .NOTES
    Reference:
    https://b-blog.info/en/implement-multi-threading-with-net-runspaces-in-powershell.html
    https://adamtheautomator.com/powershell-multithreading/

    #>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,HelpMessage="Specify Uri or array or Uris")]
        [string[]]$Uri,

        [Parameter(Mandatory=$true)]
        [hashtable]$Headers,

        [int]$Threads = 15,

        [switch]$Passthru
    );
    Begin{
        #initialSessionState will hold typeDatas and functions that will be passed to every runspace.
        $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault();

        #define function to run
        function Get-RestData {
            param (
                [Parameter(Mandatory=$true,Position=0)][string]$Uri,
                [Parameter(Mandatory=$true,Position=1)][hashtable]$Headers
            );
            try {
                $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -DisableKeepAlive -ErrorAction Stop;
            } catch {
                $ex = $_.Exception
                $errorResponse = $ex.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd();
                Write-Host ("{0}: Error Status: {1}; {2}" -f $uri,$ex.Response.StatusCode,$responseBody)
                return $false;
            };

            return $response.value;
        }

        #add function to the initialSessionState
        $GetRestData_def = Get-Content Function:\Get-RestData;
        $GetRestDataSessionStateFunction = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'Get-RestData', $GetRestData_def;
        $initialSessionState.Commands.Add($GetRestDataSessionStateFunction);

        #define your TypeData (Makes the output as object later on)
        $init = @{
            MemberName = 'Init';
            MemberType = 'ScriptMethod';
            Value = {
                Add-Member -InputObject $this -MemberType NoteProperty -Name uri -Value $null;
                Add-Member -InputObject $this -MemberType NoteProperty -Name headers -Value $null;
                Add-Member -InputObject $this -MemberType NoteProperty -Name value -Value $null;
            };
            Force = $true;
        }

        # and initiate the function call to add to session state:
        $populate = @{
            MemberName = 'Populate';
            MemberType = 'ScriptMethod';
            Value = {
                param (
                    [Parameter(Mandatory=$true)][string]$Uri,
                    [Parameter(Mandatory=$true)][hashtable]$Headers
                );
                $this.uri = $Uri;
                $this.headers = $Headers
                $this.value = (Get-RestData -Uri $Uri -Headers $Headers);
            };
            Force = $true;
        }

        Update-TypeData -TypeName 'Custom.Object' @Init;
        Update-TypeData -TypeName 'Custom.Object' @Populate;
        $customObject_typeEntry = New-Object System.Management.Automation.Runspaces.SessionStateTypeEntry -ArgumentList $(Get-TypeData Custom.Object), $false;
        $initialSessionState.Types.Add($customObject_typeEntry);

        #define our main, entry point to runspace
        $ScriptBlock = {
            Param (
                [PSCustomObject]$Uri,
                $Headers
            )

            #build object and
            $page = [PsCustomObject]@{PsTypeName ='Custom.Object'};
            $page.Init();
            $page.Populate($Uri,$Headers);

            $Result = New-Object PSObject -Property @{
                uri = $page.Uri
                value = $page.value
            };

            return $Result;
        }

        #build Runsapce threads
        $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $Threads, $initialSessionState, $Host);
        $RunspacePool.Open();
        $Jobs = @();
    }
    Process{
        #START THE JOB
        $i = 0;
        foreach($url in $Uri) { #$Uri - some array of uris
            $i++;
            #call scriptblock with arguments
            $Job = [powershell]::Create().AddScript($ScriptBlock).AddArgument($url).AddArgument($Headers);
            $Job.RunspacePool = $RunspacePool;
            $Jobs += New-Object PSObject -Property @{
                RunNum = $i;
                Pipe = $Job;
                Result = $Job.BeginInvoke();
            }
        }
    }
    End{
        $results = @();
        #TEST $job = $jobs
        foreach ($Job in $Jobs) {
            $Result = $Job.Pipe.EndInvoke($Job.Result)
            #add uri to object list if passthru used
            If($Passthru){
                Foreach($item in $Result.value){
                    $OutputItem = New-Object PSObject
                    $OutputItem | Add-Member NoteProperty "uri" -Value $Result.uri -Force
                    Foreach($p in $item | Get-Member -MemberType NoteProperty){
                        $OutputItem | Add-Member NoteProperty $p.name -Value $item.($p.name)
                    }
                $Results += $OutputItem
                }
            }
            Else{
                $Results += $Result
            }
        }
        Return $Results
    }
}
<#TEST
    $Uri = 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'
    Invoke-IDMGraphRequests -Uri $Uri -Headers $AuthToken -Passthru


$Uri = @(
    'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies'
    'https://graph.microsoft.com/beta/deviceManagement/deviceComplianceScripts'
    'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations'
    'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations'
    'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'
    'https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts'
    'https://graph.microsoft.com/beta/deviceManagement/roleScopeTags'
    'https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles'
    'https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles'
    'https://graph.microsoft.com/beta/deviceAppManagement/windowsInformationProtectionPolicies'
    'https://graph.microsoft.com/beta/deviceAppManagement/mdmWindowsInformationProtectionPolicies'
    'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
    'https://graph.microsoft.com/beta/deviceAppManagement/policysets'
)
$Responses = $Uri | Invoke-IDMGraphRequests -Headers $AuthToken -Threads $Uri.count -Passthru
$Responses[0]

Measure-command {
    Get-IDMIntuneAssignments -Target Devices -Platform $syncHash.Properties.DevicePlatform -TargetId $syncHash.Data.SelectedDevice.azureADObjectId -IncludePolicySetInherits
    Get-IDMIntuneAssignments -Target Users -Platform $syncHash.Properties.DevicePlatform -TargetId $syncHash.Data.AssignedUser.id -IncludePolicySetInherits
}
Measure-command {Get-IDMIntuneAssignmentsInRunspace -Platform $syncHash.Properties.DevicePlatform -TargetSet @{devices=$syncHash.Data.SelectedDevice.azureADObjectId;users=$syncHash.Data.AssignedUser.id} -IncludePolicySetInherits}
#>
