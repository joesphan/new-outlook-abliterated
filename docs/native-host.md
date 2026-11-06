# Native host — what is actually inside the package

Static analysis of `Microsoft.OutlookForWindows 1.2026.1026.100` (x64), read from
`C:\Program Files\WindowsApps\Microsoft.OutlookForWindows_1.2026.1026.100_x64__8wekyb3d8bbwe`
with an elevated token. Nothing here is redistributed; the notes describe structure and behaviour.

## Package inventory (141 entries)

| Binary | Size | Role |
|---|---|---|
| `olk.exe` | 177,464 | launcher |
| `olkmain.dll` | 4,807,480 | host bootstrap — creates the WebView2 environment |
| `olknh.dll` | 3,715,896 | native host |
| `nh.dll` | 4,890,936 | native host framework (WebView2 wrappers, resource pipeline) |
| `win32gql.dll` | 11,392,656 | GraphQL service (`Win32Outlook.GraphQLService`) |
| `WebView2Loader.dll` | 169,384 | WebView2 loader |
| `Microsoft.Exchange.Clients.SmimeAX.dll` | 204,472 | S/MIME COM host |
| `Microsoft.Internal.Mime.dll` | 1,793,168 | MIME parser |
| `Dino.dll` | 590,752 | native host extension |

`modules.json` — five native modules, all `container: inproc`:
`nh-mod-auth`, `mmpiehost`, `mmwebhostsystem`, `olk-mod-general`, `mmoutlookwebcontext`.

`extensions.json` — **not** WebView2 browser extensions. Four native COM hosts:
`FLORA` (file-link handling), `Win32Gql` (`Manifest: win32gql.dll,#2`), `Dino`, `SMIME`.

## The native host owns the WebView

Decorated C++ symbols recovered from RTTI/PDB-style strings in `nh.dll` and `olkmain.dll`:

```
Microsoft::NativeHost::WebView2::WrappedEnvironmentOptions::SetAdditionalBrowserArguments(basic_zstring_view<wchar_t>)
Microsoft::NativeHost::WebView2::WrappedEnvironmentOptions::GetAdditionalBrowserArguments()
Microsoft::NativeHost::WebView2::WrappedEnvironmentOptions::SetUserDataFolder(...)
Microsoft::NativeHost::WebView2::WrappedEnvironmentOptions::SetExclusiveUserDataFolderAccess(bool)
CreateCoreWebView2EnvironmentWithOptions(environmentOptions.GetBrowserExecutableFolder(),
                                         environmentOptions.GetUserDataFolder(), ...)
Microsoft::NativeHost::WebView2::WrappedView::SetVirtualHostNameToFolderMapping(host, folder, kind)
```

Consequences:

- The browser arguments are **composed in code** and passed explicitly to
  `CreateCoreWebView2EnvironmentWithOptions`. `olkmain.dll` contains the literals
  `--enable-features=` and `--disable-features=`. There is no user-facing input to that string.
- Observed live on the browser process:
  `--disable-features=msEnhancedTrackingPreventionEnabled --enable-blink-features=DragAndDropJSFileObjects --enable-features=msSingleSignOnOSForPrimaryAccountIsShared,DocumentPolicyNetworkEfficiencyGuardrails --isolate-origins=…`
  No `msExtensions`, so WebView2 browser extensions are not enabled and none are added
  (`AddBrowserExtension` appears nowhere in any binary).

## The native host serves web resources itself

```
Microsoft::NativeHost::Outlook::OutlookWebHost::AddWebResourceRequestReceived()
Microsoft::NativeHost::Outlook::OutlookWebHost::AddUnfilteredWindowWebRequestReceived()
Microsoft::NativeHost::Outlook::OutlookWebHost::MakeResourceRequestResponse()
```

The host registers `WebResourceRequested` handlers and can synthesise responses. This is why
blackholing every ad hostname changes nothing: resources can be fetched through the host's own
authenticated channel and handed to the WebView, so the request never traverses a name the
hosts file governs.

## Local state holds no ad switch

- `%LOCALAPPDATA%\Microsoft\Olk\UserSettings.json` — identities, window geometry, updater ring,
  `OWASettings.clientId`, and `Flights.FlightList` (41 opaque tokens). No ad flag.
- `%LOCALAPPDATA%\Packages\…\Settings\settings.dat` — a registry hive whose only keys are
  `LocalState` and `RoamingState`, both empty.
- `%LOCALAPPDATA%\Microsoft\Olk\xpdApi.log` (83 MB) — updater agent events only; no ad traffic.

The flight tokens are not a simple encoding: base64 decoding yields a constant `2B 1C 48 13`
prefix followed by high-entropy bytes, and no single-byte XOR key produces text. They are
service-issued and are not a client-side switch.

## Conclusion

There is no ad code in these binaries to remove and no local variable that gates the row.
The client renders an `adIds` list it receives; the list is produced service-side and can be
delivered over the host's own resource pipeline. Removal is an entitlement decision
(Microsoft 365) or a different client.
