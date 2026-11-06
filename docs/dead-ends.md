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

**Attempted**: read the package to inspect it. The first try reported the path did not exist — that
was **not** an ACL denial: the app had silently updated (`1.2026.1020.100` → `1.2026.1026.100`) and the
versioned directory was gone. With an elevated token and the live path, the package enumerates
(141 entries) and reads normally.

**Result**: decompiled — and empty of anything to strip. `olk.exe` is 177,464 bytes; the logic sits in
`olkmain.dll` / `nh.dll` / `olknh.dll`, which are WebView2 host wrappers, and the ad surface is
JavaScript plus the host's own resource pipeline. Full inventory, recovered symbols and their
consequences: [native-host.md](native-host.md).

**Why a rewrite is not the same axis**: rewriting the client is legitimate; reusing its decompiled
code is not. But nothing in the binary decides whether the row appears, so a rewrite that starts
from these binaries has no seam to cut either.

---

## 6. Injecting browser arguments — the environment variable route

**Attempted**: the registry policy is not a real policy (§1), but `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`
is a documented WebView2 mechanism. Set it per-user and restart the app:

```powershell
[Environment]::SetEnvironmentVariable('WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS',
  '--host-resolver-rules="MAP arc.msn.com ~NOTFOUND"', 'User')
```

**Result**: no effect. The browser process command line, sampled after the restarted app was up,
contained the app's own flags and not ours:

```
--embedded-browser-webview=1 --webview-exe-name=olk.exe --webview-exe-version=1.2026.1026.100
--user-data-dir=... --disable-features=msEnhancedTrackingPreventionEnabled
--enable-features=msSingleSignOnOSForPrimaryAccountIsShared,DocumentPolicyNetworkEfficiencyGuardrails
```

**Why**: this is the exact case WebView2 documents — additional arguments from the environment are
a fallback for apps that do not supply their own options. This app does supply them. Its symbols
say so directly:

```
WrappedEnvironmentOptions::SetAdditionalBrowserArguments(basic_zstring_view<wchar_t>)
CreateCoreWebView2EnvironmentWithOptions(..., environmentOptions.Get(), ...)
```

and `olkmain.dll` embeds the literals `--enable-features=` / `--disable-features=`. The argument
string is composed in code with no user input.

---

## 7. Why the creative survives a DNS block at all

`nh.dll` registers resource handlers of its own:

```
OutlookWebHost::Outlook::AddWebResourceRequestReceived()
OutlookWebHost::Outlook::AddUnfilteredWindowWebRequestReceived()
OutlookWebHost::Outlook::MakeResourceRequestResponse()
```

The native host can fetch a resource through its own authenticated channel and hand the response
to the WebView. A request served that way never resolves a name the hosts file governs, which is
why the row survives with every ad host pointed at `0.0.0.0`. See [native-host.md](native-host.md).

---

## Summary table

| Approach | Outcome |
|---|---|
| WebView2 arg policy | Ignored — no such policy |
| `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` env var | Ignored — the app supplies its own compiled-in options |
| Cached-bundle patch | Reverted on next launch |
| Hosts block of auction chain | Third-party creatives gone, slot remains |
| Flight kill switches | Server-side only |
| Decompile the package | Works; nothing in it decides the row |
| Native resource pipeline | Serves the creative in-band; no name to block |
