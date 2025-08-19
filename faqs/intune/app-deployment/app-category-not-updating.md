# Issue: Deleted App Category Still Appears in Company Portal
*Applies to: Company Portal for Windows*

## Scenario
An App Category was deleted from Intune; however, it continues to appear in the **Company Portal**.

## Symptom
- Deleted app category still shows in Company Portal UI.  
- Intune portal shows the category has been removed.  
- Devices continue to display the stale metadata in Company Portal.

## Resolution / Workaround
- Edit the affected app’s **description** (e.g., add a period or minor change).  
- Save the change.  
- On the device, trigger a **manual sync** in Company Portal several times.  
- This action forces a metadata refresh and usually clears the deleted category.  