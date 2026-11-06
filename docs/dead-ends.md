# Dead ends — approaches that do not work

Each item below was attempted and observed, not reasoned about. The goal is to save the next person the same hours.

---

## 1. Per-app WebView2 flags (`--host-resolver-rules`)

**Attempted**: write a machine- or user-scoped `AdditionalBrowserArguments` value naming `olk.exe`, intending `--host-resolver-rules=MAP arc.msn.com ~NOTFOUND`.

```
HKCU\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments
    olk.exe = --host-resolver-rules=MAP arc.msn.com ~NOTFOUND
```

**Result**: no effect. The argument never reached the browser process.

**Why**: this registry shape is a Visual Studio Code debugger convention ("so that the debugger can find the proper port"), not a WebView2 policy. The published WebView2 policy list — `BrowserExecutableFolder`, `ChannelSearchKind`, `DowngradeVersion`, `ReleaseChannels`, `ExperimentationAndConfigurationServiceControl`, `HttpAllowlist`, a few CORS/TLS toggles — contains no `AdditionalBrowserArguments`.

**Evidence**: `msedgewebview2.exe` command line for the Outlook-hosting browser process, sampled after a clean restart, contained no `host-resolver` argument:

```
--embedded-browser-webview=1 --webview-exe-name=olk.exe … --disable-features=msEnhancedTrackingPreventionEnabled
```

Note `--disable-features=msEnhancedTrackingPreventionEnabled`: the app deliberately disables the runtime's own tracker blocking.

---

## 2. Patching the cached UI bundle

**Attempted**: the row's render guard was located in the profile's service-worker cache, and the guard expression replaced in place with a constant, preserving byte length so the cache entry metadata stayed valid.

```
before: let o=(0,eH.K)().adIds.length;
after:  let o=0/*##################*/;
```

Patch written at the exact byte offset; file length unchanged (63214 bytes); context verified by re-reading the file. The V8 code cache was also invalidated.

**Result**: works until the app is restarted, then reverts. After relaunch the patched cache entry was **gone** — deleted, and the module absent from the profile entirely:

```
ad-module copies (search: messageAdRowStore): 0
```

**Why**: the service worker re-materialises its cache on every launch from `res.public.onecdn.static.microsoft`. A local edit of `CacheStorage\…\<key>_0` is not durable, and for a lazily loaded module it may be overwritten before the module is even evaluated.

**Implication**: any "patch the JS" tool for this client is either a boot-time race or a no-op. Do not ship it as a fix.

---

## 3. Blocking the ad network

**Attempted**: `0.0.0.0` entries for the auction and bidder chain:

```
arc.msn.com
msft-ssp.adnxs.com
msft-ssp-uswest.adnxs.com
msft-ssp.appnexusgslb.com
xandrpme-msft-ssp.trafficmanager.net
xandrpme-g-geo.trafficmanager.net
ib.adnxs.com
ib.anycast.adnxs.com
secure.adnxs.com
acdn.adnxs.com
lax1-ib.adnxs.com
fra1-ib.adnxs.com
adnxs.com
adnxs-simple.com
```

**Result**: partial, and this is what the repo ships. Third-party creatives stop — the rows that previously carried an Airbnb listing, an eBay listing and an AARP job ad are replaced by Microsoft's own `Upgrade Your Account` promo. The slot survives.

**Why**: the slot is a free-tier product surface. When no bidder fills it, the service backfills with its own inventory.

---

## 4. Toggling the kill-switch flights locally

**Attempted**: find and flip `ads-shutdown-nativeAds` / `ads-shutdown-displayAds` / `ads-hideDisplayAds` in the client.

**Result**: impossible from the client.

**Why**: those names appear only in the client's flight *description registry*. The ad module never references them — a search for the strings across every cached script returns hits only in the registry file. They are ECS (server-delivered) switches, honoured where the response is composed.

---

## 5. "Decompile and rewrite `olk.exe`"

**Attempted**: read the executable to inspect it.

**Result**: unreadable.

```
Path: C:\Program Files\WindowsApps\Microsoft.OutlookForWindows_1.2026.1020.100_x64__8wekyb3d8bbwe\olk.exe
Test-Path → False   (ACL: TrustedInstaller; the WindowsApps directory denies enumeration to standard users)
```

**Why it is also the wrong lever**: the executable is a thin MSIX host for WebView2. The UI, including the ad row, is JavaScript delivered by the service. Even with ownership taken, there is no ad logic in the binary to ablate — and redistributing the client is copyright infringement.

---

## Summary table

| Approach | Outcome |
|---|---|
| WebView2 arg policy | Ignored — no such policy |
| Cached-bundle patch | Reverted on next launch |
| Hosts block of auction chain | Third-party creatives gone, slot remains |
| Flight kill switches | Server-side only |
| Decompile/rewrite the exe | Unreadable, and no ad logic inside |
