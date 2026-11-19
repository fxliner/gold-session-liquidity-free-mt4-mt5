# Gold Session Liquidity Free MT4 v1.10

**FXLINER — Free educational XAUUSD analysis indicator for MetaTrader 4**

This standalone MQL4 indicator provides historical session context and manually configurable risk planning. It does not send orders or claim a profitable strategy.

## Features

- **Completed Asian High / Low:** completed range from an explicit UTC window, using historical broker UTC offset (winter setting and optional EU DST).
- **Liquidity sweep markers:** a confirmed swing high or swing low is briefly pierced, then price closes back through that level. The event is inferred from OHLC candles and does not use a live order book.
- **Confirmed structure breaks:** breaks above/below confirmed swing pivots, based on closed candles.
- **Session intelligence:** Asia, London, New York and overlap using UTC clocks and European/US DST estimates.
- **Dashboard:** session, UTC time, H1 EMA 20/50 direction, spread in broker points, Asian range, latest sweep and structure break.
- **Manual lot risk planner:** planned equity risk, entry and stop, broker tick value/tick size, lot minimum/step, assumed round-trip commission and optional price R:R.
- **Free analysis build:** no BUY/SELL trading signals, automated order functions or guaranteed profit features.

## Installation

Extract `Gold_Session_Liquidity_Free_MT4.mq4` into `MQL4/Indicators/GoldSessionLiquidityFree/` of your MetaTrader 4 Data Folder, open MetaEditor and compile (F7). Or install the compiled `.ex4` in that folder. Refresh MT4 Navigator, then add it to XAUUSD M5 or M15.

Default broker server time is UTC+2 in winter and UTC+3 in summer according to EU DST, but **you must verify the actual broker clock**. The indicator can initialize on other symbols and chart periods; visibility and usefulness of Asian-range markers depend on available intraday data.

## Inputs

- `BrokerWinterUTCOffset=2`, `BrokerEUDST=true`: historical server time conversion.
- `AsianStartUTC=0`, `AsianEndUTC=6`: completed range window [00:00,06:00).
- `SwingStrength=3`, `MaxSwingAge=90`, `MaxBarsToScan=900`: bounded pivot detection, freshness and display history.
- `ShowLiquiditySweeps=true`, `ShowStructureBreaks=true`: independent chart overlays.
- `TrendFastEMA=20`, `TrendSlowEMA=50`: informational H1 trend direction, never a guarantee of trade direction.
- `RiskBudgetPercent=0.50`: example planned equity risk budget.
- `ManualEntryPrice`, `ManualStopPrice`, `ManualTargetPrice`: manual hypothetical trade planning; left at zero until supplied.
- `CommissionRoundTrip=7.00`: example commission in account currency per 1.00 lot, both sides combined. Replace with broker actual.
- `EducationalPopup=false`: optional informational event notice, not a trading alert.

The lot planner uses MQL4 `MarketInfo(MODE_TICKVALUE)` and `MarketInfo(MODE_TICKSIZE)`, rounded **down** to the broker's lot step. Calculation assumes accurate broker contract properties. If minimum lot exceeds risk budget, it declines to recommend a lot.

**Warning:** a planned stop budget is not a maximum actual loss. Spreads, slippage, weekends and gaps can cause greater losses. The dashboard does not estimate real execution costs or position margin availability.

## Buffer map

0 Completed Asian High; 1 Completed Asian Low; 2 Low sweep; 3 High sweep; 4 Confirmed swing break up; 5 Confirmed swing break down.

All sweep/break events are computed from completed candles only. The unfinished bar is never used for signal confirmation. Old output disappears after the bounded scan window. Historical feed changes and older-history loading can affect recalculated results.

## Compilation, testing, and limitations

Source compiled in local MetaEditor 4 with **0 errors and 0 warnings**. This is an initial MT4 port, not identical source or buffer mapping to the MT5 edition; MT5 experimental trade signals are intentionally not included here.

No positive out-of-sample trading profitability has been demonstrated for related experimental strategies. Neither the MT4 nor MT5 free edition offers a verified profitable signal system.

The gallery contains **illustrative XAUUSD chart reconstructions from historical MT5 tester data** to explain the patterns; it is not a direct screenshot or performance test of MT4. Actual MT4 output may differ according to broker history and timeframe.

## Project and attribution

**https://forexreview.top/** — project homepage and upcoming dedicated installation guide.

FXLINER / forexreview.top, 2026. The confirmed swing detection logic incorporates MIT-licensed portions derived from Smart Liquidity Hunter v1.11. Preserve the attribution and MIT license included in `THIRD_PARTY_NOTICES.txt` when redistributing source.

Free to use as an educational analytical tool. No auto-trading, no promise of profit.
