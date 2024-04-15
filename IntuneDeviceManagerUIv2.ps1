<#
.SYNOPSIS
    Connects to Intune and AD to manage devices

.DESCRIPTION

.NOTES
    Author		: Dick Tracy II <richard.tracy@microsoft.com>
    Source	    :
    Version		: 2.0.2

.EXAMPLE
    .\IntuneDeviceManagerUIv2.ps1 -DevicePrefix 'DTOHAADJ'

.EXAMPLE
    .\IntuneDeviceManagerUIv2.ps1 -RenameEnablement

.EXAMPLE
    .\IntuneDeviceManagerUIv2.ps1 -DevicePlatform Android

.EXAMPLE
    .\IntuneDeviceManagerUIv2.ps1 -AppConnect -ApplicationId 'dd99ec13-a3c5-4703-b95f-794a2b559fb0' -TenantId '2ec9dcf0-b109-434a-8bcd-238a3bf0c6b2'

.LINK
    #modules needed:
        Microsoft.Graph.Authentication
        WindowsAutoPilotIntune
        IDMCmdlets
#>
[cmdletbinding(DefaultParameterSetName='User')]
param(
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [switch]$AppConnect,

    [Parameter(Mandatory=$true,ParameterSetName='App')]
    [string]$ApplicationId,

    [Parameter(Mandatory=$true,ParameterSetName='App')]
    [string]$TenantId,

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [ValidateSet('Global','USGov')]
    [string]$Environment = 'Global',

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [ValidateSet('Windows','Android','MacOS','iOS')]
    [string]$DevicePlatform = 'Windows',

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [string]$DevicePrefix,

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [switch]$RenameEnablement,

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [switch]$ManageStaleDevices,

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [ValidateSet('30','60','90','120','180','365','730')]
    [string]$DefaultDeviceAge = '90',

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [hashtable]$RenameRules = @{RuleRegex1 = '^.{0,3}';RuleRegex2 ='.{0,3}[\s+]'},

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [ValidateSet('No Abbr','Chassis','Manufacturer','Model')]
    [string]$RenameAbbrType = 'Chassis',

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [string]$RenameAbbrKey = 'Laptop=A, Notebook=A, Tablet=A, Desktop=W, Tower=W, Virtual Machine=W',

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [string]$RenamePrefix,

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [ValidateSet(0,1,2,3,4,5)]
    [int]$RenameAppendDigits = 3,

    [Parameter(Mandatory=$false,ParameterSetName='User')]
    [Parameter(Mandatory=$false,ParameterSetName='App')]
    [string]$RenameSearchFilter = '*'
)
#*=============================================
##* Runtime Function - REQUIRED
##*=============================================
#region FUNCTION: Check if running in ISE

