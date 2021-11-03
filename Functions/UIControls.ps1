#region FUNCTION: Builds dynamic variables in form with alias
Function Get-UIVariable{
    param(
        [Parameter(Mandatory = $true, Position=0)]
        [string]$Name,
        [string]$Prefix  = 'ui',
        [switch]$Wildcard

    )

    If($Wildcard){
        Return [array]($Global:AllUIVariables | Where Name -like ($Prefix + "_*" + $Name + '*')).Value
    }
    Else{
        Return [array]($Global:AllUIVariables | Where Name -eq ($Prefix + "_" + $Name)).Value
    }
}
#endregion



Function Search-UIDeviceList{
    Param(
        [Parameter(Mandatory = $true)]
        $ItemsList,
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.ListBox]$ListObject,
        [Parameter(Mandatory = $true)]
        [string]$Identifier,
        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    $ListObject.Items.Clear();

    foreach ($item in ($ItemsList | Where-Object { $_.$Identifier -like "*$Filter*" })){
        #only include what items exist in either in the folders collected initially or root locations
        #$ListObject.Tag = @($item.Name,$item.Path,$item.Guid)
        $ListObject.Items.Add($item.$Identifier) | Out-Null
    }
}
#endregion



#region FUNCTION: Action for Next & back button to change tab
function Switch-UITabItem {
    param(
        [Parameter(Mandatory = $true, Position=0)]
        [System.Windows.Controls.TabControl]$TabControlObject,
        [Parameter(Mandatory = $true, Position=1,ParameterSetName="index")]
        [int]$increment,
        [Parameter(Mandatory = $true, Position=1,ParameterSetName="name")]
        [string]$name
    )
    ## Get the name of this function
    [string]${CmdletName} = $MyInvocation.MyCommand

    If ($PSCmdlet.ParameterSetName -eq "index") {
        #Add index number to current tab
        $newtab = $TabControlObject.SelectedIndex + $increment
        #ensure number is not greater than tabs
        If ($newtab -ge $TabControlObject.items.count) {
            $newtab=0
        }
        elseif ($newtab -lt 0) {
            $newtab = $TabControlObject.SelectedIndex - 1
        }
        #Set new tab index
        $TabControlObject.SelectedIndex = $newtab

        $message = ("index [{0}]" -f $newtab)
    }
    ElseIf($PSCmdlet.ParameterSetName -eq "name"){
        $newtab = $TabControlObject.items | Where Header -eq $name
        $newtab.IsSelected = $true

        $message = ("name [{0}]" -f $newtab.Header)

    }
}
#endregion

Function Get-UIFieldElement {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0,ParameterSetName="name",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [object[]]$Name
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $MyInvocation.MyCommand

        $objects = @()
    }
    Process{
        Foreach($item in $Name){
            If($null -ne (Get-FormVariable $item -Wildcard)){
                $FieldObject = (Get-FormVariable $item -Wildcard)
                $Objects += $FieldObject
                If($DebugPreference){Write-LogEntry ("Found field object [{0}]" -f $FieldObject.Name) -Source ${CmdletName} -Severity 5}
            }
            Else{
                If($DebugPreference){Write-LogEntry ("Field object [{0}] does not exist" -f $FieldObject.Name) -Source ${CmdletName} -Severity 5}
            }
        }

    }
    End{
        Return $Objects
    }
}

