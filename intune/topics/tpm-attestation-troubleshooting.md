# TPM Attestation Troubleshooting in Windows Autopilot
*Applies to: Windows Autopilot (Pre-provisioning), Windows 10/11, Intune*

## Summary
This article details the Pre-Provisioning Autopilot workflow for firmware-based TPM Attestation and troubleshooting steps. Tools and logs are valid for Windows 11, however not all commands may be valid for Windows 10.

---

## Background
Trusted Platform Module (TPM) is designed to provide hardware-based security-related functions.

During the **“Securing Your Hardware”** step in Pre-Provisioning Autopilot, TPM Attestation is initialized. TPM Key Attestation allows the entity requesting a certificate to cryptographically prove to a CA that the RSA key in the certificate request is protected by a TPM that the CA trusts.

Unlike hardware-based TPM (Discrete or Integrated), **Firmware TPM (fTPM)** doesn’t include all needed certificates at boot time. It must retrieve them from the manufacturer on first use.

Firmware TPM providers:
- **Intel:** Intel Platform Trust Technology (PTT)  
- **AMD:** AMD Firmware TPM (fTPM)  
- **Qualcomm**

---

## Before You Start

1. **Confirm TPM 2.0 status and manufacturer**
   ```powershell
   tpmtool getdeviceinformation
'''Example output: 
TPM Present: True
TPM Version: 2.0
TPM Manufacturer ID: AMD
Ready For Attestation: True'''
2. **Enable debug logging in Registry**
   ```powershell
   $AutoEnrollmentPath = 'HKLM:\SOFTWARE\Microsoft\Cryptography\AutoEnrollment'
   New-ItemProperty -Path $AutoEnrollmentPath -Name 'Debug' -Value 1 -PropertyType DWORD
3. **Install optional TPMTool commands**
    '''powershell
    tpmtool.exe oc add

