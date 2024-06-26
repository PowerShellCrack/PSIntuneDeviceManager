# PSIntuneDeviceManagerUI
a UI to manage Intune devices, that may be more difficult to do within portal.

**WORK-IN-PROGRESS** This is still in development.

**NEW** Revampled _Hybrid Device Renamer UI_ to _Intune Device Manager UI_; built to allow more management or Intune devices besides just renaming devices.

## Required Modules
- Az.Accounts
- Microsoft.Graph.Authentication
- Microsoft.Graph.Applications
- WindowsAutopilotIntune
- IDMCmdlets [_minimum version: **1.0.2.7**_]

## Here is how you use it:

### New Parameters for **IntuneDeviceManagerUI.ps1**

| Name | Type | Default value | Help | Notes|
|--|--|--|--|--|
|DevicePlatform|String |Windows| Filters device operating system on launch. Options are: _Windows,Android,MacOS,iOS_|
|DevicePrefix |String || Filters device query on launch|
|RenameEnablement |Switch||**Rename Operations:** Enables Renamer tab in UI (If devices are found)|
|ManageStaleDevices|Switch|| **NOT READY**|
|RenameRules |Hashtable |@{RuleRegex1 = '^.{0,3}';RuleRegex2 ='.{0,3}[\s+]'}|**Rename Operations:** Consist of 4 regex rules: _RuleRegex1,RuleRegex2,RuleRegex3,RuleRegex4_|Sets default regex rules on launch; can be changed within UI|
|RenameAbbrType |String|Chassis|**Rename Operations:** Options are: _No Abbr,Chassis,Manufacturer,Model_|Sets default chassis check on launch; can be changed within UI|
|RenameAbbrKey |String|'Laptop=A, Notebook=A, Tablet=A, Desktop=W, Tower=W, Virtual Machine=W'|**Rename Operations:** Controls what abbreviation to use when value is found based on type |Sets default abbreviation on launch; can be changed within UI|
|RenamePrefix |String||**Rename Operations:** Sets default prefix on launch | can be changed within UI|
|RenameAppendDigits |Int32|3|**Rename Operations:** Options are: _0,1,2,3,4, or 5_|Sets default digits to append to name on launch but can be changed within UI|
|RenameSearchFilter |String||**Rename Operations:** Sets default prefix on launch| can be changed within UI|
|CMSiteCode |String||Not working yet|
|CMSiteServer |String||Not working yet|
|AppConnect|Switch||Set to use App ID instead of UPN for MSGraph|
|ApplicationId|string||Set App ID to connect with|
|TenantId|string||Tenant ID needed for App ID|

### Parameters for **HybridDeviceRenamerUI.ps1**

| Name | Type | Default value | Help | Notes|
|--|--|--|--|--|
|Rules|hashtable| @{RuleRegex1 = '^.{0,3}';RuleRegex2 ='.{0,3}[\s+]'}|consist of 4 regex rules: RuleRegex1,RuleRegex2,RuleRegex3,RuleRegex4|Sets default regex rules on launch; can be changed within UI|
|DevicePlatform|string|'Windows'|Options are: Windows,Android,MacOS,iOS|Sets default platform on launch|
|FilterJoinType|string|Hybrid|Options are: Hybrid,Azure,Registered,Domain|
|SearchFilter|string|*||Sets default filter search on launch; can be changed within UI|
|AbbrType|string|Chassis|Options are: No Abbr,Chassis,Manufacturer,Model|Sets default chassis check on launch; can be changed within UI|
|AbbrKey|string|'Laptop=A, Notebook=A, Tablet=A, Desktop=W, Tower=W, Virtual Machine=W'||Sets default abbreviation on launch; can be changed within UI|
|Prefix|string|||Sets default prefix on launch; can be changed within UI|
|AppendDigits|int|3|Options are: 0,1,2,3,4, or 5|Sets default digits to append to name on launch; can be changed within UI|
|CMSiteCode|string||Not working yet|
|CMSiteServer|string||Not working yet|
|AppConnect|switch||Set to use App ID instead of UPN for MSGraph|
|ApplicationId|string||Set App ID to connect with|
|TenantId|string||Tenant ID needed for App ID|

To launch the script; its best to call it through PowerShell, like so:

```powershell
#connect normally
.\IntuneDeviceManagerUI.ps1

#connect with filtered devices and rename option available
.\IntuneDeviceManagerUI.ps1 -DevicePrefix DTOLAB -RenameEnablement

#connect using a Application id
.\IntuneDeviceManagerUI.ps1 -AppConnect -ApplicationId '94727407-0ae1-4505-b4eb-a5b0ff155b05' -TenantId 'f4387048-a542-4b0b-b1a6-7e62fe5f422e'

#use prefix to search device names and enable the stale management and rename enablement tabs
.\IntuneDeviceManagerUI.ps1 -ManageStaleDevices -DefaultDeviceAge 120 -RenameEnablement -DevicePrefix DTOLAB
```