#region FUNCTION: Set UI fields to either visible and state
Function Set-UIFieldElement {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0,ParameterSetName="object",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [object[]]$FieldObject,
        [parameter(Mandatory=$true, Position=0,ParameterSetName="name",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [string[]]$FieldName,
        [boolean]$Enable,
        [boolean]$Visible,
        [string]$Content,
        [string]$text,
        $Source
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $MyInvocation.MyCommand

        #build field object from name
        If ($PSCmdlet.ParameterSetName -eq "name")
        {
            $FieldObject = @()
            $FieldObject = Get-UIFieldElement -Name $FieldName
        }

        #set visable values
        switch($Visible)
        {
            $true  {$SetVisible='Visible'}
            $false {$SetVisible='Hidden'}
        }

    }
    Process{
        Try{
            #loop each field object
            Foreach($item in $FieldObject)
            {
                #grab all the parameters
                $Parameters = $PSBoundParameters | Select -ExpandProperty Keys
                #loop each parameter
                Foreach($Parameter in $Parameters)
                {
                    #Determine what each parameter and value is
                    #if parameter is FieldObject of FieldName ignore setting it value
                    Switch($Parameter){
                        'Enable'    {$SetValue=$true;$Property='IsEnabled';$value=$Enable}
                        'Visible'    {$SetValue=$true;$Property='Visibility';$value=$SetVisible}
                        'Content'    {$SetValue=$true;$Property='Content';$value=$Content}
                        'Text'    {$SetValue=$true;$Property='Text';$value=$Text}
                        'Source'    {$SetValue=$true;$Property='Source';$value=$Source}
                        default     {$SetValue=$false;}
                    }

                    If($SetValue){
                       # Write-Host ('Parameter value is: {0}' -f $value)
                        If( $item.$Property -ne $value )
                        {
                            $item.$Property = $value
                            If($DebugPreference){Write-LogEntry ("Object [{0}] {1} property is changed to [{2}]" -f $item.Name,$Property,$Value) -Source ${CmdletName} -Severity 5}
                        }
                        Else
                        {
                            If($DebugPreference){Write-LogEntry ("Object [{0}] {1} property already set to [{2}]" -f $item.Name,$Property,$Value) -Source ${CmdletName} -Severity 5}
                        }
                    }
                }#endloop each parameter
            }#endloop each field object
        }
        Catch{
            Return $_.Exception.Message
        }
    }
}
#endregion


function Write-UIOutput {
	param(
        [parameter(Mandatory=$true)]
    	$UIObject,
    	[parameter(Mandatory=$true)]
    	[string]$Message,
    	[ValidateSet("Warning","Error","Info", "Start")]
    	[string]$Type,
        [switch]$Passthru
	)
    Switch ($Type) {
        "Info"    { $fg = "Gray";$Severity=1}
        "Start"   { $fg = "Cyan";$Severity=1}
        "Warning" { $fg = "Yellow";$Severity=2}
        "Error"   {$fg = "Red";$Severity=3}
        default {$fg = 'White';$Severity=1}
    }
    $date = (Get-Date -Format G)
    $UIObject.AppendText(("`n{0} :: {1}: {2}" -f $date.ToString(),$Type.ToUpper(),$Message))
    #[System.Windows.Forms.Application]::DoEvents()
    $UIObject.ScrollToEnd()

    Write-LogEntry $Message -Severity $Severity -PassThru:$Passthru
}


Function Get-UIFieldElement {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0,ParameterSetName="name",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [object[]]$Name
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $MyInvocation.MyCommand

        $objects = @()
    }
    Process{
        Foreach($item in $Name){
            If($null -ne (Get-UIVariable $item -Wildcard)){
                $FieldObject = (Get-UIVariable $item -Wildcard)
                $Objects += $FieldObject
                If($DebugPreference){Write-LogEntry ("Found field object [{0}]" -f $FieldObject.Name) -Source ${CmdletName} -Severity 5 -Outhost}
            }
            Else{
                If($DebugPreference){Write-LogEntry ("Field object [{0}] does not exist" -f $FieldObject.Name) -Source ${CmdletName} -Severity 5 -Outhost}
            }
        }

    }
    End{
        Return $Objects
    }
}


