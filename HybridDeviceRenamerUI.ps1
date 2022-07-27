<#
.SYNOPSIS
    Connects to Intune and AD to rename device

.DESCRIPTION


.NOTES
    Author		: Dick Tracy II <richard.tracy@microsoft.com>
	Source	    :
    Version		: 1.1.5
    #Requires -Version 3.0
#>

param(
    [ValidateSet('WorldWide','DoD','GCC','GCC High','China','Germany')]
    [string]$Cloud = "WorldWide",
    [hashtable]$Rules = @{RuleRegex1 = '^.{0,3}';RuleRegex2 ='.{0,3}[\s+]'},
    [ValidateSet('Windows','Android','MacOS','iOS')]
    [string]$FilterDeviceOS = 'Windows',
    [string]$SearchFilter = '*',
    [ValidateSet('displayName','userPrincipalName','mail','givenName','surname')]
    [string]$DisplayUserAs = 'displayName',
    [ValidateSet('No Abbr','Chassis','Manufacturer','Model')]
    [string]$AbbrType = 'Chassis',
    [string]$AbbrKey = 'Laptop=A, Notebook=A, Tablet=A, Desktop=W, Tower=W, Virtual Machine=W',
    [string]$Prefix,
    [ValidateSet(0,1,2,3,4,5)]
    [int]$AppendDigits = 3,
    [string]$CMSiteCode,
    [string]$CMSiteServer,
    [switch]$AdvancedMode,
    [switch]$AppConnect,
    [string]$ApplicationId ="21d133d2-75eb-4241-9247-febde41f4463",
    [string]$AppTenantId = "2ec9dcf0-b109-434a-8bcd-238a3bf0c6b2"
)
#*=============================================
##* Runtime Function - REQUIRED
##*=============================================

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

##*=============================================
##* VARIABLE DECLARATION
##*=============================================
[string]$Version = '1.1.7 (beta)'

If ($PSBoundParameters['Debug']){$DebugMode = $true}Else{$DebugMode = $false}
#check if offline was called
If($PSBoundParameters.ContainsKey('Offline')){$OfflineMode = $true}Else{$OfflineMode = $false}
#region VARIABLES: Building paths & values
# Use function to get paths because Powershell ISE & other editors have differnt results
[string]$scriptPath = Get-ScriptPath
[string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
[string]$scriptFileName = Split-Path -Path $scriptPath -Leaf
[string]$scriptRoot = Split-Path -Path $scriptPath -Parent
[string]$invokingScript = (Get-Variable -Name 'MyInvocation').Value.ScriptName

[string]$FunctionPath = Join-Path -Path $scriptRoot -ChildPath 'Functions'
[string]$ResourcePath = Join-Path -Path $scriptRoot -ChildPath 'Resources'
[string]$XAMLFilePath = Join-Path -Path $ResourcePath -ChildPath 'MainWindow.xaml'


##*=============================================
##* External Functions
##*=============================================
. "$FunctionPath\Logging.ps1"
. "$FunctionPath\Environment.ps1"
. "$FunctionPath\DeviceInfo.ps1"
#. "$FunctionPath\MSgraph.ps1"
#. "$FunctionPath\Intune.ps1"
. "$FunctionPath\UIControls.ps1"

#Return log path (either in task sequence or temp dir)
#build log name
[string]$FileName = $scriptName +'.log'
#build global log fullpath
$Global:LogFilePath = Join-Path $env:temp -ChildPath $FileName
Write-Host "logging to file: $LogFilePath" -ForegroundColor Cyan

# Make PowerShell Disappear
If(Test-IsISE){
    $Windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $asyncWindow = Add-Type -MemberDefinition $Windowcode -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
    $null = $asyncWindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)
}

