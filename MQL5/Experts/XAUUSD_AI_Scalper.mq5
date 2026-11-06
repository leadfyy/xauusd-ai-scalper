//+------------------------------------------------------------------+
//| XAUUSD AI Scalper - guarded demo execution EA                    |
//| Closed M1 candle signals: EMA(9/21) crossover + RSI(14).          |
//| Orders are OFF by default and are blocked on non-demo accounts.  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "XAUUSD M1 EA with demo-only guarded execution; trading disabled by default."

#include <Trade/Trade.mqh>

input int      InpFastEMA              = 9;
input int      InpSlowEMA              = 21;
input int      InpRSIPeriod            = 14;
input int      InpATRPeriod            = 14;
input double   InpMaxSpreadPoints      = 80.0;
input double   InpRSIBuyMin            = 50.0;
input double   InpRSIBuyMax            = 70.0;
input double   InpRSISellMin           = 30.0;
input double   InpRSISellMax           = 50.0;

// Safety controls. Leave execution disabled until the demo setup is verified.
input bool     InpEnableDemoTrading    = false;
input double   InpRiskPerTradePct      = 0.25;
input double   InpMaxDailyLossPct      = 2.0;
input int      InpMaxTradesPerDay      = 3;
input double   InpATRStopMultiplier    = 1.5;
input double   InpRewardRiskRatio      = 1.5;
input ulong    InpMagicNumber          = 26110601;
input int      InpDeviationPoints      = 30;
input bool     InpShowChartComment     = true;

int      g_fastHandle = INVALID_HANDLE;
int      g_slowHandle = INVALID_HANDLE;
int      g_rsiHandle  = INVALID_HANDLE;
int      g_atrHandle  = INVALID_HANDLE;
datetime g_lastClosedBar = 0;
CTrade   g_trade;

enum SignalType
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY_SETUP,
   SIGNAL_SELL_SETUP,
   SIGNAL_SPREAD_BLOCKED,
   SIGNAL_DATA_WAIT
};

string SignalToString(const SignalType signal)
{
   switch(signal)
   {
      case SIGNAL_BUY_SETUP:      return "BUY SETUP";
      case SIGNAL_SELL_SETUP:     return "SELL SETUP";
      case SIGNAL_SPREAD_BLOCKED: return "NO TRADE - SPREAD";
      case SIGNAL_DATA_WAIT:      return "WAITING FOR DATA";
      default:                    return "NO TRADE";
   }
}

bool ReadValue(const int handle,const int buffer,const int shift,double &value)
{
   double data[1];
   if(handle==INVALID_HANDLE || CopyBuffer(handle,buffer,shift,1,data)!=1)
      return false;
   value=data[0];
   return (value!=EMPTY_VALUE);
}

double CurrentSpreadPoints()
{
   MqlTick tick;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0 || !SymbolInfoTick(_Symbol,tick))
      return -1.0;
   return (tick.ask-tick.bid)/point;
}

datetime StartOfBrokerDay()
{
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(),parts);
   parts.hour=0;
   parts.min=0;
   parts.sec=0;
   return StructToTime(parts);
}

void GetDailyStats(double &dailyPnl,int &entryCount)
{
   dailyPnl=0.0;
   entryCount=0;
   datetime now=TimeCurrent();
   if(!HistorySelect(StartOfBrokerDay(),now))
      return;

   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0)
         continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber)
         continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol)
         continue;

      dailyPnl += HistoryDealGetDouble(ticket,DEAL_PROFIT)
                + HistoryDealGetDouble(ticket,DEAL_SWAP)
                + HistoryDealGetDouble(ticket,DEAL_COMMISSION);

      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
         entryCount++;
   }

   for(int p=0;p<PositionsTotal();p++)
   {
      ulong positionTicket=PositionGetTicket(p);
      if(positionTicket==0)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL)==_Symbol)
      {
         dailyPnl += PositionGetDouble(POSITION_PROFIT)
                   + PositionGetDouble(POSITION_SWAP);
      }
   }
}