The script will check for prerequisites:

- PowerShell 5.1 or higher
- MSGraph Intune module
- Azure AD
- RSAT Tools/PowerShell Module
  - If its ran on a Domain joined device


if it finds a missing one, it will prompt to install them…so if it’s not ran as privilege administrator; it will install under user context. You will see them as "no" in red at the bottom status bar of the UI

![Install Module](.images/UIWindow_Installmodule.jpg)

> Once all prereqs are installed and everything shows green in the status bar (besides MSGraph Connected), you can continue. If not restart app after install

Once the UI is launched, here are the steps to perform:
![Launch](.images/UIWindow_Initial.jpg)

1. Click the button:  Connect to Intune (MSGraph)

    a. This will minimize the UI and request your Azure login
    b. You will be required to accept the "allow permissions to read and write to Intune". Scroll down and click Accept
    c. You may have to bring the UI back up from the task bar. its designed to be restore window, but sometimes it does not work

> If you created a application principal account, and use -AppConnect parameter, the prompt is slightly different

![AppConnect](.images/UIWindow_AppConnect.jpg)

2. Once its connected, it will immediately start pulling Windows AAD devices into the list.
    a. This is pre-configured to filter anything other than Windows.

> NOTE: this may take a bit, depending on device count. The UI may look like its not responding (it is not a multithreaded UI...yet).

![Connect](.images/UIWindow_Connected.jpg)

3. You can search the device in the search window (it will filter as you type).

4. Once you select a device, the script will grab the detailed device and user information from Azure AD.

![Selected](.images/UIWindow_SelectedDevice.jpg)

## For Rename Operations

> NOTE: must use _-RenameEnablement_ parameter

![Rename](.images/UIWindow_DeviceRename.jpg)

1. Click Renamer Tab

2. Click on the Sync button to corelate the Azure account with the AD account.
    a. If the account is found, the accounts distinguished name will appear below.
    b. And it will auto generate the name as well (based on rules set)

3. The auto generated name, will use the Generation rules specified in the configure tab
    a. This is pre-configured to use your naming convention but can be changed. *
    b. If you change the rules, click the Sync button to refresh the name

4. Select the move to OU checkbox to move the AD object to another OU.
    a. This is pre-configured to the root computers OU. This can be changed in configure tab.

5. Click Rename Device.

> WARNING: this will attempt to rename the Intune object and not in AD.

    a. If you refresh the list and select the same device again; a warning message will come up near bottom of screen stating there is a pending rename action.
    b. You can also check Intune and see the same action.

## Stale Devices (Not Working)

> NOTE: must use _-ManageStaleDevices_ parameter

![Stale](.images/UIWindow_StaleDevice.jpg)

## For Retrieving Assignments

1. Select a device

2. Click Details Tab

3. Click Get Assignments

> NOTE: this may take a while to load, depending on objects in Intune and Azure. The UI may look like its not responding (its not a multithreaded UI...yet). Once complete though a screen will come up:

![Selected](.images/UIWindow_Assignments.jpg)

4. This list can further be searched or filtered. It can also be exported to CSV

## Logging

The UI does output performed clicks in the logging tab. Not everything is logged ***

![Selected](.images/UIWindow_logging.jpg)

## Output

The script runs in a runspace so data cannot be access directly. However, after script is completed and closed, data can be extracted.
By default the script will output to a $global:syncHash variable. In there it data is retrievable

```powershell
#Data input from parameters
$global:syncHash.properties

#output of all data selected
$global:syncHash.data

#UI errors
$global:syncHash.error
```

## Features that don’t exist or do not work just yet:
- Progressbar during assignment loading or device retrieval
- multithreading while pulling data
- Alternate AD credentials (eg PIV)
- Option to not increment name (overwrite domain object)
- *All Generation Methods except "User OU Name"
- ** Azure government support not working
- *** Some logging is missing
- Configuration Manager connection sync for assignments
- Get Assignments are no longer working since move to new Grpah SDK. Working issue as of 4/1/2024
- Stale device no longer retrieves devices, working issue as of 4/1/2024


# DISCLAIMER
> Even though I have tested this to the extend that I could I want to ensure your aware of Microsoft’s position on developing scripts.

This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys’ fees, that arise or result
from the use or distribution of the Sample Code.

This posting is provided "AS IS" with no warranties, and confers no rights. Use
of included script samples are subject to the terms specified
at https://www.microsoft.com/en-us/legal/copyright.