#parse changelog for version for a more accurate version
$ChangeLogPath = Resolve-ActualPath -FileName 'CHANGELOG.md' -WorkingPath $scriptRoot -ErrorAction SilentlyContinue
If($ChangeLogPath){
    $ChangeLog = Get-Content $ChangeLogPath
    $Changedetails = (($ChangeLog -match '##')[0].TrimStart('##') -split '-').Trim()
    [string]$Version = [version]$Changedetails[0]
    [string]$MenuDate = $Changedetails[1]
}
#=======================================================
# LOAD ASSEMBLIES
#=======================================================
[System.Reflection.Assembly]::LoadWithPartialName('WindowsFormsIntegration') | out-null # Call the EnableModelessKeyboardInterop
If(Test-IsISE){[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Application') | out-null} #Encapsulates a Windows Presentation Foundation application.
[System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework') | out-null
[System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')      | out-null
[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')  | out-null


[string]$XAML = (get-content $XAMLFilePath -ReadCount 0) -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window' -replace 'Click=".*','/>'

#convert XAML to XML just to grab info using xml dot sourcing (Not used to process form)
[xml]$XML = $XAML

#grab the list of merged dictionaries in XML, replace the path with Powershell
$MergedDictionaries = $XML.Window.'Window.Resources'.ResourceDictionary.'ResourceDictionary.MergedDictionaries'.ResourceDictionary.Source
#$XML.SelectNodes("//*[@Source]")

#grab all style files
$Resources = Get-ChildItem "$ResourcePath\Styles" -Filter *.xaml

# replace the resource path
foreach ($Source in $MergedDictionaries)
{
    $FileName = Split-Path $Source -Leaf
    $ActualPath = $Resources | Where {$_.Name -match $FileName} | Select -ExpandProperty FullName
    $XAML = $XAML.replace($Source,$ActualPath) #  ($ActualPath -replace "\\","/")
}

#convert XAML to XML
[xml]$XAML = $XAML
$reader = New-Object System.Xml.XmlNodeReader ([xml]$XAML)
try{
   $UI=[Windows.Markup.XamlReader]::Load($reader)
}
catch{
    $ErrorMessage = $_.Exception.Message
    Write-Host "Unable to load Windows.Markup.XamlReader for $XAMLPath. Some possible causes for this problem include:
    - .NET Framework is missing
    - PowerShell must be launched with PowerShell -sta
    - invalid XAML code was encountered
    - The error message was [$ErrorMessage]" -ForegroundColor White -BackgroundColor Red
    Exit
}

# Store Form Objects In PowerShell
#===========================================================================
#take the xaml properties & make them variables
$xaml.SelectNodes("//*[@Name]") | %{Set-Variable -Name "ui_$($_.Name)" -Value $UI.FindName($_.Name)}
#Get-Variable ui_*
$Global:AllUIVariables = Get-Variable ui_*

If($PSBoundParameters.ContainsKey('AdvancedMode')){
    $ui_tabConfigure.Visibility = 'Visible'
    $ui_tabConfigure.IsEnabled = $true
}Else{
    $ui_tabConfigure.Visibility = "Collapsed"
    $ui_tabConfigure.IsEnabled = $false
}

$ui_tbADSearchHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("Select the AD search field to determine where computer objects are locate."
                "The filter can be used during OU Search")
    }
    Add-PopupContent -FlowDocumentObject $ui_PopupContent -ContextHash $PopupContexts
    $ui_HelpPopup.VerticalOffset="50"
    $ui_HelpPopup.Placement="Right"
    $ui_HelpPopup.IsOpen = $true
})
$ui_tbADSearchHelp.Add_MouseLeave({
    $ui_HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $ui_PopupContent
})

$ui_tbAssignedUserHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("This selection will user displayed in UI")
        Setting = @("The default selection is: $DisplayUserAs")
    }
    Add-PopupContent -FlowDocumentObject $ui_PopupContent -ContextHash $PopupContexts
    $ui_HelpPopup.VerticalOffset="200"
    $ui_HelpPopup.Placement="Right"
    $ui_HelpPopup.IsOpen = $true
})
$ui_tbAssignedUserHelp.Add_MouseLeave({
    $ui_HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $ui_PopupContent
})

$ui_tbCMSearchHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("Fill in CM site server and Site code to connect to ConfigMgr")
        Tip = @("Specify the attribute used to determine if device is a match")
    }
    Add-PopupContent -FlowDocumentObject $ui_PopupContent -ContextHash $PopupContexts
    $ui_HelpPopup.VerticalOffset="240"
    $ui_HelpPopup.Placement="Right"
    $ui_HelpPopup.IsOpen = $true
})
$ui_tbCMSearchHelp.Add_MouseLeave({
    $ui_HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $ui_PopupContent
})

$ui_tbMoveOUHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("Select an option on how to move the device to an OU.")
        Tip = @("Specify an OU in LDAP format")
    }
    Add-PopupContent -FlowDocumentObject $ui_PopupContent -ContextHash $PopupContexts
    $ui_HelpPopup.VerticalOffset="340"
    $ui_HelpPopup.Placement="Left"
    $ui_HelpPopup.IsOpen = $true
})
$ui_tbMoveOUHelp.Add_MouseLeave({
    $ui_HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $ui_PopupContent
})

$ui_tbRuleTesterHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("This is a test tool that allow you to test the configurations")
        Note = @("Rule tester ignores AD Search filter and Method options.","Digits are simulated")
    }
    Add-PopupContent -FlowDocumentObject $ui_PopupContent -ContextHash $PopupContexts
    $ui_HelpPopup.VerticalOffset="380"
    $ui_HelpPopup.Placement="Left"
    $ui_HelpPopup.IsOpen = $true
})
$ui_tbRuleTesterHelp.Add_MouseLeave({
    $ui_HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $ui_PopupContent
})

$ui_tbRuleGenHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("Select an attribute to query from to build base for device name"
                "Use regex rule to further evaluate the value from the method selected; each rule extracts a value then concatenates"
                "Select Abbreviations type to add a dynamic character(s) to name. This can be controlled by Abbr key rules."
                "Set Rules. Rules must be in Key=Value pair and each set must be separated by commas."
                "Select where to place the Abbreviation within the name."
                "Select how many digits will be added to the name. This is ignored if increment option is enabled"
                "Select where the digits should be added to the name ")
        Note = @( "Prefix will add characters to front of name","If no rules are set, first three characters of evaluated type will be used.")
    }
    Add-PopupContent -FlowDocumentObject $ui_PopupContent -ContextHash $PopupContexts
    $ui_HelpPopup.VerticalOffset="50"
    $ui_HelpPopup.Placement="Left"
    $ui_HelpPopup.IsOpen = $true
})
$ui_tbRuleGenHelp.Add_MouseLeave({
    $ui_HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $ui_PopupContent
})

$UI.Title = "Hybrid Azure AD Joined Device Renamer"
$ui_txtVersion.Content = ("ver " + $Version)

#attempt to auto populate site server info
If($CMSiteCode){
    $ui_txtCMSiteCode.text = $CMSiteCode
}Else{
    $ui_txtCMSiteCode.text = Get-CMSiteCode
}

