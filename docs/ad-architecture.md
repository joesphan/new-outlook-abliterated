# Ad delivery chain — new Outlook for Windows

Observed on `Microsoft.OutlookForWindows 1.2026.1020.100`, WebView2 `156.0.4314.58`, user-data folder `%LOCALAPPDATA%\Microsoft\Olk\EBWebView`.

The client is a React/TypeScript OWA build running inside WebView2. It requests its UI modules from `res.public.onecdn.static.microsoft/owamail/hashed-v1/scripts/…`; the ad surface lives in `owa.55698.m.<hash>.js`. Everything below is client-observable — no binary inspection.

## 1. Native (in-list) ads

The row is produced by an ad module that speaks Xandr OpenRTB and populates a client store consumed by the message list.

Auction endpoint:

```
https://msft-ssp.adnxs.com/ut/v3
```

Bidder identity syncs issued alongside it:

```
https://eb2.3lift.com/getuid?redir=https://ib.adnxs.com/prebid/setuid?bidder=triplelift…
https://eb2.3lift.com/sync?px=1
```

Telemetry attached to the auction framing distinguishes primary from backfill fills:

- `adProvider` — value prefixed `BF_` marks a backfill provider
- `BidWinner` / `WinBidCPM_0` vs `BidSweeper` / `WinBidCPM_BF_0`
- `AdVAPrimaryOutcome` / `AdVABackfillOutcome`
- `AdLoadReason` — `LoadFocused`, `loadInFocusedPivot`, `loadInOtherPivot`, `loadOnHeader`, `loadInItemView`, `loadInEmptyPivot`

Placements are selected per surface, e.g. `FocusPC`, `InboxPC`, `OtherPC`, `SubFolderPC`, `HeaderPC`, `TopFloatingInboxPC`, `MidFloatingInboxPC`.

### Render gate

The list row renders only when a client store holds at least one ad id — the component returns `null` otherwise. In the served module the guard reads, in substance:

```
let o = store().adIds.length;
return props.loadOnHeader || o ? <ad row> : null;
```

Because the store is filled from the auction response (and its backfill path), blocking hosts stops *who* fills it, not *whether* the slot exists.

## 2. Display / creative ads (Microsoft Audience Network, "Iris")

The same build carries a selection URL used for creative ads:

```
https://arc.msn.com/v4/api/selection?placement={0}&country={1}&locale={2}&nct=1{3}
                                    &asid={4}&outlookpremiumstatus={5}&userType={6}&tenantId={7}
```

`outlookpremiumstatus` is computed client-side from the account, and the service decides entitlement — free accounts receive ads, subscribed accounts do not.

## 3. Configuration surface

The `Upsell` config section, cached in the profile, carries the click-through targets used by ad and upsell surfaces:

| Key | Value |
|---|---|
| `nativeAdDefaultAdUrl` | `https://go.microsoft.com/fwlink/?linkid=2222260` |
| `adBlockerUpsellUrl` | `https://go.microsoft.com/fwlink/?linkid=2222646` |
| `adFreeOnNativeAdUrl` | `https://go.microsoft.com/fwlink/?linkid=2192065` |
| `euAdPromptUrl` | `https://go.microsoft.com/fwlink/?linkid=2222558` |

These are navigation targets, not ad payloads — blackholing them removes nothing.

## 4. Kill switches exist, but are server-side

The client ships a flight registry (a description table of every known flight) containing:

| Flight | Registry description |
|---|---|
| `ads-shutdown-nativeAds` | kill switch flight to shut down native ads under urgent situation |
| `ads-shutdown-displayAds` | kill switch flight to shut down display ads under urgent situation |
| `ads-hideDisplayAds` | ECS Monarch only flag. Hide display ads on Monarch |
| `ads-hideAds-accountError` | ECS Monarch only flag. Hide ads when Monarch has the account error |
| `ads-showlocaloptoutoption` | ECS Monarch Cloud Cache account only flag |

The registry is a *catalogue*; the ad code never reads these names. Flipping them locally therefore cannot change behaviour — they are evaluated server-side (ECS).

## 5. Where the payload arrives

With `arc.msn.com` and the entire `msft-ssp.adnxs.com` / `*.adnxs.com` set pointed at `0.0.0.0`, a freshly launched client still rendered an `Ad` row with Microsoft's own promo copy.

At the same time the OS DNS cache contained only those blackholed names — and no mail-service hostnames at all, which indicates the app resolves its primary traffic through its own (encrypted) resolver rather than the system one.

Conclusion: for a free account the creative arrives in-band from Microsoft's service. There is no remaining third-party hop to cut, and no hosts entry that removes the slot.
