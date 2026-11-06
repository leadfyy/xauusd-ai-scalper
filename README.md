# XAUUSD AI Scalper

Native MetaTrader 5 Expert Advisor project for XAUUSD / broker-suffixed gold symbols.

## Current stage: research EA (no order execution)

This first commit is deliberately **signal-only**. It:
- discovers the chart symbol (attach it to the broker's gold chart, e.g. `XAUUSDn`);
- reads live ticks and closed M1 candles;
- calculates EMA 9 / EMA 21 and RSI 14;
- evaluates a candidate signal once per newly closed M1 candle;
- rejects signals when the spread exceeds the configured limit;
- displays account balance/equity and writes signal details to the Experts log.

It does **not** send, modify, or close orders. No profitability is claimed.

## Install

1. Open MetaTrader 5.
2. Press `F4` to open MetaEditor.
3. In MetaEditor, create/open an Expert Advisor under `MQL5/Experts`.
4. Copy `MQL5/Experts/XAUUSD_AI_Scalper.mq5` into that folder (or open it from the repository's local clone).
5. Compile with F7.
6. In MT5, open the broker's gold chart (for example `XAUUSDn`), select M1, and attach the EA.
7. Keep Algo Trading disabled for this signal-only build; enable only chart updates/EA permissions as required by MT5.

## Initial configuration

| Input | Default | Meaning |
|---|---:|---|
| InpFastEMA | 9 | Fast EMA period |
| InpSlowEMA | 21 | Slow EMA period |
| InpRSIPeriod | 14 | RSI period |
| InpMaxSpreadPoints | 80 | Placeholder spread ceiling; calibrate to broker |
| InpRSIBuyMin / Max | 50 / 70 | RSI confirmation range for BUY setup |
| InpRSISellMin / Max | 30 / 50 | RSI confirmation range for SELL setup |

The EA reads the actual account balance and currency from MT5. The intended demo balance is **3,000 USD**, but the program never edits or assumes the account balance.

## Roadmap

1. Validate broker's exact symbol specification (digits, point, tick size/value, contract size, volume min/step/max, spread, commission).
2. Collect and test tick data with realistic spread, commission, slippage and execution assumptions.
3. Add a demo-only execution module with strict sizing, SL/TP, max daily loss, max positions and kill switch.
4. Add optional dashboard/reporting.
5. Consider any live trading only after robust out-of-sample validation.

## Risk note

Gold scalping has substantial execution and leverage risk. A 3,000 USD demo balance is not a reason to use high risk. Backtests and demo results do not guarantee future performance.