bool HasOpenEAPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL)==_Symbol)
         return true;
   }
   return false;
}

int VolumeDigits(const double step)
{
   for(int digits=0;digits<=8;digits++)
      if(MathAbs(step-NormalizeDouble(step,digits))<0.00000001)
         return digits;
   return 2;
}

double CalculateRiskVolume(const ENUM_ORDER_TYPE orderType,
                           const double entryPrice,const double stopPrice,
                           string &reason)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney=equity*InpRiskPerTradePct/100.0;
   double oneLotResult=0.0;

   if(riskMoney<=0.0 ||
      !OrderCalcProfit(orderType,_Symbol,1.0,entryPrice,stopPrice,oneLotResult))
   {
      reason="Could not calculate monetary risk for 1 lot.";
      return 0.0;
   }

   double lossPerLot=MathAbs(oneLotResult);
   if(lossPerLot<=0.0)
   {
      reason="Calculated stop-loss risk is invalid.";
      return 0.0;
   }

   double rawVolume=riskMoney/lossPerLot;
   double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(step<=0.0 || minVolume<=0.0 || maxVolume<=0.0)
   {
      reason="Broker volume specification is invalid.";
      return 0.0;
   }

   double volume=MathFloor(rawVolume/step)*step;
   volume=NormalizeDouble(volume,VolumeDigits(step));

   // Never round UP to the broker minimum: that could exceed the risk cap.
   if(volume<minVolume)
   {
      reason=StringFormat("Safe volume %.4f is below broker minimum %.4f; trade skipped.",
                          rawVolume,minVolume);
      return 0.0;
   }

   volume=MathMin(volume,maxVolume);
   return volume;
}

bool IsDemoAccount()
{
   return ((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)
           ==ACCOUNT_TRADE_MODE_DEMO);
}

void TryOpenTrade(const SignalType signal,const double atr)
{
   if(!InpEnableDemoTrading)
   {
      Print("Signal found, but execution is disabled. Set InpEnableDemoTrading=true only after demo checks.");
      return;
   }
   if(!IsDemoAccount())
   {
      Print("SAFETY BLOCK: this EA can send orders on DEMO accounts only.");
      return;
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Print("Trading permission is disabled in MT5 or EA settings.");
      return;
   }
   if(HasOpenEAPosition())
   {
      Print("Entry skipped: this EA already has an open position on ",_Symbol,".");
      return;
   }

   double dailyPnl=0.0;
   int tradesToday=0;
   GetDailyStats(dailyPnl,tradesToday);
   double dailyLossLimit=AccountInfoDouble(ACCOUNT_BALANCE)*InpMaxDailyLossPct/100.0;

   if(dailyPnl<=-dailyLossLimit)
   {
      Print("DAILY LOSS LOCK: daily P/L ",DoubleToString(dailyPnl,2),
            " reached limit -",DoubleToString(dailyLossLimit,2),". No new entries.");
      return;
   }
   if(tradesToday>=InpMaxTradesPerDay)
   {
      Print("Daily trade-count limit reached: ",tradesToday);
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
   {
      Print("Entry skipped: no current market tick.");
      return;
   }

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   if(point<=0.0 || atr<=0.0)
   {
      Print("Entry skipped: invalid point size or ATR.");
      return;
   }

   double stopDistance=MathMax(atr*InpATRStopMultiplier,(stopsLevel+2)*point);
   double entry=0.0,sl=0.0,tp=0.0;
   ENUM_ORDER_TYPE orderType;

   if(signal==SIGNAL_BUY_SETUP)
   {
      orderType=ORDER_TYPE_BUY;
      entry=tick.ask;
      sl=NormalizeDouble(entry-stopDistance,digits);
      tp=NormalizeDouble(entry+stopDistance*InpRewardRiskRatio,digits);
   }
   else if(signal==SIGNAL_SELL_SETUP)
   {
      orderType=ORDER_TYPE_SELL;
      entry=tick.bid;
      sl=NormalizeDouble(entry+stopDistance,digits);
      tp=NormalizeDouble(entry-stopDistance*InpRewardRiskRatio,digits);
   }
   else
      return;

   string volumeReason="";
   double volume=CalculateRiskVolume(orderType,entry,sl,volumeReason);
   if(volume<=0.0)
   {
      Print("Entry skipped: ",volumeReason);
      return;
   }

   bool sent=false;
   if(orderType==ORDER_TYPE_BUY)
      sent=g_trade.Buy(volume,_Symbol,0.0,sl,tp,"XAUUSD AI Scalper demo BUY");
   else
      sent=g_trade.Sell(volume,_Symbol,0.0,sl,tp,"XAUUSD AI Scalper demo SELL");

   if(!sent)
   {
      Print("Order request failed. Retcode=",g_trade.ResultRetcode(),
            " ",g_trade.ResultRetcodeDescription());
      return;
   }

   Print("DEMO ORDER REQUEST: ",EnumToString(orderType),
         " volume=",DoubleToString(volume,VolumeDigits(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))),
         " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
         " retcode=",g_trade.ResultRetcode()," ",g_trade.ResultRetcodeDescription());
}

