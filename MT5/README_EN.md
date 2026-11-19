# Gold Session Liquidity Free MT5 v1.10

**FXLINER — Free XAUUSD analysis indicator, not an Expert Advisor**

## What it does
- Completed Asian session high/low and London/New York session intelligence with EU/US DST logic and configurable historical broker UTC offset.
- Closed-candle swing-liquidity sweep markers and confirmed swing structure-break markers.
- H1 EMA trend, broker spread context, recent market events and readable dark dashboard.
- Manual risk-budget and lot-size planner powered by MT5 `OrderCalcProfit`, account equity, symbol minimum/step volume and estimated round-trip commission.

**Experimental BUY/SELL arrows are OFF by default** because the underlying trading ideas have not demonstrated reliable profitability out of sample. The free version is an analysis and risk-planning tool, not a signal-service claim.

## Installation
Copy `Gold_Session_Liquidity_Free_MT5.ex5` into `MQL5/Indicators/GoldSessionLiquidityFree` in the MT5 *Data Folder*, refresh Navigator and attach it to an XAUUSD M5 or M15 chart. Check your broker's historical server offset and daylight-saving clock settings: UTC+2 winter/UTC+3 summer is only a common default.

## Manual risk planner
Set `RiskBudgetPercent` (for example, 0.50), `ManualEntryPrice`, `ManualStopPrice` and optionally `ManualTargetPrice`. The tool estimates a lot size by rounding DOWN to the broker volume step without exceeding the planned nominal stop-loss budget. `CommissionPerLotRoundTrip` must reflect your broker and account currency. This does not include guaranteed fills, swap, funding, spread changes, gaps or slippage.

## Buffer map
0–1: optional research BUY/SELL (empty by default); 2–3: completed Asian High/Low; 4–11: research SL/TP (empty by default); 12: heuristic score (not win probability; empty by default); 13: low sweep; 14: high sweep; 15: confirmed up swing break; 16: down swing break.

## Quality checks
MetaEditor compiled the indicator with **0 errors, 0 warnings**. MetaQuotes-Demo Strategy Tester M15 (Aug–Oct 2026) and M5 (Sep–Oct 2026) produced **1,145,655 historical marker comparisons**, **0 observed mutations**, and **0 CopyBuffer errors** inside the test's bounded history. These do not verify profitability or live fills.

## License and attribution
This work includes MIT-licensed logic derived from Smart Liquidity Hunter v1.11. See `THIRD_PARTY_NOTICES.txt`. Retain the copyright and license notice when distributing relevant source or copies. These files are staged for free distribution and have not been publicly published.

**For educational use. Stops do not guarantee maximum loss. No performance guarantees.**
