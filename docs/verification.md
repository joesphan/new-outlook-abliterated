# Verification loop

How each claim in this repo was checked. Reproducible on any machine with the new Outlook installed.

## 1. Prove the block actually applies

```powershell
ipconfig /flushdns
Resolve-DnsName msft-ssp.adnxs.com | Select-Object Name, Type, IPAddress
# expect: A 0.0.0.0
```

## 2. Watch what the app really contacts

Flush the resolver cache, restart the client, let the inbox settle, then read the cache back. Any blocked name that appears here was *attempted* by the app and refused:

```powershell
ipconfig /flushdns
Stop-Process -Name olk -Force
Start-Process explorer.exe 'shell:AppsFolder\Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows'
# wait for the row to render, then:
ipconfig /displaydns | Select-String 'adnxs|msn\.com|3lift|doubleclick|appnexusgslb|xandrpme'
```

A useful negative signal: on a healthy account the cache contains the mail-service hostnames. When it contains *only* the blackholed ad names and no mail hosts, the primary traffic is being resolved through the app's own encrypted resolver — which is why enumerating further ad hosts from the OS cache is a dead end.

## 3. Visual proof

`WebView2` renders nothing under `PrintWindow`, and `SetForegroundWindow` is refused to background processes, so the capture must raise the window with the ALT-key trick and then read the screen:

```powershell
.\tools\Capture-OutlookWindow.ps1 -Out .\shot.png
```

The script prints whether the window actually became foreground (`match=True`) before capturing — if that is `False`, the image is whichever window happened to be on top, not Outlook.

## 4. Cache forensics

The UI modules are stored uncompressed in the profile's service-worker cache, which makes them greppable:

```
%LOCALAPPDATA%\Microsoft\Olk\EBWebView\Default\Service Worker\CacheStorage\<hash>\<cache-guid>\<key>_0
```

Useful needles:

| Needle | What it identifies |
|---|---|
| `messageAdRowStore` | the native-ad module |
| `adIds.length` | the row render gate |
| `msft-ssp.adnxs.com` | auction endpoint |
| `arc.msn.com/v4/api/selection` | creative selection URL |
| `ads-shutdown-nativeAds` | kill-switch names (registry only) |

## Two pitfalls when patching bytes

1. **Character offsets are not byte offsets.** The bundles contain non-ASCII bytes; `String.IndexOf` on a decoded string returns a position that will not match the byte array. Search the byte array (or convert with `UTF8.GetByteCount` of the prefix).
2. **Length must not change.** CacheStorage entries carry stream sizes in their metadata; a same-length replacement keeps the entry valid. Changing the length requires rewriting metadata you do not want to touch.

None of that makes the patch durable — see [dead-ends.md](dead-ends.md) §2.