void PublishStatus(const SignalType signal,const string reason,
                   const double fastEMA,const double slowEMA,
                   const double rsi,const double spread,const double atr)
{
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPnl=0.0;
   int tradesToday=0;
   GetDailyStats(dailyPnl,tradesToday);

   string mode="SIGNAL ONLY (execution OFF)";
   if(InpEnableDemoTrading)
      mode=(IsDemoAccount() ? "DEMO EXECUTION ARMED" : "LIVE ACCOUNT BLOCKED");

   if(InpShowChartComment)
   {
      Comment(
         "XAUUSD AI SCALPER 1.00\n",
         "MODE: ",mode,"\n",
         "Symbol: ",_Symbol,"  Signal timeframe: M1\n",
         "Signal: ",SignalToString(signal),"\n",
         "Reason: ",reason,"\n",
         "EMA ",InpFastEMA,": ",DoubleToString(fastEMA,_Digits),
         " | EMA ",InpSlowEMA,": ",DoubleToString(slowEMA,_Digits),"\n",
         "RSI(",InpRSIPeriod,"): ",DoubleToString(rsi,2),
         " | ATR(",InpATRPeriod,"): ",DoubleToString(atr,_Digits),"\n",
         "Spread: ",DoubleToString(spread,1)," points\n",
         "Balance: ",DoubleToString(balance,2)," ",currency,
         " | Equity: ",DoubleToString(equity,2)," ",currency,"\n",
         "EA daily P/L: ",DoubleToString(dailyPnl,2)," ",currency,
         " | Entries today: ",tradesToday,"/",InpMaxTradesPerDay,"\n",
         "Risk/trade: ",DoubleToString(InpRiskPerTradePct,2),
         "% | Daily loss cap: ",DoubleToString(InpMaxDailyLossPct,2),"%"
      );
   }

   Print(_Symbol," | ",SignalToString(signal)," | ",reason,
         " | spread=",DoubleToString(spread,1),
         " | RSI=",DoubleToString(rsi,2),
         " | ATR=",DoubleToString(atr,_Digits));
}