Function Add-PopupContent{
    param(
        [Parameter(Mandatory = $true, Position=0)]
        $FlowDocumentObject,
        [Parameter(Mandatory = $true, Position=1)]
        [hashtable]$ContextHash
    )
    
    #TEST $Context = $ContextHash.GetEnumerator() | Sort Name
    Foreach($Context in $ContextHash.GetEnumerator() | Sort Name)
    {
        $i=0
        $NewParagraph = New-Object System.Windows.Documents.Paragraph
        $NewRunContext = New-Object System.Windows.Documents.Run
        #$NewRunContext.Name = "PopupTitle" + $i
        $NewRunContext.Text = $Context.Name
        $NewRunContext.FontFamily = "Segoe UI"
        $NewRunContext.FontWeight="Bold"
        $NewParagraph.AddChild($NewRunContext)
        $FlowDocumentObject.AddChild($NewParagraph)

        Foreach($Context in $Context.Value){
            $i++
            Try{
                $NewParagraph = New-Object System.Windows.Documents.Paragraph
                $NewRunContext = New-Object System.Windows.Documents.Run
                #$NewRunContext.Name = "PopupContext" + $i
                $NewRunContext.Text = $Context
                $NewRunContext.FontFamily = "Segoe UI"
                $NewParagraph.AddChild($NewRunContext)
                $FlowDocumentObject.AddChild($NewParagraph)
            }
            Catch{
                $_.exception.message
            }
        }
    }
}

Function Clear-PopupContent{
    param(
        [Parameter(Mandatory = $true, Position=0)]
        $FlowDocumentObject
    )
    $FlowDocumentObject.Blocks.Clear();
}

Function Add-UIDeviceList{
    Param(
        [Parameter(Mandatory = $true, Position=0)]
        $ItemsList,
        [System.Windows.Controls.ListBox]$ListObject,
        [Parameter(Mandatory = $false, Position=2)]
        [string]$Identifier,
        [switch]$Passthru
    )

    If($null -eq $Identifier){$Identifier = ''}

    $ListObject.Items.Clear();

    foreach ($item in $ItemsList)
    {
        #Check to see if properties exists
        If($item.PSobject.Properties.Name.Contains($Identifier)){
            $ListObject.Items.Add($item.$Identifier) | Out-Null
        }
        Else{
            $ListObject.Items.Add($item) | Out-Null
        }
    }

    If($Passthru){
        return $ItemsList.$Identifier
    }
}
#endregion


