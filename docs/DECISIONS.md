# Decisions

## D-001 — Read through the official CLI
**Status:** accepted

MRRadar reads RevenueCat through `rc`, using `rc api GET` for what `rc charts` can't ask (resolution, segments). `rc` does the OAuth sign-in and token refresh, so MRRadar never holds a token. A secret key, for people who prefer one, stays in the Keychain and reaches `rc` through `RC_API_KEY`, never its arguments.

## D-002 — Read-only
**Status:** accepted

`rc` can refund, grant and cancel, but MRRadar's source protocol only has GET. The app is for looking, so a mistake can't cost anyone money.

## D-003 — One engine, the app or the hub
**Status:** accepted

The app runs the engine and hub in process. Without it, Remote Code starts `mrradar-hub`. The app asks a running hub to yield, so two engines don't share RevenueCat's limit or raise an alert twice. Reports and fired alert ids are on disk, so the one that takes over carries on.

## D-004 — Currencies are never added
**Status:** accepted

Projects can report in different currencies. Totals are per currency, because a conversion rate would add a number nobody asked for.

## D-005 — Forecasts stay simple
**Status:** accepted

The forecast is a least-squares line through 60 days. It says what the recent trend implies, and the app labels it as a trend. A fancier model would look more certain than the data of a small app allows.