#check modules
$ModulesNeeded = @('Microsoft.Graph.Intune','Microsoft.Graph.Authentication','Microsoft.Graph.DeviceManagement.Administration','AzureAD')
#TEST $Module = $ModulesNeeded[0]
Foreach($Module in $ModulesNeeded){
    $ModuleInstalled = Get-Module -Name $Module -ListAvailable
    $n = 0
    If($null -eq $ModuleInstalled){
        $n ++
        Write-UIOutput -UIObject $ui_Logging -Message ("Module required: {0}" -f $Module) -Type Error -Passthru
    }Else{
        Write-UIOutput -UIObject $ui_Logging -Message ("Module is installed: {0}" -f $Module) -Type Info -Passthru
    }

    If($n -ge 1){
        $ui_btnMSGraphConnect.IsEnabled = $false
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name IDMCmdlets -AllowClobber -Force -Confirm:$false
#Install-Module -Name AzureAD -Force
#Install-Module -Name Microsoft.Graph -Force
#Import-Module ActiveDirectory -Force
<# TEST RULES
$Rules = @{RuleRegex1 = '^.{0,3}';RuleRegex2 ='.{0,3}\s+'}
$Rules = @{RuleRegex1 = '(^.*?)\s';RuleRegex2 ='^.{0,3}';RuleRegex3 ='.{0,3}$'}
#>
If(Test-IsDomainJoined){
    $ui_txtDomainDevice.text = 'Yes'
    $ui_txtDomainDevice.Foreground = 'Green'
    Write-UIOutput -UIObject $ui_Logging -Message ("Device running this is joined to the domain: {0}" -f (Test-IsDomainJoined -Passthru)) -Type Info -Passthru
}Else{
    $ui_txtDomainDevice.text = 'No'
    $ui_btnUserSync.IsEnabled = $false

    Write-UIOutput -UIObject $ui_Logging -Message ("Device running this script must be joined to the domain to view AD objects") -Type Error -Passthru
}


# check if RSAT PowerShell Module is installed
If(Test-RSATModule){
    $ui_txtRSAT.text = 'Yes';$ui_txtRSAT.Foreground = 'Green'
    Write-UIOutput -UIObject $ui_Logging -Message ("RSAT PowerShell module is installed: {0}" -f (Test-RSATModule -Passthru)) -Type Info -Passthru
    $ui_btnUserSync.IsEnabled = $true
}
Else{
    Write-UIOutput -UIObject $ui_Logging -Message ("RSAT PowerShell module must be installed to be able to query AD device names") -Type Error -Passthru
    $ui_txtRSAT.text = 'No'
    $ui_btnUserSync.IsEnabled = $false
}


# check if RSAT PowerShell Module is installed
If($ui_txtCMSiteCode.text -and $ui_txtCMSiteServer.text)
{
    If(Test-CMModule -CMSite $ui_txtCMSiteCode.text -CMSite $ui_txtCMSiteServer.text){
        $ui_txtRSA.text = 'Yes';$ui_txtRSAT.Foreground = 'Green'
        Write-UIOutput -UIObject $ui_Logging -Message ("Configuration Manager PowerShell module is installed: {0}" -f (Test-CMModule -CMSite $ui_txtCMSiteCode.text -CMSite $ui_txtCMSiteServer.text -Passthru)) -Type Info -Passthru
        $ui_btnCMDeviceSync.IsEnabled = $true
    }Else{
        Write-UIOutput -UIObject $ui_Logging -Message ("Configuration Manager PowerShell module must be installed to be able to query CM device names") -Type Error -Passthru
        $ui_txtRSAT.text = 'No'
        $ui_btnCMDeviceSync.IsEnabled = $False
    }
}
Else{
    Write-UIOutput -UIObject $ui_Logging -Message ("Configuration Manager settings are not configured, configure them to use the CM feature") -Type Warning -Passthru
}


# Get PowerShell Version
[hashtable]$envPSVersionTable = $PSVersionTable
[version]$envPSVersion = $envPSVersionTable.PSVersion
$PSVersion = [float]([string]$envPSVersion.Major + '.' + [string]$envPSVersion.Minor)
$ui_txtPSVersion.Text = $PSVersion.ToString()
IF($envPSVersion.Major -ge 5 -and $envPSVersion.Minor -ge 1){
    $ui_txtPSVersion.Foreground = 'Green'
    Write-UIOutput -UIObject $ui_Logging -Message ("PowerShell version is: {0}" -f $PSVersion.ToString()) -Type Info -Passthru
}Else{
    Write-UIOutput -UIObject $ui_Logging -Message ("PowerShell must be must be at version 5.1 to work properly") -Type Error -Passthru
    $ui_btnMSGraphConnect.IsEnabled = $false
    $ui_btnRename.IsEnabled = $false
}

#default refresh button to disabled until MSgraph sign in
$ui_btnRefreshList.IsEnabled = $false
#$ui_chkUseExistingCM.IsChecked = $true
#$ui_chkUseExistingCM.IsEnabled = $false

# Populate config tab
#----------------------
@('User Root OU','Computers Root OU','Default Computers OU','Custom') | %{$ui_cmbSearchInOptions.Items.Add($_) | Out-Null}
$ui_cmbSearchInOptions.SelectedItem = 'User Root OU'
$ui_txtSearchFilter.text = $SearchFilter

@('User OU Name','User Name','User Display Name','Device Name','Serial Number','AssetTag','Random') | %{$ui_cmbQueryRule.Items.Add($_) | Out-Null}
$ui_cmbQueryRule.SelectedItem = 'User OU Name'

@('displayName','userPrincipalName','mail','givenName','surname') | %{$ui_cmbUserDisplayOptions.Items.Add($_) | Out-Null}
$ui_cmbUserDisplayOptions.SelectedItem = $DisplayUserAs

@('SerialNumber','MacAddress','LastLoggedOnUser','AssetTag') | %{$ui_cmbCMAttribute.Items.Add($_) | Out-Null}
$ui_cmbCMAttribute.SelectedItem = 'SerialNumber'

If(-Not(Test-RSATModule) -or -Not(Test-IsDomainJoined)){
    $ui_chkMoveOU.Visibility = 'Hidden'
    $ui_cmbOUOptions.IsEnabled = $false
    $ui_txtOUPath.IsEnabled = $false

}Else{
    @('Computers Root','Default Computers','Corresponding User OU','Custom') | %{$ui_cmbOUOptions.Items.Add($_) | Out-Null}
    $ui_cmbOUOptions.SelectedItem = 'Computers Root'
    $MoveToOU = Get-WellKnownOU -KnownOU $ui_cmbOUOptions.SelectedItem
    $ui_txtOUPath.text = $MoveToOU
}

#load default rules
If($null -ne $Rules){
    (Get-UIVariable "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$true -ErrorAction SilentlyContinue
    $ui_chkDoRegex.IsChecked = $true
    $ui_txtRuleRegex1.text = $Rules['RuleRegex1']
    $ui_txtRuleRegex2.text = $Rules['RuleRegex2']
    $ui_txtRuleRegex3.text = $Rules['RuleRegex3']
    $ui_txtRuleRegex4.text = $Rules['RuleRegex4']
}Else{
    $ui_chkDoRegex.IsChecked = $false
    (Get-UIVariable "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
}

$ui_txtRulePrefix.text = $Prefix
$ui_txtRuleAbbrKey.text = $AbbrKey

$AbbrTypeList = Get-ParameterOption -Command Get-NewDeviceName -Parameter AbbrType
$AbbrTypeList | %{$ui_cmbRuleAbbrType.Items.Add($_) | Out-Null}
$ui_cmbRuleAbbrType.SelectedItem = $AbbrType

$AbbrPosList = Get-ParameterOption -Command Get-NewDeviceName -Parameter AbbrPos
$AbbrPosList | %{$ui_cmbRuleAbbrPosition.Items.Add($_) | Out-Null}
$ui_cmbRuleAbbrPosition.SelectedItem = 'After Prefix'

#$AddDigits = Get-ParameterOption -Command ${CmdletName} -Parameter AppendDigits
@('0','1','2','3','4','5') | %{$ui_cmbRuleAddDigits.Items.Add($_) | Out-Null}
$ui_cmbRuleAddDigits.SelectedItem = $AppendDigits.ToString()

$DigitPosList = Get-ParameterOption -Command Get-NewDeviceName -Parameter DigitPos
$DigitPosList | %{$ui_cmbRuleDigitPosition.Items.Add($_) | Out-Null}
$ui_cmbRuleDigitPosition.SelectedItem = 'At End'


#========================
# EVENT HANDLERS
#========================
#back button actions
(Get-UIVariable -Name "Back" -Wildcard) | %{
    $_.Add_Click({
       Switch-UITabItem -TabControlObject $ui_menuNavigation -Name 'Renamer'
    })
}


#PROCESS ON PAGE LOAD
#region For Task Sequence Tab event handlers
# -------------------------------------------
#Grab the text value when cursor leaves (AFTER Typed)
$ui_txtSearchIntuneDevices.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::GotFocusEvent,
    [System.Windows.RoutedEventHandler]{
        #set a variable if there is text in field BEFORE the new name is typed
        If($ui_txtSearchIntuneDevices.Text){
            $script:SearchText = $ui_txtSearchIntuneDevices.Text
        }
    }
)

$ui_txtSearchIntuneDevices.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::LostFocusEvent,
    [System.Windows.RoutedEventHandler]{
        #because there is a example text field in the box by default, check for that
        If($ui_txtSearchIntuneDevices.Text -eq 'Search...'){
            $script:SearchText = $ui_txtSearchIntuneDevices.Text
        }
        ElseIf([string]::IsNullOrEmpty($ui_txtSearchIntuneDevices.Text)){
            #add example back in light gray font
            $ui_txtSearchIntuneDevices.Foreground = 'Gray'
            $ui_txtSearchIntuneDevices.Text = 'Search...'
        }
        Else{

        }
    }
)

#Textbox placeholder remove default text when textbox is being used
$ui_txtSearchIntuneDevices.Add_GotFocus({
    #if it has an example
    if ($ui_txtSearchIntuneDevices.Text -eq 'Search...') {
        #clear value and make it black bold ready for input
        $ui_txtSearchIntuneDevices.Text = ''
        $ui_txtSearchIntuneDevices.Foreground = 'Black'
        #should be black while typing....
    }
    #if it does not have an example
    Else{
        #ensure test is black and medium
        $ui_txtSearchIntuneDevices.Foreground = 'Black'
    }
})

#Textbox placeholder grayed out text when textbox empty and not in being used
$ui_txtSearchIntuneDevices.Add_LostFocus({
    #if text is null (after it has been clicked on which cleared by the Gotfocus event)
    if ($ui_txtSearchIntuneDevices.Text -eq '') {
        #add example back in light gray font
        $ui_txtSearchIntuneDevices.Foreground = 'Gray'
        $ui_txtSearchIntuneDevices.Text = 'Search...'
    }
})

$ui_chkDoRegex.add_Checked({
    (Get-UIVariable "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$true -ErrorAction SilentlyContinue
})
$ui_chkDoRegex.add_Unchecked({
    (Get-UIVariable "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
    #(Get-UIVariable "txtRuleRegex" -Wildcard) | Set-UIElement -text $null -ErrorAction SilentlyContinue
})


$ui_cmbOUOptions.Add_SelectionChanged({
    If(Test-RSATModule -and Test-IsDomainJoined){
        switch($ui_cmbOUOptions.SelectedItem){
            'Default Computers' {
                    $MoveToOU = Get-WellKnownOU -KnownOU $ui_cmbOUOptions.SelectedItem
                    $ui_txtOUPath.IsReadOnly = $true
            }
            'Computers Root' {
                    $MoveToOU = Get-WellKnownOU -KnownOU $ui_cmbOUOptions.SelectedItem
                    $ui_txtOUPath.IsReadOnly = $true
            }
            'Corresponding User OU' {$MoveToOU = (($ADUser.distinguishedname -split ",",2)[1]).replace('UserAccounts','Laptops')}
            'Custom' {$ui_txtOUPath.IsReadOnly = $false}
        }
    }
    #Set the value of text object
    $ui_txtOUPath.Text = $MoveToOU
})

$ui_cmbQueryRule.Add_SelectionChanged({
    If($ui_cmbQueryRule.SelectedItem -eq 'Random'){
        $ui_txtSample.Text = Generate-RandomName
    }
})

$ui_cmbRuleAbbrType.Add_SelectionChanged({
    Switch($ui_cmbRuleAbbrType.SelectedItem){
        'No Abbr' {
            $ui_cmbRuleAbbrPosition.SelectedItem = $null
            $ui_cmbRuleAbbrPosition.IsEnabled = $false
            $ui_txtRuleAbbrKey.IsEnabled = $false
            $ui_txtRuleAbbrKey.Text = $null
            $ui_lblAbbrExample.Content = $null
        }
        'Chassis' {
            $SampleValue = 'Laptop=L, Notebook=N, Tablet=T, Desktop=D, Tower=D'
            $ui_cmbRuleAbbrPosition.IsEnabled = $true
            $ui_txtRuleAbbrKey.IsEnabled = $true
            $ui_lblAbbrExample.Content = "eg. $SampleValue"
            $ui_cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
        }
        'Manufacturer' {
            $SampleValue = 'Dell Inc.=D, Microsoft Corporation=M, HP=H, Lenovo=L, VMware=V'
            $ui_cmbRuleAbbrPosition.IsEnabled = $true
            $ui_txtRuleAbbrKey.IsEnabled = $true
            $ui_lblAbbrExample.Content = "eg. $SampleValue"
            $ui_cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
        }
        'Model' {
            $SampleValue = 'E6500=D, SurfaceBook 2=M, HP Prodesk 640 G1=H, Virtual Machine=V'
            $ui_cmbRuleAbbrPosition.IsEnabled = $true
            $ui_txtRuleAbbrKey.IsEnabled = $true
            $ui_lblAbbrExample.Content = "eg. $SampleValue"
            $ui_cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
        }
    }

    #default to parameter setting
    If($ui_cmbRuleAbbrType.SelectedItem -eq $AbbrType){
        $ui_txtRuleAbbrKey.Text = $AbbrKey
    }Else{
        $ui_txtRuleAbbrKey.Text = $SampleValue
    }
})

#Update when Device is selected
$ui_listIntuneDevices.Add_SelectionChanged({
    $ui_txtSelectedDevice.text = $ui_listIntuneDevices.SelectedItem
    If($ui_listIntuneDevices.SelectedItem.length -gt 0){
        $Global:DeviceInfo = $Global:ManagedDevices | Where {$_.deviceName -eq $ui_listIntuneDevices.SelectedItem}
        $AssignedUserId = Get-IDMDeviceAssignedUser -DeviceID $Global:DeviceInfo.id -AuthToken $Global:AuthToken
        $DeviceStatus = Get-IDMDevicePendingActions -DeviceID $Global:DeviceInfo.id -AuthToken $Global:AuthToken
        $AADUser = Get-IDMDeviceAADUser -Id $AssignedUserId -AuthToken $Global:AuthToken
        #check if system running device is joined to the domain and has RSAT tools installed
        If(Test-RSATModule -and Test-IsDomainJoined)
        {
            If($Global:DeviceInfo.joinType -eq 'hybridAzureADJoined')
            {
                Try{
                    $Global:ADComputer = Get-ADComputer -Identity $ui_listIntuneDevices.SelectedItem -ErrorAction Stop
                    $ui_txtRenameStatus.Text = ''
                }
                Catch{
                    Write-UIOutput -UIObject $ui_Logging -Message ("Failed to get AD object [{1}]. Error: {0}" -f $_.Exception.Message,$ui_listIntuneDevices.SelectedItem) -Type Error -Passthru
                    $ui_txtRenameStatus.Text = 'Failed to retrieve AD object. Please see log for more details'
                    $ui_txtRenameStatus.Foreground = 'Red'
                }
            }
            Else {
                Write-UIOutput -UIObject $ui_Logging -Message ("Device [{0}] is not AD joined" -f $ui_listIntuneDevices.SelectedItem) -Type Warning -Passthru
                $ui_txtRenameStatus.Text = 'Selected device is not AD joined'
                $ui_txtRenameStatus.Foreground = 'Orange'
            }
        }

        #$ui_txtAssignedUser.text = $AADUser.userPrincipalName
        #Display User by option selected
        $ui_txtAssignedUser.text = $AADUser.$($ui_cmbUserDisplayOptions.SelectedItem)

        If($null -ne $DeviceStatus){
            switch($DeviceStatus.actionName){
                'setDeviceName' {$statusMsg = ('Device is pending rename to: {0}' -f $DeviceStatus.passcode);$FontColor = 'Red'}
                default {$statusMsg = 'No pending actions';$FontColor = 'Black'}
            }
            $ui_txtDeviceStatus.Visibility='Visible'
            $ui_txtDeviceStatus.Text = $statusMsg
            $ui_txtDeviceStatus.Foreground = $FontColor
        }Else{
            $ui_txtDeviceStatus.Visibility='Hidden'
        }
    }
    Else{
        $ui_txtAssignedUser.text = ''
    }
})

#========================
# BUTTON CONTROLS
#========================
#get sample text and convert it using the regex rules
$ui_btnTestSample.Add_Click({
    $TestSample = @{Query=$ui_txtSample.Text}

    $TestRules=@{}
    if($ui_txtRuleRegex1.text){$TestRules.Add('RuleRegex1',$ui_txtRuleRegex1.text)}
    if($ui_txtRuleRegex2.text){$TestRules.Add('RuleRegex2',$ui_txtRuleRegex2.text)}
    if($ui_txtRuleRegex3.text){$TestRules.Add('RuleRegex3',$ui_txtRuleRegex3.text)}
    if($ui_txtRuleRegex4.text){$TestRules.Add('RuleRegex4',$ui_txtRuleRegex4.text)}

    If($TestRules.count -gt 0){                     $TestSample += @{RegexRules=$TestRules}}
    If($ui_cmbRuleAbbrType.Text -ne 'No Abbr'){     $TestSample += @{AbbrType=$ui_cmbRuleAbbrType.text}
        If($ui_txtRuleAbbrKey.Text.Length -gt 0){   $TestSample += @{device='localhost';AbbrKey=$ui_txtRuleAbbrKey.text}}
    }
    If($ui_cmbRuleAbbrPosition.SelectedItem){       $TestSample += @{AbbrPos=$ui_cmbRuleAbbrPosition.SelectedItem}}
    If($ui_txtRulePrefix.Text.Length -gt 0){        $TestSample += @{Prefix=$ui_txtRulePrefix.Text}}
    If($ui_cmbRuleAddDigits.SelectedItem){          $TestSample += @{AddDigits=$ui_cmbRuleAddDigits.SelectedItem}}
    If($ui_cmbRuleDigitPosition.SelectedItem){      $TestSample += @{DigitPos=$ui_cmbRuleDigitPosition.SelectedItem}}

    $ui_txtResults.Text = (Get-NewDeviceName @TestSample)
})


If($AppConnect){
    #Open-AppSecretPrompt
    $ui_btnMSGraphConnect.IsEnabled = $false
    $ui_AppSecretPopup.IsOpen = $true
    $ui_btnAppSecretCancel.Add_Click({
        $ui_AppSecretPopup.IsOpen = $false
        $AppConnect = $false
        $ui_btnMSGraphConnect.IsEnabled = $true
    })

    $ui_btnPasteClipboard.Add_Click({
        $ui_pwdAppSecret.Password = Get-Clipboard
    })

    $ui_btnAppSecretSubmit.Add_Click({
        If([string]::IsNullOrEmpty($ui_pwdAppSecret.Password) ){
            $ui_lblAppSecretMsg.content = "Invalid Secret, please try again or cancel"
        }Else{
            $ui_AppSecretPopup.IsOpen = $false
            $ui_btnMSGraphConnect.IsEnabled = $true
        }
    })
}

#action for button
$ui_btnMSGraphConnect.Add_Click({
    #minimize the UI to allow for login

    If($AppConnect){
        If([string]::IsNullOrEmpty($AppSecret) ){
            Write-UIOutput -UIObject $ui_Logging -Message "Unable to retrieve app secret." -Type Start -Passthru
        }
        $Global:AuthToken = Connect-IDMGraphApp -AppId $ApplicationId -TenantId $AppTenantId -AppSecret $ui_pwdAppSecret.Password
        #build object to simulate connection checks
        $IntuneConnection = "" | Select UPN,TenantId
        $IntuneConnection.UPN = $ApplicationId
        $IntuneConnection.TenantId = $AppTenantId
        Write-UIOutput -UIObject $ui_Logging -Message ("Connected to MSGraph using appid: {0}" -f $ApplicationId) -Type Start -Passthru
    }
    Else{
        $UI.WindowState = 'Minimized'
        $IntuneConnection = Connect-MSGraph -AdminConsent
        Write-UIOutput -UIObject $ui_Logging -Message ("Connected to MSGraph using account: {0}" -f $IntuneConnection.UPN) -Type Start -Passthru
        $TenantID = $IntuneConnection.TenantId
        $Global:AuthToken = Get-IDMGraphAuthToken -User $IntuneConnection.UPN
        #Put window back to its normal size if minimized
        If($null -ne $Global:AuthToken){
            $UI.WindowState = 'Normal'; $UI.Topmost = $true
        }
    }

    If($null -ne $IntuneConnection){
        Write-UIOutput -UIObject $ui_Logging -Message ("Successfully connected to Azure AD with Auth Token: {0}" -f ($Global:AuthToken.Authorization).replace('Bearer','').Trim()) -Type Start -Passthru

        $ui_txtMSGraphConnected.Text = 'Yes'
        $ui_txtMSGraphConnected.Foreground = 'Green'
        $ui_btnRefreshList.IsEnabled = $true
    }

    $ui_txtAADUPN.text = $IntuneConnection.UPN
    $ui_txtAuthToken.text = $Global:AuthToken.ExpiresOn

    If($null -ne $Global:AuthToken){
        #grab all managed devices
        If($FilterDeviceOS){
            $DeviceParams = @{AuthToken=$Global:AuthToken;Platform=$FilterDeviceOS}
        }Else{
            $DeviceParams = @{AuthToken=$Global:AuthToken}
        }
        $Global:ManagedDevices = @(Get-IDMDevice @DeviceParams)  # | Select deviceName,model,complianceState,deviceEnrollmentType,operatingSystem
        If($Global:ManagedDevices.count -gt 0)
        {
            $ui_btnRefreshList.IsEnabled = $true
            $ui_btnRename.IsEnabled =$true
            $ui_txtRenameStatus.Text = ''
            Add-UIList -ItemsList $Global:ManagedDevices -ListObject $ui_listIntuneDevices -Identifier 'deviceName'

            #ACTIVATE LIVE SEARCH
            $ui_txtSearchIntuneDevices.AddHandler(
                [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
                [System.Windows.RoutedEventHandler]{
                    If(-not([string]::IsNullOrEmpty($ui_txtSearchIntuneDevices.Text)) -and ($ui_txtSearchIntuneDevices.Text -ne 'Search...')){
                        Search-UIDeviceList -ItemsList $Global:ManagedDevices -ListObject $ui_listIntuneDevices -Identifier 'deviceName' -filter $ui_txtSearchIntuneDevices.Text
                    }
                }
            )
        }
        Else{
            $ui_btnRefreshList.IsEnabled = $false
            $ui_btnRename.IsEnabled = $false
            $ui_txtRenameStatus.Text = 'No devices found'
            $ui_txtRenameStatus.Foreground = 'Red'
            Write-UIOutput -UIObject $ui_Logging -Message ("No devices found. Log into a different Azure tenant or credentials to retrieve registered devices") -Type Error -Passthru
        }
    }
})

#=========================
# Refresh Device List
#========================
$ui_btnRefreshList.Add_Click(
{
    If($Global:ManagedDevices.count -gt 0){
        #clear current list
        $ui_listIntuneDevices.Items.Clear()

        If($null -ne $Global:AuthToken){

            #use search. Not live
            If($ui_txtSearchIntuneDevices.Text -ne 'Search...'){
                Search-UIDeviceList -ItemsList $Global:ManagedDevices -ListObject $ui_listIntuneDevices -Identifier 'deviceName' -filter $ui_txtSearchIntuneDevices.Text
            }Else{
                Add-UIList -ItemsList $Global:ManagedDevices -ListObject $ui_listIntuneDevices -Identifier 'deviceName'
            }
        }
    }
})

# SYNC users from Azure AD with AD to find rename method
$ui_btnUserSync.Add_Click({
    #grab User from UPN
    #$AADUserObjectName = ($ui_txtAssignedUser.text -Split '@','')[0].Trim()
    $AADUserName = (New-Object "System.Net.Mail.MailAddress" -ArgumentList $AADUser).userPrincipalName
    $Global:ADUser = Get-ADUser -Identity $AADUserName -ErrorAction SilentlyContinue
    #$Global:ADUser = Get-ADUser -Filter "Name -eq '$($ui_txtAssignedUser.text)'" -ErrorAction SilentlyContinue

    If($null -eq $ADUser){
        $ui_txtUserDN.text = "No AD User Found"
    }Else{
        $ui_txtUserDN.text = $ADUser.DistinguishedName
    }
    #build computer parameter
    $GetComputersParam = @{filter='*'}

    #Get search DN for computers
    switch($ui_cmbSearchInOptions.SelectedItem){
        'User Root OU'  {
            #get the root OU
            $SearchOU = ($ADUser.DistinguishedName -split ",",3)[2]
            $GetComputersParam += @{SearchBase=$SearchOU;searchscope='subtree'}
        }
        'Computers Root OU'  {
            $SearchOU = Get-WellKnownOU -KnownOU 'Computers Root'
            $GetComputersParam += @{SearchBase=$SearchOU}
        }
        'Default Computers OU'  {
            $SearchOU = Get-WellKnownOU -KnownOU 'Default Computers'
            $GetComputersParam += @{SearchBase=$SearchOU;searchscope='subtree'}
        }
        'Custom'        {
            If($ui_txtSearchFilter.Text -ne '*'){
                $SearchOU = $ui_txtSearchFilter.Text
                $GetComputersParam += @{SearchBase=$SearchOU}
            }

        }
        default{
            $GetComputersParam += @{searchscope='subtree'}
        }
    }

    # list all computers in AD
    $Computers = Get-ADComputer @GetComputersParam
    #$Computers = @('BLY05A001','BLY05A002','BLY05A003','BLY05A005')

    switch($ui_cmbQueryRule.SelectedItem){
        'User OU' {
                #get the current user OU to be used as query
                $QueryString = ($ADUser.distinguishedname -split ",",3)[1] -replace 'OU=',''
            }
        'User Name' {$QueryString = $ADUser.userPrincipalName}
        'User Display Name' {$QueryString = ($ADUser.displayName) -replace ' ',''}
        'Device Name' {$QueryString = $ui_listIntuneDevices.SelectedItem}
        'Serial Number' {$QueryString = Get-CIMInstance -Class Win32_Bios -ComputerName $ui_listIntuneDevices.SelectedItem | Select -ExpandProperty SerialNumber}
        'AssetTag' {$QueryString = Get-CIMInstance -Class Win32_SystemEnclosure -ComputerName $ui_listIntuneDevices.SelectedItem | Select-Object -ExpandProperty SMBiosAssetTag}
        'Random' {$QueryString = Generate-RandomName}
    }
    #get what loaded in rules
    IF($ui_txtRuleRegex1.text){$Rules['RuleRegex1'] = $ui_txtRuleRegex1.text}Else{$Rules.Remove('RuleRegex1')}
    IF($ui_txtRuleRegex2.text){$Rules['RuleRegex2'] = $ui_txtRuleRegex2.text}Else{$Rules.Remove('RuleRegex2')}
    IF($ui_txtRuleRegex3.text){$Rules['RuleRegex3'] = $ui_txtRuleRegex3.text}Else{$Rules.Remove('RuleRegex3')}
    IF($ui_txtRuleRegex4.text){$Rules['RuleRegex4'] = $ui_txtRuleRegex4.text}Else{$Rules.Remove('RuleRegex4')}

    #BUILD NEW COMPUTER NAME using query string and Query Rules
    $ComputerSample = @{Query=$QueryString;RegexRules=$Rules}
    If($ui_txtRuleAbbrKey.Text.Length -gt 0){$ComputerSample += @{device=$ui_listIntuneDevices.SelectedItem;AbbrKey=$ui_txtRuleAbbrKey.text}}
    If($ui_txtRulePrefix.Text.Length -gt 0){$ComputerSample += @{Prefix=$ui_txtRulePrefix.Text}}
    #If($null -ne $ui_cmbRuleAddDigits.SelectedItem){$ComputerSample += @{AppendDigits=$ui_cmbRuleAddDigits.SelectedItem}}

    #$ui_txtNewDeviceName.Text = (Get-NewDeviceName @ComputerSample)

    $d=0
    $UsedDigits = @()

    #get the used digits on inventoried computers
    If($ui_cmbRuleAddDigits.SelectedItem){
        $Computers.Name | %{ $UsedDigits += $_.substring($_.length-$AppendDigits) }
    }Else{
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
            $UseDigit = ("{0:d$MaxDigit}" -f $i)
            break
        }

    }

    #populate new device name
    $ui_txtNewDeviceName.Text = ((Get-NewDeviceName @ComputerSample) + $UseDigit)
})


$ui_btnCMDeviceSync.Add_Click({
    #attempt to reconnect to CMM (this is only if initial connection is not made and server and code has been changed)
    If($ui_txtCMSiteCode.text -and $ui_txtCMSiteServer.text -and ($ui_txtRSAT.text -eq 'No') )
    {
        If(Test-CMModule -CMSite $ui_txtCMSiteCode.text -CMSite $ui_txtCMSiteServer.text){
            $ui_txtRSA.text = 'Yes';$ui_txtRSAT.Foreground = 'Green'
            Write-UIOutput -UIObject $ui_Logging -Message ("Configuration Manager PowerShell module is installed: {0}" -f (Test-CMModule -CMSite $ui_txtCMSiteCode.text -CMSite $ui_txtCMSiteServer.text -Passthru)) -Type Info -Passthru
            $ui_btnCMDeviceSync.IsEnabled = $true
        }Else{
            Write-UIOutput -UIObject $ui_Logging -Message ("Configuration Manager PowerShell module must be installed to be able to query CM device names") -Type Error -Passthru
            $ui_txtRSAT.text = 'No'
            $ui_btnCMDeviceSync.IsEnabled = $False
        }
    }
    Else{
        Write-UIOutput -UIObject $ui_Logging -Message ("Configuration Manager settings are not configured, configure them to use the CM feature") -Type Warning -Passthru
    }

    #grab all CM devices
    $AllCMDevices = Get-CMDevice
    #determine how to filter CM devices
    switch($ui_cmbCMAttribute.SelectedItem){
        'SerialNumber' {$Query = "select SMS_R_System.Name, SMS_G_System_SYSTEM_ENCLOSURE.SerialNumber from  SMS_R_System inner join SMS_G_System_SYSTEM_ENCLOSURE on SMS_G_System_SYSTEM_ENCLOSURE.ResourceID = SMS_R_System.ResourceId"}
        'MacAddress'   {}
        'LastLoggedOnUser' {}
        'AssetTag'  {}
    }

    $CMdeviceMatch = Get-WmiObject -Query $Query -ComputerName $ui_txtCMSiteServer.text -Namespace "root/SMS/$($ui_txtCMSiteCode.text)"
    #display CM device based on matched filter
    $ui_txtCMDevice.text = $CMdeviceMatch

    #display device OU from AD (if exists)
    $ui_txtADDeviceOU.text = Get-ADDevice -Name $ui_txtCMDevice.text

})

$ui_btnRename.Add_Click({
    #attempt to rename object in Intune
    Try{
        Invoke-IDMDeviceAction -AuthToken $Global:AuthToken -DeviceID $Global:DeviceInfo.id -Action Rename -NewDeviceName $ui_txtNewDeviceName.Text -ErrorAction Stop
        $ui_txtRenameStatus.Text = 'Successfully renamed device.'
        $ui_txtRenameStatus.Foreground = 'Green'
        $MoveableObject = $true
    }Catch{
        Write-UIOutput -UIObject $ui_Logging -Message ("Failed to rename device. Error: {0}" -f $_.Exception.Message) -Type Error -Passthru
        $ui_txtRenameStatus.Text = 'Failed to rename device. Please see log for more details'
        $ui_txtRenameStatus.Foreground = 'Red'
        $MoveableObject = $false
    }

    #attempt to move object in AD
    If($MoveableObject -and $ui_chkMoveOU.IsChecked -and ($null -ne $Global:ADComputer) -and ($null -ne $ui_txtOUPath.Text)){
        Try{
            Move-ADObject -Identity $Global:ADComputer.DistinguishedName -TargetPath $ui_txtOUPath.Text
        }Catch{
            Write-UIOutput -UIObject $ui_Logging -Message ("Failed to move AD object [{2}] to [{1}]. Error: {0}" -f $_.Exception.Message,$ui_txtOUPath.Text,$Global:ADComputer.Name) -Type Error -Passthru
            $ui_txtRenameStatus.Text = 'Failed to move device. Please see log for more details'
            $ui_txtRenameStatus.Foreground = 'Red'
        }
    }Else{

    }

})
Show-UIMenu -FormObject $UI
