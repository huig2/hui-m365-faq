# Issue: Edge Transport server fails to deliver emails to internal Exchange servers
*Applies to: Exchange Edge Transport, Exchange Server, Mail Flow*

## Scenario
An Edge Transport server attempted to deliver messages to an internal Exchange server, but all emails were stuck in the queue with authentication errors.  

## Symptom
- Messages remain in the Edge Transport queue and fail to deliver.  
- Queue viewer shows error: 
    ```[{LED=451 4-4.395 Target host responded with error. -> 454 4.7.0 Temporary authentication failure}; 
    {MSG=}; {FQDN=<EdgeServerName>.<domain>.com}; {IP=<internal_IP>}; {LRT=15/07/2025 09:21:04}]
    ``` 
- Event logs show certificate-related errors on the Edge server.

## Root Cause
1. The default transport certificate on the Edge server was accidentally deleted.
2. Exchange attempted to use the missing certificate for server-to-server authentication, causing mail flow failure. 

Example error in Application log in Event Viewer:

    ```
    Microsoft Exchange could not load the certificate with thumbprint of <ThumbprintID> 
    from the personal store on the local computer. 
    This certificate was configured for authentication with other Exchange servers. 
    Mail flow to other Exchange servers could be affected by this error.
    ```

---

## Recommendation
- Recreate the default transport certificate.  
- Re-establish the Edge Subscription.
    ```powershell
    # Create new Edge subscription file
    New-EdgeSubscription -FileName "C:\EdgeSubscriptionFiles\EdgeSubscription01.xml"

    # Import Edge subscription file into AD site
    New-EdgeSubscription -FileData ([byte[]]$(Get-Content -Path "C:\XMLImport\EdgeSubscription01.xml" -Encoding Byte -ReadCount 0)) -Site "YourADSite"

    # Start synchronization
    Start-EdgeSynchronization -TargetServer Edge01
    ```