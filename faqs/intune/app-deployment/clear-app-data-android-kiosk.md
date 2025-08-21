# Issue: Unable to clear app data on iDATA (Android Enterprise Dedicated) devices
*Applies to: Android 11+, Android Enterprise (Dedicated/Kiosk), Android Management API, Intune (Android Enterprise), OEM: iDATA*

## Scenario
Devices are configured as **kiosk** (dedicated) and admins/users attempt to clear application data in Settings for the kiosk app.

## Symptom
- In **Settings > Apps > <App> > Storage & cache > Clear storage / Clear data**, tapping **Clear data** triggers a system dialog and the action fails.
- Dialog text observed (may vary by OEM/locale):
    ```text
    clear data
    unable to delete data for app
    ```

## Assessment / Root Cause
This behavior is **by design** beginning with **Android 11** for devices configured in kiosk mode.

> **Change note (Nov 2020):**  
> Starting in Android 11, users can no longer clear app data or force stop applications when the device is configured as a kiosk (that is, when the `InstallType` of one application in `ApplicationPolicy` is set to `KIOSK`).

---

## References
- [Release notes — Android Management API — Google for Developers (Nov 2020)](https://developers.google.com/android/management/release-notes)
