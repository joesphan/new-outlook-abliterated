# new-outlook-abliterated

Reverse-engineering notes and tooling for **ad suppression in the new Outlook for Windows** (`olk.exe`, MSIX `Microsoft.OutlookForWindows`).

Findings from a hands-on session against:

| Component | Version |
|---|---|
| Outlook for Windows (new) | `1.2026.1020.100` |
| WebView2 runtime | `156.0.4314.58` |
| WebView2 user-data folder | `%LOCALAPPDATA%\Microsoft\Olk\EBWebView` |
| Main OWA ad module | `owa.55698.m.bc69244b.js` |

## What this repo actually does

| Capability | Status |
|---|---|
| Stop third-party ad creatives and bidder/tracking calls in the desktop app | **Works** — `tools/Block-OutlookAdHosts.ps1` |
| Show which ad hosts the app attempted, and prove the block bit | **Works** — `tools/Test-OutlookAdHosts.ps1` |
| Reproduce the visual verification loop | **Works** — `tools/Capture-OutlookWindow.ps1` |
| Remove the `Ad`-labelled row from the message list entirely | **Does not work client-side.** See [docs/dead-ends.md](docs/dead-ends.md) |

Be clear about the ceiling before you install anything: **the in-list row is a product surface of the free tier, not a creative fetched from a host you can block.** With every known ad endpoint blackholed, the row still renders with Microsoft's own `Upgrade Your Account` promo. Removing that requires a Microsoft 365 subscription (server-side), classic Outlook, or a browser client where a content blocker can hide the DOM node.

This repo does not remove it, and does not pretend to.

## What it does improve

Blocking the SSP/auction chain measurably changes behaviour. Verified sequence on a live mailbox:

1. Baseline: rows served real third-party inventory — Airbnb, an eBay listing, an AARP job ad — each with bidder sync traffic.
2. After blackholing the Xandr / Microsoft SSP hosts and a cold cache: bidder traffic gone, rows fall back to Microsoft's own upsell only.

That is a real reduction in who receives ad requests and device identifiers, even though the slot itself remains.

## Install

```powershell
# from an elevated PowerShell (the hosts file is Administrators-only)
.\tools\Block-OutlookAdHosts.ps1

# verify: every blocked name must resolve to 0.0.0.0
.\tools\Test-OutlookAdHosts.ps1

# restart Outlook so it re-resolves
```

The script backs up `hosts` to `%TEMP%\hosts.bak-<timestamp>` before touching it, writes an idempotent marked block, and never rewrites unrelated lines.

Revert:

```powershell
.\tools\Block-OutlookAdHosts.ps1 -Remove
ipconfig /flushdns
```

## Contents

- [docs/ad-architecture.md](docs/ad-architecture.md) — how the ads are delivered, with the evidence that pinned each hop
- [docs/dead-ends.md](docs/dead-ends.md) — four approaches that do not work, and exactly why
- [docs/verification.md](docs/verification.md) — the reproducible loop used to prove each claim
- `tools/` — hosts installer, resolver test, window capture helper

## Legal

No Microsoft code is contained in or redistributed by this repository. Everything here is observational: network endpoints, configuration keys, and behaviour reached through the app's own public web surface. `olk.exe` itself is a signed, ACL-protected package and is neither modified nor shipped.

Decompiling and republishing that client would be copyright infringement; this project deliberately does not.

## License

MIT for the contents of this repository — see [LICENSE](LICENSE).