int OnInit()
{
   if(InpFastEMA<=0 || InpSlowEMA<=0 || InpRSIPeriod<=0 || InpATRPeriod<=0 ||
      InpFastEMA>=InpSlowEMA || InpMaxSpreadPoints<=0.0 ||
      InpRiskPerTradePct<=0.0 || InpRiskPerTradePct>1.0 ||
      InpMaxDailyLossPct<=0.0 || InpMaxDailyLossPct>5.0 ||
      InpMaxTradesPerDay<1 || InpATRStopMultiplier<=0.0 ||
      InpRewardRiskRatio<=0.0)
   {
      Print("Invalid inputs. Risk/trade must be >0 and <=1%; daily loss cap >0 and <=5%.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_fastHandle=iMA(_Symbol,PERIOD_M1,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowHandle=iMA(_Symbol,PERIOD_M1,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_rsiHandle=iRSI(_Symbol,PERIOD_M1,InpRSIPeriod,PRICE_CLOSE);
   g_atrHandle=iATR(_Symbol,PERIOD_M1,InpATRPeriod);

   if(g_fastHandle==INVALID_HANDLE || g_slowHandle==INVALID_HANDLE ||
      g_rsiHandle==INVALID_HANDLE || g_atrHandle==INVALID_HANDLE)
   {
      Print("Failed to create indicator handles. Error=",GetLastError());
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   Print("Initialized on ",_Symbol,". Execution input=",InpEnableDemoTrading,
         ". Demo-account-only order guard is active.");
   Print("Account mode=",EnumToString((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)),
         " | Balance=",DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)," ",
         AccountInfoString(ACCOUNT_CURRENCY));
   if(InpEnableDemoTrading && !IsDemoAccount())
      Print("SAFETY BLOCK: execution requested, but account is not DEMO.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fastHandle!=INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle!=INVALID_HANDLE) IndicatorRelease(g_slowHandle);
   if(g_rsiHandle!=INVALID_HANDLE)  IndicatorRelease(g_rsiHandle);
   if(g_atrHandle!=INVALID_HANDLE)  IndicatorRelease(g_atrHandle);
   Comment("");
}

void OnTick()
{
   datetime closedBarTime=iTime(_Symbol,PERIOD_M1,1);
   if(closedBarTime<=0 || closedBarTime==g_lastClosedBar)
      return;
   g_lastClosedBar=closedBarTime;

   double fastCurrent,fastPrevious,slowCurrent,slowPrevious,rsiCurrent,atrCurrent;
   if(!ReadValue(g_fastHandle,0,1,fastCurrent) ||
      !ReadValue(g_fastHandle,0,2,fastPrevious) ||
      !ReadValue(g_slowHandle,0,1,slowCurrent) ||
      !ReadValue(g_slowHandle,0,2,slowPrevious) ||
      !ReadValue(g_rsiHandle,0,1,rsiCurrent) ||
      !ReadValue(g_atrHandle,0,1,atrCurrent))
   {
      PublishStatus(SIGNAL_DATA_WAIT,"Indicator buffers are not ready.",0,0,0,
                    CurrentSpreadPoints(),0);
      return;
   }

   double spread=CurrentSpreadPoints();
   if(spread<0.0)
   {
      PublishStatus(SIGNAL_DATA_WAIT,"No valid tick is available.",fastCurrent,
                    slowCurrent,rsiCurrent,spread,atrCurrent);
      return;
   }

   SignalType signal=SIGNAL_NONE;
   string reason="No complete EMA crossover plus RSI confirmation.";

   if(spread>InpMaxSpreadPoints)
   {
      signal=SIGNAL_SPREAD_BLOCKED;
      reason=StringFormat("Spread %.1f exceeds configured ceiling %.1f points.",
                          spread,InpMaxSpreadPoints);
   }
   else
   {
      bool bullishCross=(fastPrevious<=slowPrevious && fastCurrent>slowCurrent);
      bool bearishCross=(fastPrevious>=slowPrevious && fastCurrent<slowCurrent);

      if(bullishCross && rsiCurrent>=InpRSIBuyMin && rsiCurrent<=InpRSIBuyMax)
      {
         signal=SIGNAL_BUY_SETUP;
         reason="Closed-bar bullish EMA crossover with RSI confirmation.";
      }
      else if(bearishCross && rsiCurrent>=InpRSISellMin && rsiCurrent<=InpRSISellMax)
      {
         signal=SIGNAL_SELL_SETUP;
         reason="Closed-bar bearish EMA crossover with RSI confirmation.";
      }
   }

   PublishStatus(signal,reason,fastCurrent,slowCurrent,rsiCurrent,spread,atrCurrent);
   if(signal==SIGNAL_BUY_SETUP || signal==SIGNAL_SELL_SETUP)
      TryOpenTrade(signal,atrCurrent);
}
//+------------------------------------------------------------------+
