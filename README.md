# XAUUSD AI Scalper

Native MetaTrader 5 Expert Advisor for XAUUSD and broker-specific gold symbols.

## Current build: guarded demo execution (orders OFF by default)

The EA evaluates completed M1 candles using:
- EMA 9 / EMA 21 crossover;
- RSI 14 confirmation;
- maximum spread filter;
- ATR 14 for volatility-adjusted stop distance.

The EA can submit orders only when **both** conditions are true:
1. `InpEnableDemoTrading=true` in the EA inputs; and
2. the connected MT5 account is a **DEMO** account.

A non-demo account is blocked in code. The default is `InpEnableDemoTrading=false`, so the EA starts in signal-only mode.

## Safety controls and defaults

| Input | Default | Purpose |
|---|---:|---|
| InpEnableDemoTrading | false | Master execution switch; OFF by default |
| InpRiskPerTradePct | 0.25 | Equity risk budget per trade; maximum accepted input is 1% |
| InpMaxDailyLossPct | 2.0 | Blocks new entries after EA daily P/L reaches this loss threshold; maximum accepted input is 5% |
| InpMaxTradesPerDay | 3 | Maximum EA entries per broker day |
| InpATRStopMultiplier | 1.5 | ATR-based minimum stop distance |
| InpRewardRiskRatio | 1.5 | Take-profit distance relative to stop distance |
| InpMaxSpreadPoints | 80 | Spread ceiling; must be validated for the broker |
| InpDeviationPoints | 30 | Maximum price deviation requested |
| InpMagicNumber | 26110601 | Identifies this EA's positions and deals |

Position size is calculated from equity, the configured risk percentage, and the estimated loss at the stop price using `OrderCalcProfit`. If the calculated volume is below the broker's minimum lot, the EA skips the trade rather than rounding volume up and exceeding the risk budget.

The EA allows only one open position per symbol/magic number. It does not average down, martingale, grid, or increase position size after losses. Stop Loss and Take Profit are sent with the entry request. The daily loss lock blocks new entries; it does not forcibly close an existing position.

## Install / update

1. In MT5, open MetaEditor with F4.
2. Open `MQL5/Experts/XAUUSD_AI_Scalper.mq5`.
3. Replace its contents with the latest file from this repository, or download the file and overwrite the old copy in the MT5 data folder's `MQL5/Experts` directory.
4. Compile with F7 and confirm **0 errors**.
5. In MT5, right-click Expert Advisors in Navigator and choose Refresh.
6. Attach the EA to the broker's XAUUSD M1 chart.

## Safe first run

- Keep Algo Trading OFF and leave `InpEnableDemoTrading=false` for the first compile and visual check.
- Verify the account is the intended demo account, the chart symbol is the broker's gold instrument, and the spread ceiling is sensible for that symbol.
- Only after a successful compile and review of the broker's symbol properties should demo order execution be considered. If enabled, it remains code-blocked on non-demo accounts.
- Do not use this EA on a live account. Do not treat backtests or demo results as evidence of future profitability.

## Important limitations

This is a rule-based technical strategy, not a machine-learning model and not a prediction system. It evaluates a signal once per newly closed M1 candle. No profitability is claimed. The ATR stop, spread ceiling, tick value, contract size, commission, slippage, broker execution and market gaps all affect actual risk. A stop loss does not guarantee the exact exit price during gaps or abnormal execution.

Before any live deployment (not recommended), the strategy would require robust historical tick backtesting, out-of-sample testing, forward demo testing, and independent risk review.
