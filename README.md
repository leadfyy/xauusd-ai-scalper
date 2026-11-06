# XAUUSD Trend Rider 1.20

Native MetaTrader 5 Expert Advisor for XAUUSD and broker-specific gold symbols.

## Strategy concept

This is a rule-based trend-following research build, not an AI prediction model and not a proven profitable system.

- H1: EMA 50/200 alignment defines the primary trend.
- M15: EMA 50/200 alignment plus ADX(14) and +DI/-DI confirm trend direction and strength.
- M5: waits for a pullback toward EMA 20, then a completed candle to reclaim/reject the EMA with RSI confirmation.
- Exit: initial stop is 2.2 × M5 ATR. There is no fixed take-profit; after price moves 1.5 × ATR in favor, an ATR trailing stop activates to attempt to capture larger moves.
- Spread filter: blocks entries above the configured ceiling.

Signals are evaluated only after a completed M5 candle. The trailing stop is managed on incoming ticks.

## Safety and risk controls

Orders are OFF by default. The EA can submit orders only when:
1. InpEnableDemoTrading=true; and
2. the connected account is a DEMO account.

The EA blocks order execution on non-demo accounts. Keep execution disabled on a normal chart. In Strategy Tester, enabling the input creates simulated tester trades; it does not send orders to the connected account.

| Input | Default |
|---|---:|
| InpEnableDemoTrading | false |
| InpRiskPerTradePct | 0.25% |
| InpMaxDailyLossPct | 1.5% |
| InpMaxTradesPerDay | 2 |
| InpInitialStopATR | 2.2 |
| InpTrailStartATR | 1.5 |
| InpTrailDistanceATR | 2.0 |
| InpMaxSpreadPoints | 80 |
| InpMagicNumber | 26110602 |

Position size is calculated with OrderCalcProfit and rounded DOWN to the broker's volume step. If the safe volume is below minimum lot, the trade is skipped. The EA allows one open position per symbol/magic number. It does not use martingale, grid, or averaging down.

The daily loss lock blocks new entries; it does not forcibly close an open position. Stop-loss orders cannot guarantee exact exit prices during gaps, slippage, or abnormal execution.

## Install / update

1. Open MetaEditor from MT5 (F4).
2. Open MQL5/Experts/XAUUSD_AI_Scalper.mq5.
3. Replace the old source with the latest file from this repository.
4. Compile with F7 and confirm 0 errors.
5. In Strategy Tester, select XAUUSD and M5 timeframe, real ticks, and a representative historical date range.
6. For a tester run only, set InpEnableDemoTrading=true in the tester Inputs so simulated trades are recorded. This setting does not place live account orders from Strategy Tester.
7. For a chart attachment, leave InpEnableDemoTrading=false.

## Validation protocol

- Test multiple distinct market regimes and date ranges.
- Separate in-sample tuning from out-of-sample validation.
- Include realistic commission, spread, and execution delay where available.
- Review net profit, profit factor, expected payoff, maximum equity drawdown, number of trades, and month-by-month stability.
- Forward-test on demo for several weeks before considering any further step.
- Do not optimize all parameters on the full historical sample and treat the same sample as proof.

No profitability is claimed or guaranteed. XAUUSD is volatile; leverage, spread, slippage, gaps, and broker execution can materially change results.