Function Show-UIMenu{
    Param(
        $FormObject
    )
    ## Get the name of this function
    [string]${CmdletName} = $MyInvocation.MyCommand

    If($Global:HostOutput){Write-Host ("=============================================================") -ForegroundColor Green}
    #Slower method to present form for non modal (no popups)
    #$UI.ShowDialog() | Out-Null

    #Console control
    # Credits to - http://powershell.cz/2013/04/04/hide-and-show-console-window-from-gui/
    Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
    # Allow input to window for TextBoxes, etc
    [Void][System.Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($FormObject)

    #for ISE testing only: Add ESC key as a way to exit UI
    $code = {
        [System.Windows.Input.KeyEventArgs]$esc = $args[1]
        if ($esc.Key -eq 'ESC')
        {
            $FormObject.Close()
            [System.Windows.Forms.Application]::Exit()
            #this will kill ISE
            [Environment]::Exit($ExitCode);
        }
    }
    $null = $FormObject.add_KeyUp($code)


    $FormObject.Add_Closing({
        [System.Windows.Forms.Application]::Exit()
    })

    $async = $FormObject.Dispatcher.InvokeAsync({
        #make sure this display on top of every window
        $FormObject.Topmost = $true
        # Running this without $appContext & ::Run would actually cause a really poor response.
        $FormObject.Show() | Out-Null
        # This makes it pop up
        $FormObject.Activate() | Out-Null

        #$FormObject.window.ShowDialog()
    })
    $async.Wait() | Out-Null

    ## Force garbage collection to start form with slightly lower RAM usage.
    [System.GC]::Collect() | Out-Null
    [System.GC]::WaitForPendingFinalizers() | Out-Null

    # Create an application context for it to all run within.
    # This helps with responsiveness, especially when Exiting.
    $appContext = New-Object System.Windows.Forms.ApplicationContext
    [void][System.Windows.Forms.Application]::Run($appContext)

    #[Environment]::Exit($ExitCode);
}
#endregion

Function Open-AppSecretPrompt {
    [System.Reflection.Assembly]::LoadWithPartialName('WindowsFormsIntegration') | out-null
    [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Application') | out-null
    [System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework') | out-null
    [System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')      | out-null

    $SecretForm = @"
    <Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    xmlns:local="clr-namespace:AppSecret"
    Title="AppSecret"
    WindowStyle="None"
    WindowStartupLocation="CenterScreen"
    Height="200" Width="400"
    ResizeMode="NoResize"
    ShowInTaskbar="False">
<Window.Resources>
        <Style TargetType="{x:Type Button}">
            <!-- This style is used for buttons, to remove the WPF default 'animated' mouse over effect -->
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="Foreground" Value="#FFEAEAEA"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button" >

                        <Border Name="border" 
                                    BorderThickness="1"
                                    Padding="4,2" 
                                    BorderBrush="#FFEAEAEA" 
                                    CornerRadius="2" 
                                    Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                                  VerticalAlignment="Center" 
                                                  TextBlock.FontSize="10px"
                                                  TextBlock.TextAlignment="Center"
                                                  />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#FF919191" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Background="#313130">
        <Label x:Name="lblPassword" Content="Type in the App Secret:" HorizontalAlignment="Left" Margin="32,47,0,0" VerticalAlignment="Top" Foreground="White" RenderTransformOrigin="0.557,-0.246" Width="147"/>
        <PasswordBox x:Name="pwdBoxPassword" Width="332" Height="24" Margin="37,78,31,98"/>
        <Label x:Name="lblMsg" HorizontalAlignment="Left" Margin="37,102,0,0" VerticalAlignment="Top" Width="332" Foreground="Red"/>

        <Button x:Name="btnSubmit" Content="Submit" HorizontalAlignment="Left" Margin="286,140,0,0" VerticalAlignment="Top" Width="95" Height="50" Background="Black" Foreground="White"/>
        <Button x:Name="btnCancel" Content="Cancel" HorizontalAlignment="Left" Margin="32,140,0,0" VerticalAlignment="Top" Width="95" Height="50" Background="Black" Foreground="White"/>
        
    </Grid>
</Window>
"@

    #convert XAML to XML just to grab info using xml dot sourcing (Not used to process form)
    [xml]$XAMLPopup = $SecretForm -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window' -replace 'Click=".*','/>'

    $PopupReader = New-Object System.Xml.XmlNodeReader ($XAMLPopup)
    try{
       $Popup=[Windows.Markup.XamlReader]::Load($PopupReader)
    }
    catch{
        $ErrorMessage = $_.Exception.Message
        Write-Host "Unable to load Windows.Markup.XamlReader for popup. Some possible causes for this problem include:
        - .NET Framework is missing
        - PowerShell must be launched with PowerShell -sta
        - invalid XAML code was encountered
        - The error message was [$ErrorMessage]" -ForegroundColor White -BackgroundColor Red
        break
    }
    
    #take the xaml properties & make them variables
    $XAMLPopup.SelectNodes("//*[@Name]") | %{Set-Variable -Name "pop_$($_.Name)" -Value $Popup.FindName($_.Name)}
    
    $pop_btnCancel.Add_Click({
        $Popup.Close()
    })

    $pop_btnSubmit.Add_Click({
        If([string]::IsNullOrEmpty($pop_pwdBoxPassword.Password) ){
            $pop_lblMsg.content = "Invalid Secret, please try again or cancel"
        }Else{
            $Global:AppSecret = $pop_pwdBoxPassword.Password
            $Popup.Close()
        }
    })

    Show-UIMenu -FormObject $Popup
}