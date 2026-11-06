//+------------------------------------------------------------------+
/*| XAUUSD AI Scalper - signal-only research EA
  | Version: 0.1.0
  | IMPORTANT: This build NEVER sends trade orders.
  | Attach to the broker's gold chart (e.g. XAUUSDn), timeframe M1.
  +------------------------------------------------------------------+*/
#property strict
#property version   "0.100"
#property description "Signal-only XAUUSD scalping research EA. No orders are sent."

input int      InpFastEMA          = 9;
input int      InpSlowEMA          = 21;
input int      InpRSIPeriod        = 14;
input double   InpMaxSpreadPoints  = 80.0;  // Placeholder; calibrate per broker.
input double   InpRSIBuyMin        = 50.0;
input double   InpRSIBuyMax        = 70.0;
input double   InpRSISellMin       = 30.0;
input double   InpRSISellMax       = 50.0;
input bool     InpShowChartComment = true;

int      g_fastHandle = INVALID_HANDLE;
int      g_slowHandle = INVALID_HANDLE;
int      g_rsiHandle  = INVALID_HANDLE;
datetime g_lastClosedBar = 0;

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
      case SIGNAL_BUY_SETUP:     return "BUY SETUP";
      case SIGNAL_SELL_SETUP:    return "SELL SETUP";
      case SIGNAL_SPREAD_BLOCKED:return "NO TRADE - SPREAD";
      case SIGNAL_DATA_WAIT:     return "WAITING FOR DATA";
      default:                   return "NO TRADE";
   }
}

bool ReadValue(const int handle,const int buffer,const int shift,double &value)
{
   double data[1];
   if(handle==INVALID_HANDLE)
      return false;
   if(CopyBuffer(handle,buffer,shift,1,data)!=1)
      return false;
   value=data[0];
   return (value!=EMPTY_VALUE);
}

double CurrentSpreadPoints()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return -1.0;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)
      return -1.0;
   return (tick.ask-tick.bid)/point;
}

void PublishStatus(const SignalType signal,const string reason,
                   const double fastEMA,const double slowEMA,
                   const double rsi,const double spread)
{
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   string message=StringFormat(
      "XAUUSD AI Scalper | %s | %s | EMA%d=%.5f EMA%d=%.5f RSI=%.2f Spread=%.1f pts | Balance=%.2f %s Equity=%.2f %s",
      _Symbol,SignalToString(signal),InpFastEMA,fastEMA,InpSlowEMA,slowEMA,
      rsi,spread,balance,currency,equity,currency
   );
   Print(message," | ",reason);

   if(InpShowChartComment)
   {
      Comment(
         "XAUUSD AI SCALPER 0.1.0\n",
         "MODE: SIGNAL ONLY - NO ORDERS\n",
         "Symbol: ",_Symbol,"  TF: M1\n",
         "Signal: ",SignalToString(signal),"\n",
         "Reason: ",reason,"\n",
         "EMA ",InpFastEMA,": ",DoubleToString(fastEMA,_Digits),"\n",
         "EMA ",InpSlowEMA,": ",DoubleToString(slowEMA,_Digits),"\n",
         "RSI(",InpRSIPeriod,"): ",DoubleToString(rsi,2),"\n",
         "Spread: ",DoubleToString(spread,1)," points\n",
         "Balance: ",DoubleToString(balance,2)," ",currency,"\n",
         "Equity: ",DoubleToString(equity,2)," ",currency
      );
   }
}

int OnInit()
{
   if(InpFastEMA<=0 || InpSlowEMA<=0 || InpRSIPeriod<=0 ||
      InpFastEMA>=InpSlowEMA || InpMaxSpreadPoints<=0.0)
   {
      Print("Invalid inputs. Require 0 < Fast EMA < Slow EMA and positive periods/spread.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_fastHandle=iMA(_Symbol,PERIOD_M1,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowHandle=iMA(_Symbol,PERIOD_M1,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_rsiHandle=iRSI(_Symbol,PERIOD_M1,InpRSIPeriod,PRICE_CLOSE);

   if(g_fastHandle==INVALID_HANDLE || g_slowHandle==INVALID_HANDLE ||
      g_rsiHandle==INVALID_HANDLE)
   {
      Print("Failed to create indicator handles. Error=",GetLastError());
      return INIT_FAILED;
   }

   Print("Initialized on ",_Symbol,
         ". SIGNAL-ONLY MODE: no OrderSend/CTrade calls exist in this build.");
   Print("Account balance is read-only: ",
         DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)," ",
         AccountInfoString(ACCOUNT_CURRENCY));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fastHandle!=INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle!=INVALID_HANDLE) IndicatorRelease(g_slowHandle);
   if(g_rsiHandle!=INVALID_HANDLE)  IndicatorRelease(g_rsiHandle);
   Comment("");
}

void OnTick()
{
   // Tick-driven spread monitor, but signal evaluation occurs only once per
   // newly closed M1 candle to avoid repeatedly reacting to an unfinished bar.
   datetime closedBarTime=iTime(_Symbol,PERIOD_M1,1);
   if(closedBarTime<=0 || closedBarTime==g_lastClosedBar)
      return;

   g_lastClosedBar=closedBarTime;

   double fastCurrent,fastPrevious,slowCurrent,slowPrevious,rsiCurrent;
   if(!ReadValue(g_fastHandle,0,1,fastCurrent) ||
      !ReadValue(g_fastHandle,0,2,fastPrevious) ||
      !ReadValue(g_slowHandle,0,1,slowCurrent) ||
      !ReadValue(g_slowHandle,0,2,slowPrevious) ||
      !ReadValue(g_rsiHandle,0,1,rsiCurrent))
   {
      PublishStatus(SIGNAL_DATA_WAIT,"Indicator buffers are not ready.",0,0,0,
                    CurrentSpreadPoints());
      return;
   }

   double spread=CurrentSpreadPoints();
   if(spread<0.0)
   {
      PublishStatus(SIGNAL_DATA_WAIT,"No valid tick is available.",fastCurrent,
                    slowCurrent,rsiCurrent,spread);
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
         reason="EMA bullish crossover confirmed by RSI. Candidate only; no order sent.";
      }
      else if(bearishCross && rsiCurrent>=InpRSISellMin && rsiCurrent<=InpRSISellMax)
      {
         signal=SIGNAL_SELL_SETUP;
         reason="EMA bearish crossover confirmed by RSI. Candidate only; no order sent.";
      }
   }

   PublishStatus(signal,reason,fastCurrent,slowCurrent,rsiCurrent,spread);
}
//+------------------------------------------------------------------+
