# Issue: VLC UWP app fails to install via Intune (ApplicabilityError / CI_E_INAPPLICABLE)
*Applies to: Windows 10/11, Microsoft Intune, Microsoft Store app (new), UWP deployment, IME*

## Scenario
VLC UWP was targeted to devices via Intune (Microsoft Store app). On impacted devices, the app never installs.

## Symptom
- Company Portal/Intune shows **Not Applicable** or installation never starts.
- **IME** logs report an applicability failure (**RequirementsNotMet**) for the app.

### Searchable error signatures (sanitized)
```text
-------------------------------------
--App Name:                     VLC UWP
--6-14-2025 17:57:01.706 Applicability Check: NOT Applicable 
Completed applicability check for app with id: e5e9cba6-c40a-4b5a-b39c-53e0axxxxxxx.
Operation result =  ApplicabilityError
Applicability state message: RequirementsNotMet
-------------------------------------
```

> Error code observed: **-2016215017 (CI_E_INAPPLICABLE)**

## Root Cause
1. **Market/locale availability**
   - The VLC UWP package is **not available** in certain regions/locales. When the device’s Store market/locale is set to an unsupported country/language, the Store endpoint may return **“Data not found”**, causing Intune applicability to fail.
2. **General applicability conditions** (when triggered)
   - App not available in the specific **region/market**
   - App not available for the specific **language/locale**
   - Device OS does not meet the app’s **Store requirements**
3. **Confirmed case**
   - VLC UWP is not available in some specific countries (e.g., **DE**), which leads to the **Not Applicable** state.

## Evidence
- App available (Download active): `https://apps.microsoft.com/detail/9nblggh4vvnh?hl=en-US&gl=HK`  
- App unavailable (Download greyed out): `https://apps.microsoft.com/detail/9nblggh4vvnh?hl=en-US&gl=DE`  
- With device region set to **Germany (DE)**, Store query returned **“Data not found”**.

---

## Recommendation
**Align market/locale with supported availability**
  - Change the device’s **Region** (Country or region) and **Windows display language** to a supported market (e.g., English + a market where Download is available).
  - Reboot, then trigger Intune sync and retry the install.
  - Rationale: VLC UWP **does not currently support the German locale**; switching system language to **English** resolves the issue.

---