Function Test-IsAdmin{
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        return $false
    }Else{
        return $true
    }
}

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
            Try{
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
            Catch{
                $ScriptPath = $MyInvocation.MyCommand.Definition
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
##*=============================================
##* VARIABLE DECLARATION
##*=============================================
#region VARIABLES: Building paths & values
# Use function to get paths because Powershell ISE & other editors have different results
[string]$scriptPath = Get-ScriptPath
[string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
[string]$scriptRoot = Split-Path -Path $scriptPath -Parent
[string]$FunctionPath = Join-Path -Path $scriptRoot -ChildPath 'Functions'
[string]$ResourcePath = Join-Path -Path $scriptRoot -ChildPath 'Resources'
[string]$StylePath = Join-Path -Path $ResourcePath -ChildPath 'Styles'
[string]$XAMLFilePath = Join-Path -Path $ResourcePath -ChildPath 'MainWindow.xaml'
##*=============================================
##* External Functions
##*=============================================
. "$FunctionPath\Environment.ps1"

#parse changelog for version for a more accurate version
$ChangeLogPath = Resolve-ActualPath -FileName 'CHANGELOG.md' -WorkingPath $scriptRoot -ErrorAction SilentlyContinue
If($ChangeLogPath){
    $ChangeLog = Get-Content $ChangeLogPath
    $Changedetails = (($ChangeLog -match '##')[0].TrimStart('##') -split '-').Trim()
    [string]$Version = [version]$Changedetails[0]
    [string]$MenuDate = $Changedetails[1]
}
#check modules and the MINIMUM modules needed
$ModulesNeeded = @{
    'Microsoft.Graph.Authentication' = ''
    'IDMCmdlets' = '1.0.2.7'
    'WindowsAutoPilotIntune' = '5.6'
}

$ParamProps = @{
    Name = $scriptName
    DevicePlatform = $DevicePlatform
    DevicePrefix = $DevicePrefix
    Rules = $RenameRules
    AllowRename = $RenameEnablement
    ManageStaleDevices=$ManageStaleDevices
    DeviceAge=$DefaultDeviceAge
    SearchFilter = $SearchFilter
    AbbrType = $RenameAbbrType
    AbbrKey = $RenameAbbrKey
    Prefix = $RenamePrefix
    AppendDigits = $RenameAppendDigits
    AppConnect = $AppConnect
    ApplicationId = $ApplicationId
    TenantId = $TenantId
    Version = $Version
    MenuDate = $MenuDate
    RequiredModules = $ModulesNeeded
    RunningAsAdmin = Test-IsAdmin
}

#update properties with correct environment and autopilot support
switch ($Environment) {
    'Public' {
        $ParamProps += @{
            Environment = 'Global'
            AutopilotSupported = $true
        }
    }
    'Global' {
        $ParamProps += @{
            Environment = 'Global'
            AutopilotSupported = $true
        }
    }
    'USGov' {
        $ParamProps += @{
            Environment = 'USGov'
            AutopilotSupported = $false
        }
    }
    'USGovDoD' {
        $ParamProps += @{
            Environment = 'USGovDoD'
            AutopilotSupported = $false
        }
    }
}

##*=============================================
##* UI FUNCTION
##*=============================================
Function Show-UIMainWindow
{
    <#
    .SYNOPSIS
        Shows the Intune Device Manager UI
    .DESCRIPTION
        Displays the Intune Device Manager (IDM) UI to managing devices in Intune
    .NOTES
        Author		: Dick Tracy II <richard.tracy@microsoft.com>
        Source	    :
        Version		: 1.1.6
    .PARAMETER XamlFile
    #>
    Param(
        [String]$XamlFile,
        [String]$StylePath,
        [String]$FunctionPath,
        [hashtable]$Properties,
        [switch]$Wait
    )
    <#
    $XamlFile=$XAMLFilePath
    $StylePath=$StylePath
    $FunctionPath=$FunctionPath
    $Properties=$ParamProps
    $Wait=$true
    #>
    #build runspace
    $syncHash = [hashtable]::Synchronized(@{})
    $IDMRunSpace =[runspacefactory]::CreateRunspace()
    $syncHash.Runspace = $IDMRunSpace
    $syncHash.FunctionPath = $FunctionPath
    $syncHash.StylePath = $StylePath
    $syncHash.XamlFile = $XamlFile
    $syncHash.Properties = $Properties
    $syncHash.Data = @{}
    $syncHash.GraphData = @{}
    $IDMRunSpace.ApartmentState = "STA"
    $IDMRunSpace.ThreadOptions = "ReuseThread"
    $IDMRunSpace.Open() | Out-Null
    $IDMRunSpace.SessionStateProxy.SetVariable("syncHash",$syncHash)
    $PowerShellCommand = [PowerShell]::Create().AddScript({
    #$Code{
        #Load assembles to display UI
        [System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework') | out-null
        [System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')      | out-null
        #convert XAML to XML just to grab info using xml dot sourcing (Not used to process form)
        [string]$XAML = (Get-Content $syncHash.XamlFile -ReadCount 0) -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window' -replace 'Click=".*','/>'
        [xml]$XML = $XAML
        #grab the list of merged dictionaries in XML, replace the path with Powershell
        $MergedDictionaries = $XML.Window.'Window.Resources'.ResourceDictionary.'ResourceDictionary.MergedDictionaries'.ResourceDictionary.Source
        #$XML.SelectNodes("//*[@Source]")
        #grab all style files
        $Resources = Get-ChildItem $syncHash.StylePath -Filter *.xaml
        # replace the resource path
        foreach ($Source in $MergedDictionaries)
        {
            $FileName = Split-Path $Source -Leaf
            $ActualPath = $Resources | Where {$_.Name -match $FileName} | Select -ExpandProperty FullName
            $XAML = $XAML.replace($Source,$ActualPath) #  ($ActualPath -replace "\\","/")
        }
        #convert XAML to XML
        [xml]$XAML = $XAML
        $reader=(New-Object System.Xml.XmlNodeReader $xaml)
        $syncHash.Window=[Windows.Markup.XamlReader]::Load( $reader )
        # Store Form Objects In hashtable
        #===========================================================================
        $xaml.SelectNodes("//*[@Name]") | %{ $syncHash."$($_.Name)" = $syncHash.Window.FindName($_.Name)}
        #Return log path (either in task sequence or temp dir)
        #build log name
        [string]$LogFileName = $syncHash.Name +'.log'
        #build global log fullpath
        $Global:LogFilePath = Join-Path $env:temp -ChildPath $LogFileName
        [string]$FunctionPath = $syncHash.FunctionPath
        ##* External Scripts
        ##*=============================================
        . "$FunctionPath\Logging.ps1"
        . "$FunctionPath\Environment.ps1"
        . "$FunctionPath\DeviceInfo.ps1"
        . "$FunctionPath\Runspace.ps1"
        . "$FunctionPath\UIControls.ps1"
        . "$FunctionPath\UIHandlers.ps1"
        . "$FunctionPath\UIHelpMenu.ps1"
        . "$FunctionPath\Helpers.ps1"
        #DELETE THIS LATER
        #. "$FunctionPath\IDMGraph.ps1"
        #. "$FunctionPath\IDM.ps1"
        #. "$FunctionPath\IDMAutopilot.ps1"
        # INNER  FUNCTIONS
        #=================================
        If(Test-IsISE){
            $Windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
            $asyncWindow = Add-Type -MemberDefinition $Windowcode -name Win32ShowWindowAsync -namespace Win32Functions
            $null = $asyncWindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)
        }


        #Closes UI objects and exits (within runspace)
        Function Close-UIMainWindow
        {
            if ($syncHash.hadCritError) { Write-Host -Message "Background thread had a critical error" -ForegroundColor red }
            #if runspace has not errored Dispose the UI
            if (!($syncHash.isClosing)) { $syncHash.Window.Close() | Out-Null }
        }


        $updateUI = {

            If($syncHash.AssignmentWindow.Window.IsVisible -eq $true){
                Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} assignment(s) for device [{1}] and user [{2}]' -f $syncHash.AssignmentWindow.AssignmentData.count,$syncHash.Data.SelectedDevice.deviceName,$syncHash.Data.AssignedUser.userPrincipalName) -PercentComplete 100
            }

            If($syncHash.AssignmentWindow.Window){
                $syncHash.btnViewIntuneAssignments.IsEnabled = $syncHash.AssignmentWindow.isClosed
            }
        }

        # Start populating menu content
        #=================================
        $syncHash.txtVersion.Text = $Synchash.Properties.Version

        $syncHash.Data.MissingModules = @()
        #TEST $Module = $ModulesNeeded[0]
        #TEST $Module = $syncHash.Properties.RequiredModules.GetEnumerator() | Where Name -eq 'IDMCmdlets'
        #TEST $Module = $syncHash.Properties.RequiredModules.GetEnumerator() | Where Name -eq 'Az.Accounts'
        Foreach($Module in $syncHash.Properties.RequiredModules.GetEnumerator()){
            $ModuleInstalled = Get-Module -Name $Module.Name -ListAvailable
            If($null -eq $ModuleInstalled){
                $syncHash.Data.MissingModules += $Module
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("No module found named [{0}], module must be installed to continue" -f $Module) -Type Error
            }
            Else{
                #get the latest version of module
                $LatestModule = $ModuleInstalled | Where Version -eq ($ModuleInstalled.Version | measure -Maximum).Maximum
                #Check version if needed
                If(-NOT[string]::IsNullOrEmpty($Module.Value))
                {
                    If($LatestModule.Version -lt [version]$Module.Value){
                        $syncHash.Data.MissingModules += $Module
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Installed module [{0}] version is [{1}]; this script requires version [{2}]" -f $Module.Name,$ModuleInstalled.Version.ToString(),$Module.Value) -Type Error
                    }
                }
                Else{
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Module [{0}] is installed with a version equal to or greater than [{1}] " -f $Module.Name,$LatestModule.Version) -Type Info
                }
            }
        }

        #if required modules not installed display UI correctly
        If($syncHash.Data.MissingModules.Count -ge 1){
            $syncHash.AppModulePopup.IsOpen = $true
            $syncHash.btnGetIntuneDevices.IsEnabled = $false

        }Else{
            $syncHash.AppModulePopup.IsOpen = $false
        }

        $syncHash.btnAppModuleCancel.Add_Click({
            $syncHash.AppModulePopup.IsOpen = $false
        })

        $syncHash.txtAppModuleList.text = ($syncHash.Data.MissingModules.GetEnumerator() | %{If($_.Value){$_.Name + '[' + $_.Value + ']'}Else{$_.Name}}) -join ','


        $syncHash.btnAppModuleInstall.Add_Click({
            Update-UIProgress -Runspace $synchash -StatusMsg ('Installing [{0}] modules, please wait...' -f $syncHash.Data.MissingModules.count) -Indeterminate

            $err=0
            #always install nuget if modules missing
            If( ($syncHash.Data.MissingModules.count -gt 0) ){
                If( (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue).Version -lt [version]'2.8.5.201'){
                    If($syncHash.Properties.RunningAsAdmin){
                        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                    }Else{
                        $syncHash.txtAppModuleList.text = 'You must run this as an administrator to install the required modules'
                    }
                }
                
            }

            Foreach($Module in $syncHash.Data.MissingModules.GetEnumerator()){
                $syncHash.lblAppModuleMsg.Content = ("Installing module: {0}..." -f $Module)
                Try{
                    Install-Module -Name $Module.Name -AllowClobber -Force -Confirm:$false
                }Catch{
                    $err++
                    $syncHash.lblAppModuleMsg.Content = ("Failed: {0}..." -f $_.exception.message)
                }
            }
            If($err -eq 0){
                $syncHash.lblAppModuleMsg.Foreground = 'White'
                $syncHash.lblAppModuleMsg.Content = ("Modules installed, You must restart app...")
                Update-UIProgress -Runspace $synchash -StatusMsg ('Modules are installed, but the app needs to be restarted') -PercentComplete 100 -Color 'Green'
                $syncHash.btnAppModuleCancel.Content = 'Ok'
            }
            Else{
                Update-UIProgress -Runspace $synchash -StatusMsg ('Failed to install [{0}] modules' -f $err.count) -PercentComplete 100 -Color 'Red'
                $syncHash.btnAppModuleCancel.Content = 'Close'
            }
            $syncHash.btnAppModuleInstall.Visibility = 'Hidden'
            $syncHash.AppSecretPopup.IsOpen = $false
        })

        $syncHash.btnAppSecretSubmit.Add_Click({
            If([string]::IsNullOrEmpty($syncHash.pwdAppSecret.Password) ){
                $syncHash.lblAppSecretMsg.content = "Invalid Secret, please try again or cancel"
            }Else{
                $syncHash.AppSecretPopup.IsOpen = $false
                $syncHash.btnGetIntuneDevices.IsEnabled = $true
            }
        })

        $syncHash.spViewAppSecret.Add_MouseEnter({
            $syncHash.txtAppSecret.text = $syncHash.pwdAppSecret.Password
            $syncHash.pwdAppSecret.Visibility = 'Hidden'
            $syncHash.txtAppSecret.Visibility = 'Visible'
        })
        $syncHash.spViewAppSecret.Add_MouseLeave({
            $syncHash.pwdAppSecret.Visibility = 'Visible'
            $syncHash.txtAppSecret.Visibility = 'Hidden'
            $syncHash.txtAppSecret.text = $null
        })
        # UPDATE DATA IN MENU
        #=================================
        If(Test-IsDomainJoined){
            $syncHash.txtDomainDevice.text = 'Yes'
            $syncHash.txtDomainDevice.Foreground = 'Green'
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Device running this is joined to the domain: {0}" -f (Test-IsDomainJoined -Passthru)) -Type Info
        }Else{
            $syncHash.txtDomainDevice.text = 'No'
            $syncHash.btnADUserSync.IsEnabled = $false
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Device running this script must be joined to the domain to view AD objects") -Type Error
        }
        # check if RSAT PowerShell Module is installed
        If(Test-RSATModule){
            $syncHash.txtRSAT.text = 'Yes';$syncHash.txtRSAT.Foreground = 'Green'
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("RSAT PowerShell module is installed: {0}" -f (Test-RSATModule -Passthru)) -Type Info
            $syncHash.btnADUserSync.IsEnabled = $true
        }
        Else{
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("RSAT PowerShell module must be installed to be able to query AD device names") -Type Error
            $syncHash.txtRSAT.text = 'No'
            $syncHash.btnADUserSync.IsEnabled = $false
        }

        # Get PowerShell Version
        [hashtable]$envPSVersionTable = $PSVersionTable
        [version]$envPSVersion = $envPSVersionTable.PSVersion
        $PSVersion = [float]([string]$envPSVersion.Major + '.' + [string]$envPSVersion.Minor)
        $syncHash.txtPSVersion.Text = $PSVersion.ToString()
        IF($envPSVersion.Major -ge 5 -and $envPSVersion.Minor -ge 1){
            $syncHash.txtPSVersion.Foreground = 'Green'
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("PowerShell version is: {0}" -f $PSVersion.ToString()) -Type Info
        }Else{
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("PowerShell must be must be at version 5.1 to work properly") -Type Error
            $syncHash.btnGetIntuneDevices.IsEnabled = $false
            $syncHash.btnNewDeviceName.IsEnabled = $false
        }


        #populate dropdown for Search Option
        @('User Root OU','Computers Root OU','Computers Default OU','Custom') | Add-UIList -Runspace $syncHash -DropdownObject $syncHash.cmbSearchInOptions -Preselect 'User Root OU'
        $syncHash.txtSearchFilter.text = $syncHash.Properties.SearchFilter

        #populate dropdown for Query Rule
        @('User OU Name','User Name','User Display Name','Device Name','Device SerialNumber','Device AssetTag','Random') | Add-UIList -Runspace $syncHash -DropdownObject $syncHash.cmbQueryRule -Preselect 'User OU Name'

        If(-Not(Test-RSATModule) -or -Not(Test-IsDomainJoined)){
            $syncHash.chkNewDeviceNameMoveOU.Visibility = 'Hidden'
            $syncHash.cmbOUOptions.IsEnabled = $false
            $syncHash.txtOUPath.IsEnabled = $false
        }Else{
            #populate dropdown for OU Options
            @('Computers Root','Default Computers','Corresponding User OU','Custom') | Add-UIList -Runspace $syncHash -DropdownObject $syncHash.cmbOUOptions -Preselect 'Computers Root'
            $MoveToOU = Get-WellKnownOU -KnownOU $syncHash.cmbOUOptions.SelectedItem
            $syncHash.txtOUPath.text = $MoveToOU
        }

        If($null -ne $syncHash.Properties.Rules){
            (Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$true -ErrorAction SilentlyContinue
            $syncHash.chkDoRegex.IsChecked = $true
            $syncHash.txtRuleRegex1.text = $syncHash.Properties.Rules['RuleRegex1']
            $syncHash.txtRuleRegex2.text = $syncHash.Properties.Rules['RuleRegex2']
            $syncHash.txtRuleRegex3.text = $syncHash.Properties.Rules['RuleRegex3']
            $syncHash.txtRuleRegex4.text = $syncHash.Properties.Rules['RuleRegex4']
        }Else{
            $syncHash.chkDoRegex.IsChecked = $false
            (Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
        }

        #set text area to enabled if checked
        $syncHash.chkDoRegex.add_Checked({
            (Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$true -ErrorAction SilentlyContinue
        })

        #set text area to disabled if checked
        $syncHash.chkDoRegex.add_Unchecked({
            (Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
            #(Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -text $null -ErrorAction SilentlyContinue
        })

        $syncHash.txtRulePrefix.text = $syncHash.Properties.Prefix
        $syncHash.txtRuleAbbrKey.text = $syncHash.Properties.AbbrKey

        #populate dropdown for Abbreviation Type
        Get-ParameterOption -Command Get-NewDeviceName -Parameter AbbrType | Add-UIList -DropdownObject $syncHash.cmbRuleAbbrType -Preselect $syncHash.Properties.AbbrType

        #populate dropdown for Abbreviation Position
        Get-ParameterOption -Command Get-NewDeviceName -Parameter AbbrPos | Add-UIList -DropdownObject $syncHash.cmbRuleAbbrPosition -Preselect 'After Prefix'

        #populate dropdown for Append Digits
        Add-UIList -ItemsList @('0','1','2','3','4','5') -DropdownObject $syncHash.cmbRuleAddDigits -Preselect $syncHash.Properties.AppendDigits.ToString()

        #populate dropdown for Digit Position
        Get-ParameterOption -Command Get-NewDeviceName -Parameter DigitPos | Add-UIList -DropdownObject $syncHash.cmbRuleDigitPosition -Preselect 'At End'

        #populate dropdown for Device Age
        Add-UIList -ItemsList @('30','60','90','120','180','365','730') -DropdownObject $syncHash.cmbDeviceAge -Preselect $syncHash.Properties.DeviceAge.ToString()

        #populate dropdown for Extensions attributes
        $e=@();For($i = 1; $i -lt 16; $i++){ $e += "extensionAttribute$($i)" }; $e | Add-UIList -Runspace $syncHash -DropdownObject $syncHash.cmbDeviceExtensions -Preselect 'extensionAttribute1'

        #hide the back button on startup
        $syncHash.btnBack.Visibility = 'hidden'
        # EVENT HANDLERS
        #========================
        $syncHash.menuNavigation.Add_SelectionChanged( {
            $Tabcount = $syncHash.menuNavigation.items.count
            #show the back button if next on first page is displayed
            If ($syncHash.menuNavigation.SelectedIndex -eq 0) {
                $syncHash.btnBack.Visibility = 'hidden'
            }
            Else {
                $syncHash.btnBack.Visibility = 'Visible'
            }
            #change the button text to display begin on the last tab
            If ($syncHash.menuNavigation.SelectedIndex -ne ($Tabcount - 1)) {
                #Use tab on keyboard to navigate mentu forward (only works until last page)
                $syncHash.Window.Add_KeyDown( {
                        if ($_.Key -match 'Tab') {
                            Switch-UITabItem -TabControlObject $syncHash.menuNavigation -increment 1
                        }
                    })
            }
        })

        $syncHash.cmbOUOptions.Add_SelectionChanged({
            If(Test-RSATModule -and Test-IsDomainJoined){
                switch($syncHash.cmbOUOptions.SelectedItem){
                    'Default Computers' {
                            $MoveToOU = Get-WellKnownOU -KnownOU $syncHash.cmbOUOptions.SelectedItem
                            $syncHash.txtOUPath.IsReadOnly = $true
                    }
                    'Computers Root' {
                            $MoveToOU = Get-WellKnownOU -KnownOU $syncHash.cmbOUOptions.SelectedItem
                            $syncHash.txtOUPath.IsReadOnly = $true
                    }
                    'Corresponding User OU' {$MoveToOU = (($syncHash.Data.ADUser.distinguishedname -split ",",2)[1]).replace('UserAccounts','Laptops')}
                    'Custom' {$syncHash.txtOUPath.IsReadOnly = $false}
                }
            }
            #Set the value of text object
            $syncHash.txtOUPath.Text = $MoveToOU
        })

        $syncHash.cmbQueryRule.Add_SelectionChanged({
            If($syncHash.cmbQueryRule.SelectedItem -eq 'Random'){
                $syncHash.txtSample.Text = Generate-RandomName
            }
        })

        $syncHash.cmbRuleAbbrType.Add_SelectionChanged({
            Switch($syncHash.cmbRuleAbbrType.SelectedItem){
                'No Abbr' {
                    $syncHash.cmbRuleAbbrPosition.SelectedItem = $null
                    $syncHash.cmbRuleAbbrPosition.IsEnabled = $false
                    $syncHash.txtRuleAbbrKey.IsEnabled = $false
                    $syncHash.txtRuleAbbrKey.Text = $null
                    $syncHash.lblAbbrExample.Content = $null
                }
                'Chassis' {
                    $SampleValue = 'Laptop=L, Notebook=N, Tablet=T, Desktop=D, Tower=D'
                    $syncHash.cmbRuleAbbrPosition.IsEnabled = $true
                    $syncHash.txtRuleAbbrKey.IsEnabled = $true
                    $syncHash.lblAbbrExample.Content = "eg. $SampleValue"
                    $syncHash.cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
                }
                'Manufacturer' {
                    $SampleValue = 'Dell Inc.=D, Microsoft Corporation=M, HP=H, Lenovo=L, VMware=V'
                    $syncHash.cmbRuleAbbrPosition.IsEnabled = $true
                    $syncHash.txtRuleAbbrKey.IsEnabled = $true
                    $syncHash.lblAbbrExample.Content = "eg. $SampleValue"
                    $syncHash.cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
                }
                'Model' {
                    $SampleValue = 'E6500=D, SurfaceBook 2=M, HP Prodesk 640 G1=H, Virtual Machine=V'
                    $syncHash.cmbRuleAbbrPosition.IsEnabled = $true
                    $syncHash.txtRuleAbbrKey.IsEnabled = $true
                    $syncHash.lblAbbrExample.Content = "eg. $SampleValue"
                    $syncHash.cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
                }
            }
            #default to parameter setting
            If($syncHash.cmbRuleAbbrType.SelectedItem -eq $syncHash.Properties.AbbrType){
                $syncHash.txtRuleAbbrKey.Text = $syncHash.Properties.AbbrKey
            }Else{
                $syncHash.txtRuleAbbrKey.Text = $SampleValue
            }
        })
        #Open App secret popup in XAML
        #=================================
        If($syncHash.Properties.AppConnect){
            #Open-AppSecretPrompt
            $syncHash.btnGetIntuneDevices.IsEnabled = $false
            $syncHash.AppSecretPopup.IsOpen = $true

            $syncHash.btnPasteClipboard.Add_Click({
                $syncHash.pwdAppSecret.Password = Get-Clipboard
            })

            $syncHash.btnAppSecretCancel.Add_Click({
                $syncHash.AppSecretPopup.IsOpen = $false
                $syncHash.Properties.AppConnect = $false
                $syncHash.btnGetIntuneDevices.IsEnabled = $false
                Update-UIProgress -Runspace $synchash -StatusMsg ('User cancelled app connection. Close and reopen app to try again') -PercentComplete 100 -Color 'Red'
            })

            $syncHash.btnAppSecretSubmit.Add_Click({
                If([string]::IsNullOrEmpty($syncHash.pwdAppSecret.Password) ){
                    $syncHash.lblAppSecretMsg.content = "Invalid Secret, please try again or cancel"
                }Else{
                    $syncHash.AppSecretPopup.IsOpen = $false
                    $syncHash.btnGetIntuneDevices.IsEnabled = $true
                }
            })
        }
        #Collapse all features until connected
        $syncHash.tabDetails.Visibility = 'Collapsed'
        $syncHash.tabRenamer.Visibility = 'Collapsed'
        $syncHash.tabStale.Visibility = 'Collapsed'
        If($syncHash.Properties.ManageStaleDevices -eq $true){
            $syncHash.tabStale.Visibility = 'Visible'
        }Else{
            $syncHash.tabStale.Visibility = 'Collapsed'
        }
        #default load option

        #disable pagination on startup
        $syncHash.btnIntuneDevicePreviousPage.Visibility = 'Hidden'
        $syncHash.btnIntuneDeviceNextPage.Visibility = 'Hidden'
        $syncHash.txtIntuneDevicePageStatus.Visibility = 'Hidden'
        $syncHash.btnStaleDevicePreviousPage.Visibility = 'Hidden'
        $syncHash.btnStaleDeviceNextPage.Visibility = 'Hidden'
        $syncHash.txtStaleDevicePageStatus.Visibility = 'Hidden'
        $synchash.listIntuneDevices.Height = 650
        $synchash.listStaleDevices.Height = 650
        <# when pagination is enabled
            $synchash.listIntuneDevices.Height = 618
            $synchash.listStaleDevices.Height = 618
        #>
        $syncHash.txtDevicePrefix.text = $syncHash.Properties.DevicePrefix

        #set button to disabled until an actions happens
        $syncHash.btnRefreshList.IsEnabled = $false
        $syncHash.btnAssignUser.IsEnabled = $false
        $syncHash.btnHardwareDeviceInfo.IsEnabled = $false
        $syncHash.btnViewIntuneAssignments.IsEnabled = $false
        # BUTTON CONTROLS
        #=================================
        $syncHash.btnBack.Add_Click({
            Switch-UITabItem -TabControlObject $syncHash.menuNavigation -Name 'Devices'
        })

        #get sample text and convert it using the regex rules

        $syncHash.btnTestSample.Add_Click({
            $TestSample = @{Query=$syncHash.txtSample.Text}
            $TestRules=@{}
            if($syncHash.txtRuleRegex1.text){$TestRules.Add('RuleRegex1',$syncHash.txtRuleRegex1.text)}
            if($syncHash.txtRuleRegex2.text){$TestRules.Add('RuleRegex2',$syncHash.txtRuleRegex2.text)}
            if($syncHash.txtRuleRegex3.text){$TestRules.Add('RuleRegex3',$syncHash.txtRuleRegex3.text)}
            if($syncHash.txtRuleRegex4.text){$TestRules.Add('RuleRegex4',$syncHash.txtRuleRegex4.text)}
            If($TestRules.count -gt 0){                     $TestSample += @{RegexRules=$TestRules}}
            If($syncHash.cmbRuleAbbrType.Text -ne 'No Abbr'){     $TestSample += @{AbbrType=$syncHash.cmbRuleAbbrType.text}
                If($syncHash.txtRuleAbbrKey.Text.Length -gt 0){   $TestSample += @{device='localhost';AbbrKey=$syncHash.txtRuleAbbrKey.text}}
            }
            If($syncHash.cmbRuleAbbrPosition.SelectedItem){       $TestSample += @{AbbrPos=$syncHash.cmbRuleAbbrPosition.SelectedItem}}
            If($syncHash.txtRulePrefix.Text.Length -gt 0){        $TestSample += @{Prefix=$syncHash.txtRulePrefix.Text}}
            If($syncHash.cmbRuleAddDigits.SelectedItem){          $TestSample += @{AddDigits=$syncHash.cmbRuleAddDigits.SelectedItem}}
            If($syncHash.cmbRuleDigitPosition.SelectedItem){      $TestSample += @{DigitPos=$syncHash.cmbRuleDigitPosition.SelectedItem}}
            $syncHash.txtResults.Text = (Get-NewDeviceName @TestSample)
        })

        $syncHash.btnGetIntuneDevices.Content = 'Connect'

        #action for connect button
        $syncHash.btnGetIntuneDevices.Add_Click({
            $this.IsEnabled = $false
             #clear current list
             $syncHash.btnGetIntuneDevices.Dispatcher.Invoke("Normal",[action]{
                $syncHash.txtSearchIntuneDevices.Foreground = 'Gray'
                $syncHash.txtSearchIntuneDevices.Text = 'Search...'
                $syncHash.listIntuneDevices.Items.Clear()
            })

            Update-UIProgress -Runspace $synchash -StatusMsg "Connecting to Microsoft Graph Api..." -Indeterminate

            If($syncHash.Properties.AppConnect)
            {
                If([string]::IsNullOrEmpty($syncHash.pwdAppSecret.Password) ){
                    Update-UIProgress -Runspace $synchash -StatusMsg "Unable to retrieve app secret." -Indeterminate
                }
                <#
                #using MSAL module
                $AppConnectionDetails = @{
                    'TenantId'     = $syncHash.Properties.TenantId
                    'ClientId'     = $syncHash.Properties.ApplicationId
                    'ClientSecret' = $syncHash.pwdAppSecret.Password | ConvertTo-SecureString -AsPlainText -Force
                }
                $syncHash.Data.AuthToken = Get-MsalToken @AppConnectionDetails
                Connect-MgGraphApp -AppId $syncHash.Properties.ApplicationId
                #>
                $AppConnectionDetails = @{
                    'TenantID'    = $syncHash.Properties.TenantId
                    'AppId'     = $syncHash.Properties.ApplicationId
                    'AppSecret' = ConvertTo-SecureString $syncHash.pwdAppSecret.Password -AsPlainText
                    'CloudEnvironment' = $syncHash.Properties.Environment
                }

                #Connect-MgGraphApp @AppConnectionDetails
                $syncHash.Data.AuthToken = Get-IDMGraphAppAuthToken @AppConnectionDetails
                $syncHash.Data.ConnectAs = (Connect-IDMGraphApp -CloudEnvironment $syncHash.Properties.Environment -AppAuthToken $syncHash.Data.AuthToken).AppName

                $syncHash.Data.ConnectedUPN = $syncHash.Properties.ApplicationId
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Connected to MSGraph using appid: {0}" -f $syncHash.Properties.ApplicationId) -Type Start

                #globalize token for function usage
                #$Global:AuthToken = $syncHash.Data.AuthToken
                $syncHash.txtAuthTokenExpireDate.text = $syncHash.Data.AuthToken.ExpiresOn
            }
            Else{
                #minimize the UI to allow for login
                $syncHash.Window.WindowState = 'Minimized'
                <#
                try{
                    Connect-MgGraph -Environment $syncHash.Properties.Environment -NoWelcome
                    $syncHash.Data.ConnectedUPN = (Get-MgContext).Account
                }
                Catch{
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Failed to connect to MSGraph using account: {0}" -f $syncHash.Data.ConnectedUPN) -Type Error
                    Close-UIMainWindow
                    return
                }
                #>
                
                #connect with Interactive login. Use Connect-MgGraphApp to set the graph endpoint globally
                try{
                    $syncHash.Data.ConnectAs = (Connect-IDMGraphApp -CloudEnvironment $syncHash.Properties.Environment).Account
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Connected to MSGraph using account: {0}" -f $syncHash.Data.ConnectAs) -Type Start
                    $syncHash.txtAuthTokenExpireDate.text = 'Not Applicable'
                }
                Catch{
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Failed to connect to MSGraph using account: {0}" -f $syncHash.Data.ConnectedUPN) -Type Error
                    Close-UIMainWindow
                    return
                }
                $syncHash.Window.WindowState = 'Normal'
                $syncHash.Window.Topmost = $true
            }

            If($syncHash.Properties.AppConnect){
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Successfully connected to Azure Entra with Auth Token: {0}" -f ($syncHash.Data.AuthToken.Authorization).replace('Bearer','').Trim()) -Type Start
            }

            
            If($null -ne $syncHash.Data.ConnectAs)
            {
                $syncHash.btnGetIntuneDevices.Content = 'Get Devices'
                $syncHash.txtGraphConnectAs.text = $syncHash.Data.ConnectAs
                $syncHash.txtGraphConnectAs.Foreground = 'Green'
                $syncHash.btnRefreshList.IsEnabled = $true
                $syncHash.btnGetUsers.IsEnabled = $true
                #Put window back to its normal size if minimized

                Update-UIProgress -Runspace $synchash -StatusMsg ('Searching for managed [{0}] devices...' -f $syncHash.properties.DevicePlatform) -Indeterminate

                #populate Autopilot profiles
                If($syncHash.Properties.AutopilotSupported){
                    $syncHash.Data.AutopilotProfiles = Get-IDMAutopilotProfile
                    Add-UIList -Runspace $syncHash -ItemsList $syncHash.Data.AutopilotProfiles -DropdownObject $syncHash.cmbAPProfile -Identifier 'displayName'
                }

                #populate device category
                If($syncHash.Data.DeviceCategories = Get-IDMDeviceCategory){
                    Add-UIList -Runspace $syncHash -ItemsList $syncHash.Data.DeviceCategories -DropdownObject $syncHash.cmbDeviceCategoryList -Identifier 'displayName'
                }

                #grab all managed devices
                #build device query
                $DeviceParams = @{}
                If($syncHash.Properties.DevicePlatform){
                    $DeviceParams += @{Platform=$syncHash.Properties.DevicePlatform}
                }
                If($syncHash.txtDevicePrefix.text.length -gt 0){
                    $DeviceParams += @{Filter=$syncHash.txtDevicePrefix.text}
                }
                #encapsulate device in array (incase there is only 1)
                #$syncHash.Data.IntuneDevices = @(Get-IDMDevice @DeviceParams -Expand)
                #$syncHash.Data.IntuneDevices = @()
                #$syncHash.Data.IntuneDevices += Get-RunspaceIntuneDevices -Runspace $syncHash @DeviceParams -Expand -ListObject $syncHash.listIntuneDevices
                Get-RunspaceIntuneDevices -Runspace $syncHash -ParentRunspace $syncHash @DeviceParams -Expand -ListObject $syncHash.listIntuneDevices
                
                If($syncHash.Data.IntuneDevices.count -gt 0)
                {
                    $syncHash.tabDetails.Visibility = 'Visible'
                    If($syncHash.Properties.AllowRename -eq $true){$syncHash.tabRenamer.Visibility = 'Visible'}
                }

                If($syncHash.Data.IntuneDevices.count -eq 0)
                {
                    Update-UIProgress -Runspace $synchash -StatusMsg ('No devices found') -PercentComplete 100 -Color 'Red'
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("No managed devices found. Log into a different Azure tenant or credentials to retrieve managed devices") -Type Error
                }
                ElseIf($syncHash.Data.IntuneDevices.count -gt 1000){
                    Update-UIProgress -Runspace $synchash -StatusMsg ("WARNING: More than 1000 devices were found! Use prefix to reduce search criteria and click the cloud sync button again") -PercentComplete 100 -Color 'Red'
                }
                ElseIf(($syncHash.txtDevicePrefix.text.length -ge 1)){
                    Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} managed devices based on criteria [Search device prefix that starts with "{1}"]' -f $syncHash.Data.IntuneDevices.count,$syncHash.txtDevicePrefix.text) -PercentComplete 100 -Color 'Green'
                }
                Else{
                    Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} managed devices' -f $syncHash.Data.IntuneDevices.count) -PercentComplete 100 -Color 'Green'
                }
            }
            $this.IsEnabled = $true
        })

        # Select a Device List
        #========================
        #Update UI when Device is selected
        $syncHash.listIntuneDevices.Add_SelectionChanged({
            $syncHash.btnViewIntuneAssignments.IsEnabled = $True
            $syncHash.btnHardwareDeviceInfo.IsEnabled = $True
            $syncHash.txtSelectedDevice.text = $syncHash.listIntuneDevices.SelectedItem
            If($syncHash.listIntuneDevices.SelectedItem.length -gt 0)
            {
                $syncHash.Data.SelectedDevice = $syncHash.Data.IntuneDevices | Where {$_.deviceName -eq $syncHash.listIntuneDevices.SelectedItem}
                $syncHash.Data.DeviceStatus = Get-IDMDevicePendingActions -DeviceID $syncHash.Data.SelectedDevice.id
                
                If($syncHash.Properties.AutopilotSupported){
                    #Uses module: WindowsAutoPilotIntune
                    $syncHash.Data.AutopilotDevice = Get-IDMAutopilotDevice -Serial $syncHash.Data.SelectedDevice.serialNumber -Expand
                    #$syncHash.Data.AutopilotDevice = Get-IDMAutopilotDevice -Serial $syncHash.Data.SelectedDevice.serialNumber -Expand -verbose
                }

                $syncHash.cmbDeviceCategoryList.SelectedItem = $syncHash.Data.SelectedDevice.deviceCategoryDisplayName
                If($syncHash.Data.SelectedDevice.userPrincipalName){
                    $syncHash.Data.AssignedUser = Get-IDMAzureUser -UPN $syncHash.Data.SelectedDevice.userPrincipalName
                }Else{
                    $syncHash.Data.AssignedUser = $null
                }

                Switch($syncHash.Data.SelectedDevice.joinType){
                    'hybridAzureADJoined' {
                            $syncHash.txtDeviceJoinType.Text = "Hybrid Azure Entra Joined"
                            If(Test-RSATModule -and Test-IsDomainJoined)
                            {
                                Try{
                                    $Global:ADComputer = Get-ADComputer -Identity $syncHash.listIntuneDevices.SelectedItem -ErrorAction Stop
                                    $syncHash.txtStatus.Text = ''
                                    $syncHash.txtStatus.Foreground = 'Green'
                                }
                                Catch{
                                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Failed to get AD object [{1}]. Error: {0}" -f $_.Exception.Message,$syncHash.listIntuneDevices.SelectedItem) -Type Error
                                    $syncHash.txtStatus.Text = 'Failed to retrieve AD object. Please see log for more details'
                                    $syncHash.txtStatus.Foreground = 'Red'
                                }
                            }
                            Else {
                                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("This device must be joined to the domain and have RSAT installed to query AD computer object [{0}]" -f $syncHash.listIntuneDevices.SelectedItem) -Type Warning
                                $syncHash.txtStatus.Text = ("This device must be joined to the domain and have RSAT installed to query AD computer object [{0}]" -f $syncHash.listIntuneDevices.SelectedItem)
                                $syncHash.txtStatus.Foreground = 'Orange'
                            }
                            (Get-UIProperty -HashName $syncHash "ADComputer" -Wildcard) | Set-UIElement -Enable:$true -ErrorAction SilentlyContinue
                    }
                    'azureADJoined' {
                        $syncHash.txtDeviceJoinType.Text = "Azure Entra Joined"
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("On-prem AD options are not available for Azure Entra joined devices [{0}]" -f $syncHash.listIntuneDevices.SelectedItem) -Type Warning
                        #$syncHash.txtStatus.Foreground = 'Orange'
                        #(Get-UIProperty -HashName $syncHash "ADComputer" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
                    }
                    'azureADRegistered' {
                        $syncHash.txtDeviceJoinType.Text = "Azure Entra Registered"
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Limited options are available for Azure Entra registered device [{0}]" -f $syncHash.listIntuneDevices.SelectedItem) -Type Warning
                        #(Get-UIProperty -HashName $syncHash "ADComputer" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
                    }
                }
                #check if system running device is joined to the domain and has RSAT tools installed
                $DeviceAsString = $syncHash.Data.SelectedDevice | Select deviceName,osVersion,manufacturer,model,serialNumber,joinType,deviceEnrollmentType,userDisplayName,userPrincipalName | Out-String
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Selected device:`n{0}" -f $DeviceAsString)

                $syncHash.txtDeviceIntuneId.Text = $syncHash.Data.SelectedDevice.id
                $syncHash.txtDeviceAzureId.Text = $syncHash.Data.SelectedDevice.azureADDeviceId
                $syncHash.txtDeviceAzureObjectId.Text = $syncHash.Data.SelectedDevice.azureADObjectId
                $syncHash.txtDeviceSerial.Text = $syncHash.Data.SelectedDevice.serialNumber
                $syncHash.txtDeviceOSver.Text = $syncHash.Data.SelectedDevice.osVersion
                If($syncHash.Data.SelectedDevice.isCompliant){
                    $syncHash.lblDeviceComplianceStatus.Foreground = 'Black'
                    $syncHash.chkDeviceComplianceStatus.IsChecked = $true
                }Else{
                    $syncHash.lblDeviceComplianceStatus.Foreground = 'Gray'
                    $syncHash.chkDeviceComplianceStatus.IsChecked = $false
                }


                #Detemine if device is co-managed
                If($syncHash.Data.SelectedDevice.deviceEnrollmentType -eq 'windowsCoManagement'){
                    $syncHash.lblDeviceCoManagedStatus.Foreground = 'Black'
                    $syncHash.chkDeviceCoManagedStatus.IsChecked = $true
                }Else{
                    $syncHash.lblDeviceCoManagedStatus.Foreground = 'Gray'
                    $syncHash.chkDeviceCoManagedStatus.IsChecked = $false
                }

                 #Detemine if device is an AVD host
                 If($syncHash.Data.SelectedDevice.skuFamily -eq 'EnterpriseMultisession'){
                    $syncHash.lblDeviceMultiSession.Foreground = 'Black'
                    $syncHash.chkDeviceMultiSession.IsChecked = $true
                }Else{
                    $syncHash.lblDeviceMultiSession.Foreground = 'Gray'
                    $syncHash.chkDeviceMultiSession.IsChecked = $false
                }

                #https://docs.microsoft.com/en-us/graph/api/resources/intune-devices-managementagenttype?view=graph-rest-1.0
                switch($syncHash.Data.SelectedDevice.managementAgent){
                    'configurationManagerClientMdm' {$syncHash.txtDeviceMDM.Text = 'ConfigMgr & MDM'}
                    'configurationManagerClient' {$syncHash.txtDeviceMDM.Text = 'ConfigMgr'}
                    'intuneClient' {$syncHash.txtDeviceMDM.Text = 'Intune MDM'}
                    'Mdm' {$syncHash.txtDeviceMDM.Text = 'Intune MDM'}
                    'jamf' {$syncHash.txtDeviceMDM.Text = 'Jamf MDM'}
                    'googleCloudDevicePolicyController' {$syncHash.txtDeviceMDM.Text = 'Google CloudDPC.'}
                    default {$syncHash.txtDeviceMDM.Text = 'Unknown'}
                }

                If($syncHash.Properties.AutopilotSupported){

                    #determine if device Autopilot ready...meaning its hardware id has been uploaded with Autopilot devices
                    If($syncHash.Data.AutopilotDevice){
                        $syncHash.lblDeviceAutopilotReadyStatus.Foreground = 'Black'
                        $syncHash.chkDeviceAutopilotReadyStatus.IsChecked = $true
                        #update autopilot group tag
                        $syncHash.txtAPProfileGroupTag.text = $syncHash.Data.AutopilotDevice.groupTag
                        $syncHash.cmbAPProfile.SelectedItem = $syncHash.Data.AutopilotDevice.deploymentProfile.displayName
                    }Else{
                        $syncHash.lblDeviceAutopilotReadyStatus.Foreground = 'Gray'
                        $syncHash.chkDeviceAutopilotReadyStatus.IsChecked = $false
                        $syncHash.txtAPProfileGroupTag.text = $Null
                        $syncHash.cmbAPProfile.SelectedItem = $Null
                    }
                    
                    (Get-UIProperty -HashName $syncHash "APProfile" -Wildcard) | Set-UIElement -Enable:($syncHash.chkDeviceAutopilotReadyStatus.IsChecked -eq $True) -ErrorAction SilentlyContinue
                
                    #determine if device has been autopiloted (look for ZTDID and profile type). Is there a better way???
                    If($syncHash.Data.SelectedDevice.physicalIds -match '\[ZTDID\]' -and $syncHash.Data.SelectedDevice.profileType -ne 'RegisteredDevice')
                    {
                        $syncHash.lblDeviceAutopilotedStatus.Foreground = 'Black'
                        $syncHash.txtDeviceAutopilotedStatus.Foreground = 'Green'
                        $syncHash.txtDeviceAutopilotedStatus.Text = 'Online Profile'
                    }
                    ElseIf($syncHash.Data.AutopilotDevice)
                    {
                        $syncHash.lblDeviceAutopilotedStatus.Foreground = 'Black'
                        $syncHash.txtDeviceAutopilotedStatus.Foreground = 'Blue'
                        $syncHash.txtDeviceAutopilotedStatus.Text = $syncHash.Data.AutopilotDevice.deploymentProfileAssignmentStatus
                    }
                    ElseIf($syncHash.Data.SelectedDevice.enrollmentProfileName -like 'OfflineAutopilotprofile*')
                    {
                        $syncHash.lblDeviceAutopilotedStatus.Foreground = 'Black'
                        $syncHash.txtDeviceAutopilotedStatus.Foreground = 'Blue'
                        $syncHash.txtDeviceAutopilotedStatus.Text = 'Offline JSON'
                        $syncHash.cmbAPProfile.SelectedItem = ($syncHash.Data.AutopilotProfiles | Where id -eq ($syncHash.Data.SelectedDevice.enrollmentProfileName -replace 'OfflineAutopilotprofile-','')).displayName
                    }
                    Else
                    {
                        $syncHash.lblDeviceAutopilotedStatus.Foreground = 'Gray'
                        $syncHash.txtDeviceAutopilotedStatus.Foreground = 'Gray'
                        $syncHash.txtDeviceAutopilotedStatus.Text = 'Not Performed'
                    }
                }else {
                    $syncHash.chkDeviceAutopilotReadyStatus.IsChecked = $false
                    $syncHash.chkDeviceAutopilotReadyStatus.Visibility = 'Hidden'
                    $syncHash.lblDeviceAutopilotReadyStatus.Foreground = 'Gray'
                    $syncHash.txtAPProfileGroupTag.text = $Null
                    $syncHash.txtAPProfileGroupTag.IsEnabled = $false
                    $syncHash.cmbAPProfile.SelectedItem = $Null
                    $syncHash.cmbAPProfile.IsEnabled = $false
                    $syncHash.lblDeviceAutopilotedStatus.Foreground = 'Gray'
                    $syncHash.txtDeviceAutopilotedStatus.Foreground = 'Gray'
                    $syncHash.txtDeviceAutopilotedStatus.Text = 'Not Supported'
                }
                #Display Assigned User
                $syncHash.txtAssignedUserName.text = $syncHash.Data.AssignedUser.displayName
                $syncHash.txtAssignedUserUPN.text = $syncHash.Data.AssignedUser.userPrincipalName
                $syncHash.txtAssignedUserEmail.text = $syncHash.Data.AssignedUser.mail
                $syncHash.txtAssignedUserId.text = $syncHash.Data.AssignedUser.id

                If($syncHash.Data.AssignedUser.signInSessionsValidFromDateTime){
                    $syncHash.txtAssignedUserLastSignIn.text = [datetime]$syncHash.Data.AssignedUser.signInSessionsValidFromDateTime
                }Else{
                    $syncHash.txtAssignedUserLastSignIn.text = ''
                }

                If($syncHash.Data.AssignedUser.onPremisesSyncEnabled -eq $True)
                {
                    $syncHash.lblAssignedUserADSyncd.Foreground = 'Black'
                    $syncHash.chkAssignedUserADSyncd.IsChecked = $true
                    $syncHash.txtAssignedUserDN.text = $syncHash.Data.AssignedUser.onPremisesDistinguishedName
                    $syncHash.lblAssignedUserDN.Visibility = 'Visible'
                    $syncHash.txtAssignedUserDN.Visibility = 'Visible'

                    $syncHash.Data.ADUser = '' | Select DistinguishedName,Name,SamAccountName,UserPrincipalName,SID
                    $syncHash.Data.ADUser.DistinguishedName = $syncHash.Data.AssignedUser.onPremisesDistinguishedName
                    $syncHash.Data.ADUser.Name = $syncHash.Data.AssignedUser.displayName
                    $syncHash.Data.ADUser.SamAccountName = $syncHash.Data.AssignedUser.onPremisesSamAccountName
                    $syncHash.Data.ADUser.UserPrincipalName = $syncHash.Data.AssignedUser.onPremisesUserPrincipalName
                    $syncHash.Data.ADUser.SID = $syncHash.Data.AssignedUser.onPremisesSecurityIdentifier

                    $syncHash.txtADUserDN.text = $syncHash.Data.AssignedUser.onPremisesDistinguishedName
                }
                Else
                {
                    $syncHash.lblAssignedUserADSyncd.Foreground = 'Gray'
                    $syncHash.chkAssignedUserADSyncd.IsChecked = $false
                    $syncHash.txtAssignedUserDN.text = ''
                    $syncHash.lblAssignedUserDN.Visibility = 'Hidden'
                    $syncHash.txtAssignedUserDN.Visibility = 'Hidden'
                    $syncHash.Data.ADUser = $Null
                    $syncHash.txtADUserDN.text = ''
                }

                #update AD user properties
                (Get-UIProperty -HashName $syncHash "ADUser" -Wildcard) | 
                    Set-UIElement -Enable:($syncHash.Data.AssignedUser.onPremisesSyncEnabled -eq $True) -ErrorAction SilentlyContinue


                #$syncHash.txtAssignedUser.text = $syncHash.Data.AssignedUser.$($syncHash.cmbUserDisplayOptions.SelectedItem)
                If($null -ne $syncHash.Data.DeviceStatus){
                    $statusMsg = @()
                    switch($syncHash.Data.DeviceStatus.actionName){
                        'setDeviceName' {$statusMsg += "Device is pending rename to:{0}" -f "$($syncHash.Data.DeviceStatus.passcode)" ;$FontColor = 'Red'}
                        'rebootNow' {$statusMsg += "Device is pending reboot";$FontColor = 'Red'}
                    }
                    $syncHash.txtDeviceStatus.Visibility='Visible'
                    $syncHash.txtDeviceStatus.Text = $statusMsg -join "`n"
                    $syncHash.txtDeviceStatus.Foreground = $FontColor
                }Else{
                    $syncHash.txtDeviceStatus.Visibility='Hidden'
                }

                #get value of extension attribute
                $syncHash.txtDeviceExtensionValue.Text = $syncHash.Data.SelectedDevice.extensionAttributes | 
                    Select -ExpandProperty $syncHash.cmbDeviceExtensions.SelectedItem
                
                If($syncHash.txtDeviceExtensionValue.Text.length -eq 0){
                    $syncHash.btnDeviceExtensionChange.IsEnabled = $false
                }Else{
                    $syncHash.btnDeviceExtensionChange.IsEnabled = $True
                }
            }
            Update-UIProgress -Runspace $synchash -StatusMsg ("You selected device [{0}]`nThe user assigned is [{1}]" -f $syncHash.Data.SelectedDevice.deviceName,$syncHash.Data.AssignedUser.userPrincipalName) -PercentComplete 100 -Color (Get-UIRandomColor)
        })

        # Refresh Device List
        #========================
        $syncHash.btnRefreshList.Add_Click({
            $this.IsEnabled = $false
            Update-UIProgress -Runspace $synchash -StatusMsg ('Refreshing managed [{0}] device list...' -f $syncHash.properties.DevicePlatform) -Indeterminate -Color Blue

            #clear current list
            $syncHash.btnRefreshList.Dispatcher.Invoke("Normal",[action]{
                $syncHash.txtSearchIntuneDevices.Foreground = 'Gray'
                $syncHash.txtSearchIntuneDevices.Text = 'Search...'
                $syncHash.listIntuneDevices.Items.Clear()
            })

            #grab all managed devices
            $DeviceParams = @{Expand=$true}
            If($syncHash.Properties.DevicePlatform){
                $DeviceParams += @{Platform=$syncHash.Properties.DevicePlatform}
            }
            If($syncHash.txtDevicePrefix.text.length -gt 0){
                $DeviceParams += @{Filter=$syncHash.txtDevicePrefix.text}
            }
            #refresh list
            Get-RunspaceIntuneDevices -Runspace $syncHash -ParentRunspace $syncHash @DeviceParams -ListObject $syncHash.listIntuneDevices
            
            If($syncHash.Data.IntuneDevices.count -gt 0)
            {
                $syncHash.tabDetails.Visibility = 'Visible'
                $syncHash.tabRenamer.Visibility = 'Visible'

                Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} devices the meet platform requirement [{1}]' -f $syncHash.Data.IntuneDevices.count,$syncHash.properties.DevicePlatform) -PercentComplete 100
            }
            Else{
                Update-UIProgress -Runspace $synchash -StatusMsg ('No devices found') -PercentComplete 100 -Color 'Red'
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("No devices found. Log into a different Azure tenant or credentials to retrieve registered devices") -Type Error
            }
            $this.IsEnabled = $true
        })


        If($syncHash.Properties.AutopilotSupported){
            $syncHash.btnAPProfileExport.Add_Click({
                $this.IsEnabled = $false
                $syncHash.btnAPProfileChange.Dispatcher.Invoke("Normal",[action]{
                    If($syncHash.cmbAPProfile.SelectedItem){
                        $SelectedAPProfile = $syncHash.Data.AutopilotProfiles | where DisplayName -eq $syncHash.cmbAPProfile.SelectedItem
                        $SelectedAPProfile | ConvertTo-AutopilotConfigurationJSON | Out-File "$env:UserProfile\Desktop\AutopilotConfigurationFile.json" -Encoding ASCII -Force

                        $Message=("Autopilot Profile [{0}] was exported to: [{1}]" -f $SelectedAPProfile.displayName,"$env:UserProfile\Desktop\AutopilotConfigurationFile.json")
                        $syncHash.txtStatus.Text = $Message
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message $Message
                    }
                })
                $this.IsEnabled = $true
            })
        }else {
            $syncHash.btnAPProfileExport.IsEnabled = $false
        }

        $syncHash.btnHardwareDeviceInfo.Add_Click({
            $this.IsEnabled = $false
            $syncHash.btnHardwareDeviceInfo.Dispatcher.Invoke("Normal",[action]{
                If($syncHash.Data.SelectedDevice){
                    If($syncHash.chkHardwareDeviceRemote.IsChecked -eq $true){
                        Try{
                            $DeviceInfo = Get-PlatformInfo -DeviceName $syncHash.Data.SelectedDevice.deviceName -ErrorAction Stop
                        }
                        Catch{
                            $syncHash.txtStatus.Foreground = 'Red'
                            $syncHash.txtStatus.Text =('{0}' -f $_.exception.message)
                        }

                        $DeviceData = New-Object PSObject
                        Foreach($p in ($syncHash.Data.SelectedDevice | Get-Member -MemberType NoteProperty) )
                        {
                            If($syncHash.Data.SelectedDevice.($p.name) -is [DateTime]){
                                $DeviceData | Add-Member NoteProperty $p.name -Value ($syncHash.Data.SelectedDevice.($p.name) -as [DateTime])
                            }Else{
                                $DeviceData | Add-Member NoteProperty $p.name -Value $syncHash.Data.SelectedDevice.($p.name)
                            }
                        }
                        #$AADObjects | Where displayName -eq 'DTOLAB-46VEYL1'
                        If($DeviceInfo){
                            Foreach($p in ($DeviceInfo | Get-Member -MemberType NoteProperty))
                            {
                                If($p.name -notin ($DeviceData | Get-Member -MemberType NoteProperty).Name){
                                    If($DeviceInfo.($p.name) -is [DateTime]){
                                        $DeviceData | Add-Member NoteProperty $p.name -Value ($DeviceInfo.($p.name) -as [DateTime])
                                    }Else{
                                        $DeviceData | Add-Member NoteProperty $p.name -Value $DeviceInfo.($p.name)
                                    }

                                }
                            }
                            # Add the object to our array of output objects
                        }
                    }

                    #build default excludes
                    $excludeProperties = @('uri','configurationManagerClientHealthState','configurationManagerClientEnabledFeatures','configurationManagerClientInformation','usersLoggedOn',
                                        'extensionAttributes','physicalIds','hardwareInformation','totalStorageSpaceInBytes','freeStorageSpaceInBytes',
                                        'activationLockBypassCode','iccid','udid','meid','imei','phoneNumber','subscriberCarrier','jailBroken',
                                        'androidSecurityPatchLevel','chromeOSDeviceInfo','azureActiveDirectoryDeviceId',
                                        'remoteAssistanceSessionErrorDetails','remoteAssistanceSessionUrl')
                    #add to exclude based on OS
                    Switch($syncHash.Data.SelectedDevice.operatingSystem){
                        'Windows'{$excludeProperties += @('uri','configurationManagerClientHealthState','configurationManagerClientEnabledFeatures','configurationManagerClientInformation',
                                                        'activationLockBypassCode','iccid','udid','meid','imei','phoneNumber','subscriberCarrier','jailBroken',
                                                        'androidSecurityPatchLevel','chromeOSDeviceInfo')}
                        default {$excludeProperties += @('CMClientHealthStatus','CoManagedWorkloads_inventory','CoManagedWorkloads_modernApps','CoManagedWorkloads_resourceAccess',
                                                        'CoManagedWorkloads_deviceConfiguration','CoManagedWorkloads_compliancePolicy','CoManagedWorkloads_windowsUpdateForBusiness',
                                                        'CoManagedWorkloads_endpointProtection','CoManagedWorkloads_officeApps',
                                                        'DeviceGuardState','DeviceGuardStatus','CredentialGuardStatus','BitlockerEncrypted',
                                                        'autopilotEnrolled','windowsActiveMalwareCount','windowsRemediatedMalwareCount')}
                    }
                    #collect properties
                    $Data = ($syncHash.Data.SelectedDevice | Select *, @{n="LastLogOnDateTime";e={$_.usersLoggedOn.LastLogOnDateTime}},
                                                                    @{n="CMClientHealthStatus";e={If($_.configurationManagerClientHealthState.State -eq 'healthy'){'healthy'}Else{$_.configurationManagerClientHealthState.errorCode}}},
                                                                    @{n="CoManagedWorkloads_inventory";e={$_.configurationManagerClientEnabledFeatures.inventory}},
                                                                    @{n="CoManagedWorkloads_modernApps";e={$_.configurationManagerClientEnabledFeatures.modernApps}},
                                                                    @{n="CoManagedWorkloads_resourceAccess";e={$_.configurationManagerClientEnabledFeatures.resourceAccess}},
                                                                    @{n="CoManagedWorkloads_deviceConfiguration";e={$_.configurationManagerClientEnabledFeatures.deviceConfiguration}},
                                                                    @{n="CoManagedWorkloads_compliancePolicy";e={$_.configurationManagerClientEnabledFeatures.compliancePolicy}},
                                                                    @{n="CoManagedWorkloads_windowsUpdateForBusiness";e={$_.configurationManagerClientEnabledFeatures.windowsUpdateForBusiness}},
                                                                    @{n="CoManagedWorkloads_endpointProtection";e={$_.configurationManagerClientEnabledFeatures.endpointProtection}},
                                                                    @{n="CoManagedWorkloads_officeApps";e={$_.configurationManagerClientEnabledFeatures.officeApps}},
                                                                    @{n="DeviceGuardState";e={$_.hardwareInformation.deviceGuardVirtualizationBasedSecurityHardwareRequirementState}},
                                                                    @{n="DeviceGuardStatus";e={$_.hardwareInformation.deviceGuardVirtualizationBasedSecurityState}},
                                                                    @{n="CredentialGuardStatus";e={$_.hardwareInformation.deviceGuardLocalSystemAuthorityCredentialGuardState}},
                                                                    @{n="LicensingStatus";e={$_.hardwareInformation.deviceLicensingStatus}},
                                                                    @{n="SharedDevice";e={$_.hardwareInformation.isSharedDevice}},
                                                                    @{n="BitlockerEncrypted";e={$_.hardwareInformation.isEncrypted}},
                                                                    @{n="StorageSpaceTotal";e={ ConvertTo-ByteString $_.totalStorageSpaceInBytes}},
                                                                    @{n="StorageSpaceFree";e={ ConvertTo-ByteString $_.freeStorageSpaceInBytes}} `
                                                                    -ExcludeProperty $excludeProperties).psobject.properties | foreach -begin { $h=@{} } -process { If($_.Value -as [DateTime]){$h."$($_.Name)" = ($_.Value -as [DateTime])}Else{$h."$($_.Name)" = $_.Value} } -end { $h }
                    $syncHash.lstHardwareDevice.ItemsSource = ($Data.GetEnumerator() | Sort-Object Name)
                    #$DataString = ($Data.GetEnumerator() | Sort-Object Name | Format-Table)
                    $DataString = $Data.GetEnumerator() | Sort-Object Name | Format-Table -AutoSize | Out-String
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Device Details:`n{0}" -f $DataString)
                }
                Else{
                    $syncHash.txtStatus.Foreground = 'Red'
                    $syncHash.txtStatus.Text = 'You must select a device first from the Device Tab'
                }
            })
            Update-UIProgress -Runspace $synchash -StatusMsg ("Hardware information retrieved successfully for device [{0}]" -f $syncHash.Data.SelectedDevice.deviceName) -PercentComplete 100
            $this.IsEnabled = $true
        })

        # Update Category
        #========================
        $syncHash.btnDeviceCategoryChange.IsEnabled = $false
        $syncHash.cmbDeviceCategoryList.Add_SelectionChanged({
            If($syncHash.cmbDeviceCategoryList.SelectedItem -ne $syncHash.Data.SelectedDevice.deviceCategoryDisplayName){
                $syncHash.btnDeviceCategoryChange.IsEnabled = $true
            }Else{
                $syncHash.btnDeviceCategoryChange.IsEnabled = $false
            }
        })

        $syncHash.btnDeviceCategoryChange.Add_Click({
            $syncHash.btnDeviceCategoryChange.Dispatcher.Invoke("Normal",[action]{
                Try{
                    Set-IDMDeviceCategory -DeviceID $syncHash.Data.SelectedDevice.id -Category $syncHash.cmbDeviceCategoryList.SelectedItem
                    $syncHash.txtStatus.Foreground = 'Green'
                    $syncHash.txtStatus.Text = ("Updated device [{0}] category to [{1}]" -f $syncHash.Data.SelectedDevice.deviceName,$syncHash.cmbDeviceCategoryList.SelectedItem)
                }Catch{
                    $syncHash.txtStatus.Foreground = 'Red'
                    $syncHash.txtStatus.Text = ("Failed to assign category [{0}] to device [{1}]. {2}" -f $syncHash.cmbDeviceCategoryList.SelectedItem,$syncHash.Data.SelectedDevice.deviceName, $_.exception.message)
                }

            })

        })

        # Update Autopilot Group Tag
        #============================
        If($syncHash.Properties.AutopilotSupported)
        {
            $syncHash.btnAPProfileChange.Add_Click({
                $syncHash.btnAPProfileChange.Dispatcher.Invoke("Normal",[action]{
                    Try{
                        #uses module: WindowsAutoPilotIntune
                        Set-AutopilotDevice -id $syncHash.Data.AutopilotDevice.id -groupTag $syncHash.txtAPProfileGroupTag.text
                        #Set-IDMAutopilotDeviceTag -AutopilotID $syncHash.Data.AutopilotDevice.id -GroupTag $syncHash.txtAPProfileGroupTag.text
                        $syncHash.txtStatus.Foreground = 'Green'
                        $syncHash.txtStatus.Text = ("Updated Autopilot device [{0}] group tag to [{1}]" -f $syncHash.Data.SelectedDevice.deviceName,$syncHash.txtAPProfileGroupTag.text)
                    }Catch{
                        $syncHash.txtStatus.Foreground = 'Red'
                        $syncHash.txtStatus.Text = ("Failed to assign group tag [{0}] to device [{1}]. {2}" -f $syncHash.txtAPProfileGroupTag.text,$syncHash.Data.SelectedDevice.deviceName, $_.exception.message)
                    }
                })
            })
        }Else{
            $syncHash.btnAPProfileChange.IsEnabled = $false
        }

        # Retrieve users
        #============================
        $syncHash.btnGetUsers.Add_Click({
            $this.IsEnabled = $false
            Update-UIProgress -Runspace $synchash -StatusMsg ('Retrieving Azure Users...') -Indeterminate -Color Blue

            #clear current list
            $syncHash.btnGetUsers.Dispatcher.Invoke("Normal",[action]{
                $syncHash.listUsers.Items.Clear()
            })

            #search all users or if filtered
            If(($syncHash.txtDevicePrefix.text.length -gt 0) -and ($syncHash.txtSearchUser.text -ne 'Search...')){
                $syncHash.Data.AzureUsers = Get-IDMAzureUsers -Filter $syncHash.txtSearchUser.text -FilterBy SearchDisplayName
            }Else{
                $syncHash.Data.AzureUsers = Get-IDMAzureUsers
            }

            Add-UIList -ItemsList $syncHash.Data.AzureUsers -ListObject $syncHash.listUsers -Identifier 'userPrincipalName'

            If($syncHash.Data.AzureUsers.count -eq 0)
            {
                Update-UIProgress -Runspace $synchash -StatusMsg ('No users found') -PercentComplete 100 -Color 'Red'
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("No users found. Log into a different Azure tenant or credentials to retrieve Azure Entra users") -Type Error
            }
            ElseIf($syncHash.Data.AzureUsers.count -gt 1000){
                Update-UIProgress -Runspace $synchash -StatusMsg ("WARNING: More than 1000 users were found! Use search to reduce search criteria and click the cloud sync button again") -PercentComplete 100 -Color 'Red'
            }
            ElseIf(($syncHash.txtSearchUser.text.length -ge 1) -and ($syncHash.txtSearchUser.text -ne 'Search...')){
                Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} Azure Entra users based on criteria [Search "{1}" in user name]' -f $syncHash.Data.AzureUsers.count,$syncHash.txtSearchUser.text) -PercentComplete 100 -Color 'Green'
            }
            Else{
                Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} Azure Entra users' -f $syncHash.Data.AzureUsers.count) -PercentComplete 100 -Color 'Green'
            }

            #reset search (to allow search within current list)
            $syncHash.btnGetUsers.Dispatcher.Invoke("Normal",[action]{
                $syncHash.txtSearchUser.Foreground = 'Gray'
                $syncHash.txtSearchUser.Text = 'Search...'
            })

            $this.IsEnabled = $true
        })

        # Update Extension
        #============================
        $syncHash.btnDeviceExtensionChange.Add_Click({
            $syncHash.cmbDeviceExtensions.SelectedItem -match '\d+' | Out-Null
            $Id = $Matches[0]
            Try{
                Set-IDMAzureDeviceExtension -DeviceID $syncHash.Data.SelectedDevice.azureADObjectId -ExtensionID $Id -ExtensionValue $syncHash.txtDeviceExtensionValue.Text -ErrorAction Stop
                Update-UIProgress -Runspace $synchash -StatusMsg ('Successfully updated [{0}] to value [{1}]' -f $syncHash.cmbDeviceExtensions.SelectedItem,$syncHash.txtDeviceExtensionValue.Text) -PercentComplete 100 -Color 'Green'
            }Catch{
                Update-UIProgress -Runspace $synchash -StatusMsg ('Failed to updated [{0}] to value [{1}]: {2}' -f $syncHash.cmbDeviceExtensions.SelectedItem,$syncHash.txtDeviceExtensionValue.Text,$_) -PercentComplete 100 -Color 'Red'
            }
        })

        # Select a Extension Attributes
        #===============================
        #Update UI when Device is selected
        $syncHash.cmbDeviceExtensions.Add_SelectionChanged({
            $syncHash.txtDeviceExtensionValue.Text = $syncHash.Data.SelectedDevice.extensionAttributes | Select -ExpandProperty $syncHash.cmbDeviceExtensions.SelectedItem
            If($syncHash.txtDeviceExtensionValue.Text.length -eq 0){
                $syncHash.btnDeviceExtensionChange.IsEnabled = $false
            }Else{
                $syncHash.btnDeviceExtensionChange.IsEnabled = $true
            }
        })

        # Select a User from List
        #========================
        #Update UI when Device is selected
        $syncHash.listUsers.Add_SelectionChanged({
            $syncHash.Data.SelectedUser = ($syncHash.Data.AzureUsers | Where userPrincipalName -eq $syncHash.listUsers.SelectedItem)
            $syncHash.txtSelectedUserName.text = $syncHash.Data.SelectedUser.displayName
            $syncHash.txtSelectedUPN.text = $syncHash.Data.SelectedUser.userPrincipalName
            $syncHash.txtSelectedEMail.text = $syncHash.Data.SelectedUser.mail
            $syncHash.btnAssignUser.IsEnabled = $true
        })

        $syncHash.lstHardwareDevice.Add_SelectionChanged({
            Set-Clipboard -Value ($syncHash.lstHardwareDevice.SelectedItem.Name + ' : ' + $syncHash.lstHardwareDevice.SelectedItem.Value)
            Update-UIProgress -Runspace $synchash -StatusMsg ("Added [{0}] to clipboard" -f $syncHash.lstHardwareDevice.SelectedItem.Value) -PercentComplete 100
        })

        $syncHash.btnAssignUser.Add_Click({
            If($null -eq $syncHash.Data.SelectedDevice.deviceName){
                $syncHash.txtStatus.Foreground = 'Brown'
                $syncHash.txtStatus.Text = ("No device has been selected, you must select a device first!")
            }ElseIf($syncHash.Data.SelectedUser.userPrincipalName -eq $syncHash.Data.AssignedUser.userPrincipalName){
                $syncHash.txtStatus.Foreground = 'Brown'
                $syncHash.txtStatus.Text = ("User [{0}] is already assigned to [{1}]. Please select a different user..." -f $syncHash.Data.SelectedUser.userPrincipalName,$syncHash.Data.SelectedDevice.deviceName)
            }Else{
                $syncHash.btnAssignUser.Dispatcher.Invoke("Normal",[action]{
                    Try{
                        Set-IDMDeviceAssignedUser -DeviceID $syncHash.Data.SelectedDevice.id -UserId $syncHash.Data.SelectedUsers.id
                        $syncHash.txtStatus.Foreground = 'Green'
                        $syncHash.txtStatus.Text = ("Assigned user [{0}] to device [{1}]" -f $syncHash.Data.SelectedUser.userPrincipalName,$syncHash.Data.SelectedDevice.deviceName)
                    }Catch{
                        $syncHash.txtStatus.Foreground = 'Red'
                        $syncHash.txtStatus.Text = ("Failed to assign user [{0}] to device [{1}]. {2}" -f $syncHash.Data.SelectedUser.userPrincipalName,$syncHash.Data.SelectedDevice.deviceName, $_.exception.message)
                    }
                })
            }


        })



        # Sync Device Assignments
        #========================
        $syncHash.btnViewIntuneAssignments.Add_Click({
            # disable this button to prevent multiple export.
            $syncHash.btnViewIntuneAssignments.Dispatcher.Invoke("Normal",[action]{
                $this.IsEnabled = $false
                Update-UIProgress -Runspace $synchash -StatusMsg ("Please wait while loading device and user assignment data, this can take a while...") -Indeterminate

                $syncHash.AssignmentWindow = Show-UIAssignmentsWindow -ParentSynchash $syncHash `
                                                                        -DeviceData $syncHash.Data.SelectedDevice `
                                                                        -UserData $syncHash.Data.AssignedUser `
                                                                        -SupportScripts @("$FunctionPath\Runspace.ps1","$FunctionPath\UIControls.ps1","$FunctionPath\Helpers.ps1") `
                                                                        -IncludeInherited -LoadOnStartup

            })

        })

        #Currently Keep check and disabled
        $syncHash.chkNewDeviceNameIncrement.IsEnabled = $false
        $syncHash.chkNewDeviceNameIncrement.IsChecked = $true
        $syncHash.btnNewDeviceName.IsEnabled = $false

        # Sync AD Computer
        #========================
        $syncHash.btnADComputerSync.Add_Click({
            # disable this button to prevent multiple export.
            $this.IsEnabled = $false
            $syncHash.Window.Dispatcher.Invoke([action]{
                Import-Module ActiveDirectory
                #START to build computer parameter
                $GetComputersParam = @{identity=$syncHash.listIntuneDevices.SelectedItem}
                $CompSearchParmAsString = $GetComputersParam.GetEnumerator() |%{ "$($_.Name) = $($_.Value)" }
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Searching for AD computers within the parameters:`n{0}" -f $CompSearchParmAsString)
                # list all computers in AD
                $syncHash.Data.ADComputer = Get-ADComputer @GetComputersParam
                If($syncHash.Data.ADComputer){
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Found computer object in AD" )
                    $syncHash.txtADComputerDN.Text = $syncHash.Data.ADComputer.DistinguishedName
                }
                # disable this button to prevent multiple export.
                $this.IsEnabled = $true
            },'Normal')
        })

        # Sync AD User
        #========================
        $syncHash.btnADUserSync.Add_Click({
            #grab User from UPN

            #$AADUserObjectName = ($syncHash.txtAssignedUser.text -Split '@','')[0].Trim()
            [System.Net.Mail.MailAddress]$AadUserMailAddress = $syncHash.Data.AssignedUser.userPrincipalName
            $syncHash.Data.ADUser = Get-ADUser -Identity $AadUserMailAddress.User -ErrorAction SilentlyContinue

            If($null -eq $syncHash.Data.ADUser.DistinguishedName){
                $syncHash.txtADUserDN.text = "No AD User Found"
            }
            Else{
                $AdUserAsString = $syncHash.Data.ADUser | Select DistinguishedName,Name,SamAccountName,UserPrincipalName | Format-List | Out-String
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Found AD user:`n{0}" -f $AdUserAsString)
                $syncHash.txtADUserDN.text = $syncHash.Data.ADUser.DistinguishedName
            }
        })


        #
        #=======================
        # Stale Device List
        #========================
        $syncHash.cmbDeviceAge.Add_SelectionChanged({
            $syncHash.properties.DeviceAge =  $syncHash.cmbDeviceAge.SelectedItem
        })

        $syncHash.btnGetStaleDevices.Add_Click({
            $this.IsEnabled = $false
            Update-UIProgress -Runspace $synchash -StatusMsg ('Refreshing stale [{0}] device list...' -f $syncHash.properties.DevicePlatform) -Indeterminate -Color Blue

            #clear current list
            $syncHash.btnGetStaleDevices.Dispatcher.Invoke("Normal",[action]{
                $syncHash.txtSearchIntuneDevices.Foreground = 'Gray'
                $syncHash.txtSearchIntuneDevices.Text = 'Search...'
                $syncHash.listIntuneDevices.Items.Clear()
            })

            #grab all stale devices
            $syncHash.Data.StaleDevices = Get-IDMStaleAzureDevices -cutoffDays $syncHash.cmbDeviceAge.SelectedItem
            Add-UIList -Runspace $syncHash -ItemsList $syncHash.Data.StaleDevices -ListObject $syncHash.listStaleDevices -Identifier 'displayName'
            
            If($syncHash.Data.StaleDevices.count -gt 0)
            {
                Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} devices the meet platform requirement [{1}]' -f $syncHash.Data.StaleDevices.count,$syncHash.properties.DevicePlatform) -PercentComplete 100
            }
            Else{
                Update-UIProgress -Runspace $synchash -StatusMsg ('No devices found') -PercentComplete 100 -Color 'Red'
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("No devices found. Log into a different Azure tenant or credentials to retrieve registered devices") -Type Error
            }
            $this.IsEnabled = $true
        })

        # Generate new name
        #========================
        $syncHash.btnNewDeviceNameGen.Add_Click({
            #START to build computer parameter
            $GetComputersParam = @{filter='*'}
            #Get search DN for computers
            switch($syncHash.cmbSearchInOptions.SelectedItem){
                'User Root OU'  {
                    #get the root OU
                    $SearchOU = (([ADSI]"LDAP://$($syncHash.Data.ADUser.DistinguishedName)").parent).Substring(7).split(',',2)[1]
                    #$SearchOU = $syncHash.Data.ADUser.DistinguishedName.Substring($syncHash.Data.ADUser.DistinguishedName.IndexOf('OU='))
                    $GetComputersParam += @{SearchBase=$SearchOU;searchscope='subtree'}
                }
                'Computers Root OU'  {
                    $SearchOU = Get-WellKnownOU -KnownOU 'Computers Root'
                    $GetComputersParam += @{SearchBase=$SearchOU}
                }
                'Computers Default OU'  {
                    $SearchOU = Get-WellKnownOU -KnownOU 'Default Computers'
                    $GetComputersParam += @{SearchBase=$SearchOU;searchscope='subtree'}
                }
                'Custom'        {
                    If($syncHash.txtSearchFilter.Text -ne '*'){
                        $SearchOU = $syncHash.txtSearchFilter.Text
                        $GetComputersParam += @{SearchBase=$SearchOU}
                    }
                }
                default{
                    $GetComputersParam += @{searchscope='subtree'}
                }
            }
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Found {0} computer(s) in AD from search criteria" -f $Computers.count)

            # list all computers in AD
            $Computers = Get-ADComputer @GetComputersParam
            #TEST $Computers = @('BLY05A001','BLY05A002','BLY05A003','BLY05A005')
            $CompSearchParmAsString = $GetComputersParam.GetEnumerator() |%{ "$($_.Name) = $($_.Value)" }
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Searching for AD computers within the parameters:`n{0}" -f $CompSearchParmAsString)

            switch($syncHash.cmbQueryRule.SelectedItem){
                'User OU Name' {
                        #get the current user OU to be used as query
                        $syncHash.Data.QueryString = ((([ADSI]"LDAP://$($syncHash.Data.ADUser.DistinguishedName)").parent).Substring(7) -split ",",3)[0] -replace 'OU=',''
                }
                'User Name' {$syncHash.Data.QueryString = $syncHash.Data.ADUser.SamAccountName}
                'User Display Name' {$syncHash.Data.QueryString = ($syncHash.Data.ADUser.displayName) -replace ' ',''}
                'Device Name' {$syncHash.Data.QueryString = $syncHash.listIntuneDevices.SelectedItem}
                'Device SerialNumber' {
                    #$syncHash.Data.QueryString = Get-CIMInstance -Class Win32_Bios -ComputerName $syncHash.listIntuneDevices.SelectedItem | Select -ExpandProperty SerialNumber
                    $syncHash.Data.QueryString = $syncHash.Data.SelectedDevice.serialNumber
                }
                'Device AssetTag' {$syncHash.Data.QueryString = Get-CIMInstance -Class Win32_SystemEnclosure -ComputerName $syncHash.listIntuneDevices.SelectedItem | Select-Object -ExpandProperty SMBiosAssetTag}
                'Random' {$syncHash.Data.QueryString = Generate-RandomName}
            }
            #get what loaded in rules
            $syncHash.Data.Rules = @{}
            IF($syncHash.txtRuleRegex1.text){$syncHash.Data.Rules['RuleRegex1'] = $syncHash.txtRuleRegex1.text}
            IF($syncHash.txtRuleRegex2.text){$syncHash.Data.Rules['RuleRegex2'] = $syncHash.txtRuleRegex2.text}
            IF($syncHash.txtRuleRegex3.text){$syncHash.Data.Rules['RuleRegex3'] = $syncHash.txtRuleRegex3.text}
            IF($syncHash.txtRuleRegex4.text){$syncHash.Data.Rules['RuleRegex4'] = $syncHash.txtRuleRegex4.text}
            #BUILD NEW COMPUTER NAME using query string and Query Rules
            $ComputerSample = @{Query=$syncHash.Data.QueryString;RegexRules=$syncHash.Data.Rules}
            If($syncHash.txtRuleAbbrKey.Text.Length -gt 0){$ComputerSample += @{device=$syncHash.listIntuneDevices.SelectedItem;AbbrKey=$syncHash.txtRuleAbbrKey.text}}
            If($syncHash.txtRulePrefix.Text.Length -gt 0){$ComputerSample += @{Prefix=$syncHash.txtRulePrefix.Text}}
            #If($null -ne $syncHash.cmbRuleAddDigits.SelectedItem){$ComputerSample += @{AppendDigits=$syncHash.cmbRuleAddDigits.SelectedItem}}
            $d=0
            $UsedDigits = @()
            #get the used digits on inventoried computers
            If($syncHash.cmbRuleAddDigits.SelectedItem){
                $AppendDigits = $syncHash.cmbRuleAddDigits.SelectedItem
                $Computers.Name | %{ $UsedDigits += $_.substring($_.length-$AppendDigits) }
            }
            Else{
                #grabs all digits at end of string
                $Computers.Name | %{ $UsedDigits += [regex]::Matches($_, "\d+(?!.*\d+)").value }
            }
            $MaxDigit = ($UsedDigits | Measure-Object -Maximum -Property Length).Maximum
            $MaxLoop = ("{0:d$MaxDigit}" -f 9) -replace '0','9'
            #loop through all available digits to see what not used
            #stop once you grab one
            for($i=1;$i -le $MaxLoop;$i++)
            {
                If(("{0:d$MaxDigit}" -f $i) -notin $UsedDigits){
                    $NextIncrement = ("{0:d$MaxDigit}" -f $i)
                    break
                }
            }
            #populate new device name
            If($syncHash.chkNewDeviceNameIncrement.IsChecked){
                $syncHash.txtNewDeviceName.Text = ((Get-NewDeviceName @ComputerSample) + $NextIncrement)
            }
            Else{
                $syncHash.txtNewDeviceName.Text = (Get-NewDeviceName @ComputerSample)
            }
            $syncHash.btnNewDeviceName.IsEnabled = $true
        })

        # Rename Device
        #========================
        $syncHash.btnNewDeviceName.Add_Click({
            $syncHash.Window.Dispatcher.Invoke([action]{
                #attempt to rename object in Intune
                Try{
                    Invoke-IDMDeviceAction -DeviceID $syncHash.Data.SelectedDevice.id -Action Rename -NewDeviceName $syncHash.txtNewDeviceName.Text -ErrorAction Stop
                    $syncHash.txtNewDeviceNameStatus.Text = 'Successfully renamed device.'
                    $syncHash.txtNewDeviceNameStatus.Foreground = 'Green'
                    $MoveableObject = $true
                }
                Catch{
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Failed to rename device. Error: {0}" -f $_.Exception.Message) -Type Error
                    $syncHash.txtNewDeviceNameStatus.Text = 'Failed to rename device. Please see log for more details'
                    $syncHash.txtNewDeviceNameStatus.Foreground = 'Red'
                    $MoveableObject = $false
                }
                #attempt to move object in AD
                If($MoveableObject -and $syncHash.chkNewDeviceNameMoveOU.IsChecked -and ($null -ne $syncHash.Data.ADComputer) -and ($null -ne $syncHash.txtOUPath.Text)){
                    Try{
                        Move-ADObject -Identity $syncHash.Data.ADComputer.DistinguishedName -TargetPath $syncHash.txtOUPath.Text
                    }
                    Catch{
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging -Message ("Failed to move AD object [{2}] to [{1}]. Error: {0}" -f $_.Exception.Message,$syncHash.txtOUPath.Text,$syncHash.Data.ADComputer.Name) -Type Error
                        $syncHash.txtNewDeviceNameStatus.Text = 'Failed to move device. Please see log for more details'
                        $syncHash.txtNewDeviceNameStatus.Foreground = 'Red'
                    }
                }
            })
        })

        #Allow UI to be dragged around screen
        $syncHash.Window.Add_MouseLeftButtonDown( {
            $syncHash.Window.DragMove()
        })
        #action for exit button
        $syncHash.btnExit.Add_Click({
            Close-UIMainWindow
        })


        $syncHash.Window.Add_KeyDown({
            #allow window in back if ESC is hit
            if ( ($_.Key -match 'Esc') -and $syncHash.Window.Topmost ) {
                $syncHash.Window.Topmost = $false
            }
            #and set inf front if hit again
            ElseIf ( ($_.Key -match 'Esc') ) {
                $syncHash.Window.Topmost = $true
            }
        })

        # Before the UI is displayed
        # Create a timer dispatcher to watch for value change externally on regular interval
        # update those values when found using scriptblock ($updateblock)
        $syncHash.Window.Add_SourceInitialized({
            ## create a timer
            $timer = new-object System.Windows.Threading.DispatcherTimer
            ## set to fire 4 times every second
            $timer.Interval = [TimeSpan]"0:0:0.01"
            ## invoke the $updateBlock after each fire
            $timer.Add_Tick( $updateUI )
            ## start the timer
            $timer.Start()

            if( -Not($timer.IsEnabled) ) {
               $syncHash.Error = "Timer didn't start"
            }
        })

        #Add smooth closing for Window
        $syncHash.Window.Add_Loaded({ $syncHash.isLoaded = $True })
        $syncHash.Window.Add_Closing({ $syncHash.isClosing = $True; Close-UIMainWindow })
        $syncHash.Window.Add_Closed({ $syncHash.isClosed = $True })
        #make sure this display on top of every window
        $syncHash.Window.Topmost = $true
        $syncHash.window.ShowDialog()
        $syncHash.Error = $Error
    }) # end scriptblock
    #collect data from runspace
    $Data = $syncHash
    #invoke scriptblock in runspace
    $PowerShellCommand.Runspace = $IDMRunSpace
    $AsyncHandle = $PowerShellCommand.BeginInvoke()
    #wait until runspace is completed before ending
    If($Wait){
        do {
            Start-sleep -m 100 }
        while (!$AsyncHandle.IsCompleted)
        #end invoked process
        $null = $PowerShellCommand.EndInvoke($AsyncHandle)
    }

    #cleanup registered object
    Register-ObjectEvent -InputObject $syncHash.Runspace `
            -EventName 'AvailabilityChanged' `
            -Action {
                    if($Sender.RunspaceAvailability -eq "Available")
                    {
                        $Sender.Closeasync()
                        $Sender.Dispose()
                        # Speed up resource release by calling the garbage collector explicitly.
                        # Note that this will pause *all* threads briefly.
                        [GC]::Collect()
                    }
                } | Out-Null
    return $Data
}
#endregion
##*=============================================
##* MAIN
##*=============================================
Write-Host ""
Write-Host ("Launching Intune Device Manager UI [ver: {0}]..." -f $version ) -ForegroundColor Cyan
Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host "Keyboard shortcut: " -ForegroundColor Green -NoNewline
Write-Host "Hit " -ForegroundColor White -NoNewline
Write-Host "ESC" -ForegroundColor Yellow -NoNewline
Write-Host " to toggle UI to show in front of other windows" -ForegroundColor White
Write-Host ""

$Global:syncHash = Show-UIMainWindow -XamlFile $XAMLFilePath -StylePath $StylePath -FunctionPath $FunctionPath -Properties $ParamProps -Wait
#$Global:AuthToken = $syncHash.Data.AuthToken

If($Global:syncHash.Error){
    Write-Host ""
    Write-Host "MAIN UI ERRORS:" -ForegroundColor Red
    Write-Host "==================================================================" -ForegroundColor Red
    $Global:syncHash.Error
}
If($Global:syncHash.AssignmentWindow.Error){
    Write-Host ""
    Write-Host "ASSIGNMENT WINDOW UI ERRORS:" -ForegroundColor Red
    Write-Host "==================================================================" -ForegroundColor Red
    $Global:syncHash.AssignmentWindow.Error
}


Write-Host ""
Write-Host "Global variable available after UI closed:" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Get all properties of UI, run command:" -ForegroundColor DarkGray
Write-Host "`$Global:syncHash" -ForegroundColor Green
Write-Host ""
#Write-Host "Get current graph token, run command:" -ForegroundColor DarkGray
#Write-Host "`$Global:AuthToken" -ForegroundColor Green
#Write-Host ""
Write-Host "Useful UI outputs:" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "To review specified properties, run command:" -ForegroundColor DarkGray
Write-Host "`$Global:syncHash" -ForegroundColor Green -NoNewline
Write-Host ".Properties" -ForegroundColor White
Write-Host ""
Write-Host "To review the data output of UI, run command:" -ForegroundColor DarkGray
Write-Host "`$Global:syncHash" -ForegroundColor Green -NoNewline
Write-Host ".Data" -ForegroundColor White
Write-Host ""
Write-Host "To review all listed devices shown in UI, run command:" -ForegroundColor DarkGray
Write-Host "`$Global:syncHash" -ForegroundColor Green -NoNewline
Write-Host ".Data.IntuneDevice" -ForegroundColor White
Write-Host ""
Write-Host "To review details of last selected device, run command:" -ForegroundColor DarkGray
Write-Host "`$Global:syncHash" -ForegroundColor Green -NoNewline
Write-Host ".Data.SelectedDevice" -ForegroundColor White
Write-Host ""
Write-Host "To review selected device user details, run command:" -ForegroundColor DarkGray
Write-Host "`$Global:syncHash" -ForegroundColor Green -NoNewline
Write-Host ".Data.AssignedUser" -ForegroundColor White
Write-Host ""
Write-Host "To review the graph data output of UI, run command:" -ForegroundColor DarkGray
Write-Host "`$Global:syncHash" -ForegroundColor Green -NoNewline
Write-Host ".GraphData" -ForegroundColor White
Write-Host ""
If($Global:syncHash.AssignmentWindow.DeviceAssignments.count -gt 0){
    Write-Host "To review selected device assignments, run command:" -ForegroundColor DarkGray
    Write-Host "`$Global:syncHash" -ForegroundColor Green -NoNewline
    Write-Host ".AssignmentWindow.DeviceAssignments" -ForegroundColor White
    Write-Host ""
}
If($Global:syncHash.AssignmentWindow.UserAssignments.count -gt 0){
    Write-Host "To review selected device user assignments, run command:" -ForegroundColor DarkGray
    Write-Host "`$Global:syncHash" -ForegroundColor Green -NoNewline
    Write-Host ".AssignmentWindow.UserAssignments" -ForegroundColor White
    Write-Host ""
}
Write-Host "==================================================================" -ForegroundColor Cyan