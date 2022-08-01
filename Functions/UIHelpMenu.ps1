# Setup help menu
#=================================
$syncHash.tbADSearchHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("Select the AD search field to determine where computer objects are locate."
                "The filter can be used during OU Search")
    }
    Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
    $syncHash.HelpPopup.VerticalOffset="50"
    $syncHash.HelpPopup.Placement="Right"
    $syncHash.HelpPopup.IsOpen = $true
})

$syncHash.tbADSearchHelp.Add_MouseLeave({
    $syncHash.HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
})

$syncHash.tbCMSiteSearchHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("Fill in CM site server and Site code to connect to ConfigMgr")
        Tip = @("Specify the attribute used to determine if device is a match")
    }
    Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
    $syncHash.HelpPopup.VerticalOffset="240"
    $syncHash.HelpPopup.Placement="Right"
    $syncHash.HelpPopup.IsOpen = $true
})

$syncHash.tbCMSiteSearchHelp.Add_MouseLeave({
    $syncHash.HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
})

$syncHash.tbMoveOUHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("Select an option on how to move the device to an OU.")
        Tip = @("Specify an OU in LDAP format")
    }
    Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
    $syncHash.HelpPopup.VerticalOffset="340"
    $syncHash.HelpPopup.Placement="Left"
    $syncHash.HelpPopup.IsOpen = $true
})

$syncHash.tbMoveOUHelp.Add_MouseLeave({
    $syncHash.HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
})

$syncHash.tbRuleTesterHelp.Add_MouseEnter({
    $PopupContexts = @{
        Help = @("This is a test tool that allow you to test the configurations")
        Note = @("Rule tester ignores AD Search filter and Method options.","Digits are simulated")
    }
    Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
    $syncHash.HelpPopup.VerticalOffset="380"
    $syncHash.HelpPopup.Placement="Left"
    $syncHash.HelpPopup.IsOpen = $true
})

$syncHash.tbRuleTesterHelp.Add_MouseLeave({
    $syncHash.HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
})

$syncHash.tbRuleGenHelp.Add_MouseEnter({
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
    Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
    $syncHash.HelpPopup.VerticalOffset="50"
    $syncHash.HelpPopup.Placement="Left"
    $syncHash.HelpPopup.IsOpen = $true
})

$syncHash.tbRuleGenHelp.Add_MouseLeave({
    $syncHash.HelpPopup.IsOpen = $false
    Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
})
