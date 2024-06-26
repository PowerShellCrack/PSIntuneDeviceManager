# Change log for IntuneDeviceManagerUI.ps1

## 2.0.2 - April 14, 2024

- Removed Authtoken check; no longer need with Graph modules
- Fixed Device retrieval. Used newer IDMCmdlets. 

## 1.5.1 - August 8, 2022

- Updared readme.
- Validated script still works

## 1.5.1 - August 8, 2022

- Changed date output to actual date format; better readability
- Added Admin Consent switch to script; to allow global admin permissions
- Added the ability to update device extension attributes; does require AdminConsent
- Added more height to UI to account for additional features.

## 1.5.0 - August 5, 2022

- Using new IDMcmdlet 1.0.1.2 for Batch processing; speeds up graph output

## 1.4.9 - July 31, 2022
- Cleanup up UI slightly; removed module check and changed to connect user and organized xaml content
- Must use IDMcmdlet 1.0.0.8; supports new graph batch and multithreaded Graph requests
- Added ability to assign new user to device; replaced configmgr device detection
- Added more context to listing devices and users to show status
- Added helper scripts to contain handlers and help menu; reduce lines in main code.

## 1.4.8 - July 30, 2022
- changed Module check to hashtable to incorporate versions
- Fixed device id output; Swapped Azure device id to intune ID

## 1.4.7 - July 29, 2022

- Added device prefix change within UI; allows search without restart UI (thanks smithc)
- Changed some button names and added pagination menu; still work in progress
- Moved Stale device tab behind Renamer tab; made use of white space by adjusting login info
- Added descriptive output for data analytics.

## 1.4.6 - July 28, 2022

- Formatted device hardware retrieval to be more readable
- Fixed dropdown list ; populated null values
- Stale device tab created; nothing is functional yet

## 1.4.5 - July 27, 2022

- Fixed issue where EAS devices scan is need; issue with runspace scripts
- Removed Invoke-Graphrequests from Runspace.ps1; now part of IDMCmdlets module
- Fixed Device Assignments script to load on startup
- Changed functions names in UI and Runspace; doesn't conflict with IDMCmdlets module

## 1.4.4 - July 26, 2022

- Added detection for Offline Autopilot profile deployments; rearranged layout
- Removed Msgraph.ps1, Intune.ps1, Autopilot.ps1 and replaced with IDMCmdlet module
- Change Device info to be read only instead of disabled; allows clipboard
- Rearranged UI for Azure device to make easier read

## 1.4.3 - July 11, 2022

- Created runspace pool for assignment data retrieval; faster by 2 minutes.
- Fixed View assignment button status and lockup issue.
- Changed button to show disabled when clicked and then reenable when complete.
- Fixed assignment export; one-drive changes path; use registry key to find it.
- Updates Autopilot module; removed dependency

## 1.4.2 - July 7, 2022

- Change the function of refresh button to update list instead or use cache list.
- Added more modern look to dropdowns, buttons, and checkboxes.
- Added Device filter to limit device retrieval; helps with msgraph limit
- Working multi-threaded pieces; allowing faster load time for assignments
- Added data output for troubleshooting; graph, properties and data out

## 1.4.1 - June 29, 2022

- Added progress UI; shows status messages clearer.
- Added Assignment UI; processes device and user assignments in single pane
- Added Autopilot Profile change; allows json export and group tag change
- Added Device Category change and Autopilot grouptag change
- Changed all functions to IDM prefix; allow no conflict

## 1.3.1 - June 23, 2022

- Changed UI size to 1026 x 768 window
- Converted to runspace to allow multithreading
- Added module check popup. Allows to install modules during launch.


## 1.3.0 - October 20, 2021

- Added App principal service login
- re-arranged advanced menu; easier navigation
- Hide advanced menu; can be activated using -AdvancedMode parameter

## 1.2.0 - October 19, 2021

- fixed error when no device found; provided message to UI
- Cleaned up UI; removed title and added more space for device list
- Added logging function; changed UI logging to passthru to logging file


## 1.1.5 - April 13, 2021

- Fixed OU retrieval

## 1.0.0 - March 21, 2021

- initial UI design
