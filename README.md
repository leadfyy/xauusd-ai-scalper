# XAUUSD AI Scalper

Native MetaTrader 5 Expert Advisor for XAUUSD and broker-specific gold symbols.

## Version 1.10: multi-timeframe trend-filtered research build

The entry logic now requires several conditions on **completed candles**:
- M1 EMA 9/21 crossover and RSI 14 confirmation;
- M5 EMA 50/200 trend alignment;
- M15 EMA 50/200 trend alignment in the same direction;
- M5 ADX 14 at or above the configured minimum (default 20);
- spread below the configured ceiling.

This is a trend-alignment filter intended to avoid taking every M1 crossover against the broader intraday trend. It may reduce the number of trades; it is a hypothesis to test, not a proven profitable edge.

## Execution and safety

Orders are OFF by default. The EA can submit orders only when:
1. `InpEnableDemoTrading=true`; and
2. the connected account is a **DEMO** account.

The code blocks order execution on non-demo accounts. Keep execution disabled on the live chart. In Strategy Tester, enabling the input runs simulated tester trades, not orders on the connected account.

## Risk controls

| Input | Default | Purpose |
|---|---:|---|
| InpEnableDemoTrading | false | Master execution switch |
| InpRiskPerTradePct | 0.25 | Equity risk budget per trade; maximum accepted input 1% |
| InpMaxDailyLossPct | 2.0 | Blocks new entries after EA daily P/L reaches this threshold; maximum accepted input 5% |
| InpMaxTradesPerDay | 3 | Maximum EA entries per broker day |
| InpATRStopMultiplier | 1.5 | ATR-based stop distance |
| InpRewardRiskRatio | 1.5 | Target distance relative to stop |
| InpMaxSpreadPoints | 80 | Spread ceiling; validate against broker conditions |
| InpMinADX | 20 | Minimum M5 ADX for trend-strength filter |
| InpTrendFastEMA / SlowEMA | 50 / 200 | M5 and M15 trend direction |
| InpMagicNumber | 26110601 | Identifies this EA's positions and deals |

Volume is calculated using `OrderCalcProfit` and rounded DOWN to the broker's volume step. If the safe size is below minimum lot, the trade is skipped. The EA permits one open position per symbol/magic number and does not use martingale, grid, or averaging down.

The daily loss lock blocks new entries; it does not forcibly close an open position. Stop-loss orders do not guarantee exact exit prices during gaps or abnormal execution.

## Install / update

1. Open MetaEditor with F4.
2. Open `MQL5/Experts/XAUUSD_AI_Scalper.mq5`.
3. Replace the old source with the latest version from this repository.
4. Compile with F7 and confirm **0 errors**.
5. In MT5, refresh Expert Advisors in Navigator and attach the EA to XAUUSD M1.

Repository: https://github.com/leadfyy/xauusd-ai-scalper

## Validation protocol

1. Backtest on real ticks with realistic/random execution delay and commission where available.
2. Use separate in-sample and out-of-sample date ranges; do not optimize on the entire history and report that as validation.
3. Check profit factor, expected payoff, max equity drawdown, number of trades, and stability by month.
4. Forward-test on a demo account for several weeks after the historical tests.
5. Do not move to live trading based only on one backtest or a high net-profit figure.

This is a rule-based technical strategy, not an AI prediction model. No profitability is claimed or guaranteed. XAUUSD scalping carries substantial execution, leverage, spread, slippage, and market-gap risk.
