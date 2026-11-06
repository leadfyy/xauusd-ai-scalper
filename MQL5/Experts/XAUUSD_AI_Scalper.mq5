//+------------------------------------------------------------------+
//| XAUUSD Trend Rider 1.20                                          |
//| M5 pullback/reclaim entries with M15/H1 trend alignment          |
//| ATR initial stop + ATR trailing stop; demo-only execution         |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"
#property description "XAUUSD trend-following EA. Demo-only execution, disabled by default."

#include <Trade/Trade.mqh>

//--- Signal and trend timeframes
input ENUM_TIMEFRAMES InpSignalTF       = PERIOD_M5;
input ENUM_TIMEFRAMES InpConfirmTF      = PERIOD_M15;
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1;

//--- Trend and entry indicators
input int      InpTrendFastEMA          = 50;
input int      InpTrendSlowEMA          = 200;
input int      InpPullbackEMA           = 20;
input int      InpRSIPeriod             = 14;
input int      InpADXPeriod             = 14;
input double   InpMinADX                = 22.0;
input double   InpBuyRSIMin             = 52.0;
input double   InpSellRSIMax            = 48.0;
input double   InpTouchToleranceATR     = 0.25;

//--- Volatility and execution filters
input int      InpATRPeriod             = 14;
input double   InpMaxSpreadPoints       = 80.0;

//--- Risk controls
input bool     InpEnableDemoTrading     = false;
input double   InpRiskPerTradePct       = 0.25;
input double   InpMaxDailyLossPct       = 1.5;
input int      InpMaxTradesPerDay       = 2;
input double   InpInitialStopATR        = 2.2;
input double   InpTrailStartATR         = 1.5;
input double   InpTrailDistanceATR      = 2.0;
input ulong    InpMagicNumber           = 26110602;
input int      InpDeviationPoints       = 30;
input bool     InpShowChartComment      = true;

int hPullback=INVALID_HANDLE, hRSI=INVALID_HANDLE, hATR=INVALID_HANDLE;
int hConfirmFast=INVALID_HANDLE, hConfirmSlow=INVALID_HANDLE, hADX=INVALID_HANDLE;
int hTrendFast=INVALID_HANDLE, hTrendSlow=INVALID_HANDLE;
datetime g_lastSignalBar=0;
CTrade trade;

enum TrendSignal { SIG_NONE=0, SIG_BUY, SIG_SELL, SIG_WAIT, SIG_SPREAD };

string SignalName(const TrendSignal s)
{
   if(s==SIG_BUY) return "BUY TREND PULLBACK";
   if(s==SIG_SELL) return "SELL TREND PULLBACK";
   if(s==SIG_WAIT) return "WAITING FOR DATA";
   if(s==SIG_SPREAD) return "SPREAD FILTER";
   return "NO SETUP";
}

bool ReadBuffer(const int handle,const int buffer,const int shift,double &v)
{
   double a[1];
   if(handle==INVALID_HANDLE || CopyBuffer(handle,buffer,shift,1,a)!=1) return false;
   v=a[0];
   return (v!=EMPTY_VALUE);
}

double SpreadPoints()
{
   MqlTick t;
   double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(p<=0 || !SymbolInfoTick(_Symbol,t)) return -1;
   return (t.ask-t.bid)/p;
}

datetime BrokerDayStart()
{
   MqlDateTime x;
   TimeToStruct(TimeCurrent(),x);
   x.hour=0; x.min=0; x.sec=0;
   return StructToTime(x);
}

void DailyStats(double &pnl,int &entries)
{
   pnl=0; entries=0;
   if(!HistorySelect(BrokerDayStart(),TimeCurrent())) return;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0 || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagicNumber ||
         HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
      pnl+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+
           HistoryDealGetDouble(d,DEAL_COMMISSION);
      ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(e==DEAL_ENTRY_IN || e==DEAL_ENTRY_INOUT) entries++;
   }
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL)==_Symbol)
         pnl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
}

bool IsDemo()
{
   return ((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO);
}

bool FindOurPosition(ulong &ticket,ENUM_POSITION_TYPE &type,double &open,double &sl,double &tp)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL)==_Symbol)
      {
         ticket=t;
         type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         open=PositionGetDouble(POSITION_PRICE_OPEN);
         sl=PositionGetDouble(POSITION_SL);
         tp=PositionGetDouble(POSITION_TP);
         return true;
      }
   }
   return false;
}

int VolDigits(double step)
{
   for(int i=0;i<=8;i++)
      if(MathAbs(step-NormalizeDouble(step,i))<1e-8) return i;
   return 2;
}

double RiskVolume(ENUM_ORDER_TYPE side,double entry,double stop,string &why)
{
   double risk=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPerTradePct/100.0;
   double result=0;
   if(risk<=0 || !OrderCalcProfit(side,_Symbol,1.0,entry,stop,result))
   { why="OrderCalcProfit failed"; return 0; }
   double perLot=MathAbs(result);
   if(perLot<=0) { why="Invalid stop risk"; return 0; }
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || minv<=0 || maxv<=0) { why="Invalid broker volume rules"; return 0; }
   double v=MathFloor((risk/perLot)/step)*step;
   v=NormalizeDouble(v,VolDigits(step));
   if(v<minv) { why="Safe lot is below broker minimum; skipped"; return 0; }
   return MathMin(v,maxv);
}

void ManageTrailingStop()
{
   ulong ticket; ENUM_POSITION_TYPE type; double open,sl,tp;
   if(!FindOurPosition(ticket,type,open,sl,tp)) return;

   double atr;
   if(!ReadBuffer(hATR,0,1,atr) || atr<=0) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   long minStop=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist=(minStop+2)*point;
   double candidate=sl;

   if(type==POSITION_TYPE_BUY)
   {
      double move=tick.bid-open;
      if(move<InpTrailStartATR*atr) return;
      candidate=MathMax(open+0.10*atr,tick.bid-InpTrailDistanceATR*atr);
      candidate=MathMin(candidate,tick.bid-minDist);
      candidate=NormalizeDouble(candidate,digits);
      if(sl>0 && candidate<=sl+2*point) return;
   }
   else
   {
      double move=open-tick.ask;
      if(move<InpTrailStartATR*atr) return;
      candidate=MathMin(open-0.10*atr,tick.ask+InpTrailDistanceATR*atr);
      candidate=MathMax(candidate,tick.ask+minDist);
      candidate=NormalizeDouble(candidate,digits);
      if(sl>0 && candidate>=sl-2*point) return;
   }

   if(!trade.PositionModify(ticket,candidate,tp))
      Print("Trailing stop update failed: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   else
      Print("Trailing stop updated to ",DoubleToString(candidate,digits));
}

void OpenSignal(TrendSignal signal,double atr)
{
   if(!InpEnableDemoTrading) { Print("Signal only: execution disabled."); return; }
   if(!IsDemo()) { Print("SAFETY BLOCK: demo account required."); return; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   { Print("Trading permission disabled."); return; }

   ulong existing; ENUM_POSITION_TYPE pt; double op,ps,ptp;
   if(FindOurPosition(existing,pt,op,ps,ptp)) return;

   double pnl; int entries; DailyStats(pnl,entries);
   double dailyLimit=AccountInfoDouble(ACCOUNT_BALANCE)*InpMaxDailyLossPct/100.0;
   if(pnl<=-dailyLimit || entries>=InpMaxTradesPerDay)
   { Print("Daily risk/trade limit reached. P/L=",DoubleToString(pnl,2)," entries=",entries); return; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || atr<=0) return;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double dist=MathMax(atr*InpInitialStopATR,(stops+2)*point);
   ENUM_ORDER_TYPE side=(signal==SIG_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double entry=(side==ORDER_TYPE_BUY ? tick.ask : tick.bid);
   double sl=(side==ORDER_TYPE_BUY ? entry-dist : entry+dist);
   sl=NormalizeDouble(sl,digits);
   string why="";
   double lots=RiskVolume(side,entry,sl,why);
   if(lots<=0) { Print("Entry skipped: ",why); return; }

   bool ok=false;
   if(side==ORDER_TYPE_BUY)
      ok=trade.Buy(lots,_Symbol,0.0,sl,0.0,"Trend Rider BUY");
   else
      ok=trade.Sell(lots,_Symbol,0.0,sl,0.0,"Trend Rider SELL");

   if(!ok)
      Print("Order failed: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   else
      Print("DEMO trend entry submitted. Side=",EnumToString(side)," lots=",DoubleToString(lots,VolDigits(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)))," SL=",DoubleToString(sl,digits)," TP=ATR trailing");
}

void ShowStatus(TrendSignal sig,string reason,double adx,double rsi,double atr,double spread)
{
   double pnl; int entries; DailyStats(pnl,entries);
   string mode=(InpEnableDemoTrading ? (IsDemo() ? "DEMO EXECUTION ARMED" : "LIVE BLOCKED") : "SIGNAL ONLY");
   if(InpShowChartComment)
      Comment("XAUUSD TREND RIDER 1.20\n",
              "Mode: ",mode,"\n",
              "Signal: ",SignalName(sig),"\n",
              "Reason: ",reason,"\n",
              "M15 ADX: ",DoubleToString(adx,1)," | M5 RSI: ",DoubleToString(rsi,1),"\n",
              "M5 ATR: ",DoubleToString(atr,_Digits)," | Spread: ",DoubleToString(spread,1)," pts\n",
              "Daily EA P/L: ",DoubleToString(pnl,2)," | Entries: ",entries,"/",InpMaxTradesPerDay,"\n",
              "Risk: ",DoubleToString(InpRiskPerTradePct,2),"% | Daily stop: ",DoubleToString(InpMaxDailyLossPct,2),"%");
   Print(_Symbol," | ",SignalName(sig)," | ",reason," | ADX=",DoubleToString(adx,1)," RSI=",DoubleToString(rsi,1));
}

int OnInit()
{
   if(InpTrendFastEMA<=0 || InpTrendSlowEMA<=InpTrendFastEMA ||
      InpPullbackEMA<=0 || InpRSIPeriod<=0 || InpADXPeriod<=0 || InpATRPeriod<=0 ||
      InpMinADX<0 || InpRiskPerTradePct<=0 || InpRiskPerTradePct>1.0 ||
      InpMaxDailyLossPct<=0 || InpMaxDailyLossPct>5.0 ||
      InpMaxTradesPerDay<1 || InpInitialStopATR<=0 ||
      InpTrailStartATR<=0 || InpTrailDistanceATR<=0 || InpMaxSpreadPoints<=0)
   { Print("Invalid inputs."); return INIT_PARAMETERS_INCORRECT; }

   hPullback=iMA(_Symbol,InpSignalTF,InpPullbackEMA,0,MODE_EMA,PRICE_CLOSE);
   hRSI=iRSI(_Symbol,InpSignalTF,InpRSIPeriod,PRICE_CLOSE);
   hATR=iATR(_Symbol,InpSignalTF,InpATRPeriod);
   hConfirmFast=iMA(_Symbol,InpConfirmTF,InpTrendFastEMA,0,MODE_EMA,PRICE_CLOSE);
   hConfirmSlow=iMA(_Symbol,InpConfirmTF,InpTrendSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hADX=iADX(_Symbol,InpConfirmTF,InpADXPeriod);
   hTrendFast=iMA(_Symbol,InpTrendTF,InpTrendFastEMA,0,MODE_EMA,PRICE_CLOSE);
   hTrendSlow=iMA(_Symbol,InpTrendTF,InpTrendSlowEMA,0,MODE_EMA,PRICE_CLOSE);

   if(hPullback==INVALID_HANDLE || hRSI==INVALID_HANDLE || hATR==INVALID_HANDLE ||
      hConfirmFast==INVALID_HANDLE || hConfirmSlow==INVALID_HANDLE || hADX==INVALID_HANDLE ||
      hTrendFast==INVALID_HANDLE || hTrendSlow==INVALID_HANDLE)
   { Print("Indicator initialization failed: ",GetLastError()); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   Print("XAUUSD Trend Rider 1.20 initialized. Demo-only execution guard active; execution default OFF.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hPullback!=INVALID_HANDLE) IndicatorRelease(hPullback);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hConfirmFast!=INVALID_HANDLE) IndicatorRelease(hConfirmFast);
   if(hConfirmSlow!=INVALID_HANDLE) IndicatorRelease(hConfirmSlow);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hTrendFast!=INVALID_HANDLE) IndicatorRelease(hTrendFast);
   if(hTrendSlow!=INVALID_HANDLE) IndicatorRelease(hTrendSlow);
   Comment("");
}

void OnTick()
{
   // Keep managing an existing position on every tick; new entries are evaluated on closed signal candles only.
   ManageTrailingStop();

   datetime bar=iTime(_Symbol,InpSignalTF,1);
   if(bar<=0 || bar==g_lastSignalBar) return;
   g_lastSignalBar=bar;

   double ema1,ema2,rsi,atr,cf,cs,adx,plusDI,minusDI,tf,ts;
   if(!ReadBuffer(hPullback,0,1,ema1) || !ReadBuffer(hPullback,0,2,ema2) ||
      !ReadBuffer(hRSI,0,1,rsi) || !ReadBuffer(hATR,0,1,atr) ||
      !ReadBuffer(hConfirmFast,0,1,cf) || !ReadBuffer(hConfirmSlow,0,1,cs) ||
      !ReadBuffer(hADX,0,1,adx) || !ReadBuffer(hADX,1,1,plusDI) ||
      !ReadBuffer(hADX,2,1,minusDI) || !ReadBuffer(hTrendFast,0,1,tf) ||
      !ReadBuffer(hTrendSlow,0,1,ts))
   {
      ShowStatus(SIG_WAIT,"Waiting for M5/M15/H1 indicator history.",0,0,0,SpreadPoints());
      return;
   }

   double spread=SpreadPoints();
   if(spread<0) { ShowStatus(SIG_WAIT,"No valid tick.",adx,rsi,atr,spread); return; }

   TrendSignal sig=SIG_NONE;
   string reason="No pullback/reclaim setup.";
   if(spread>InpMaxSpreadPoints)
   {
      sig=SIG_SPREAD;
      reason="Spread above configured ceiling.";
   }
   else
   {
      double close1=iClose(_Symbol,InpSignalTF,1);
      double open1=iOpen(_Symbol,InpSignalTF,1);
      double low1=iLow(_Symbol,InpSignalTF,1);
      double high1=iHigh(_Symbol,InpSignalTF,1);
      double close2=iClose(_Symbol,InpSignalTF,2);
      double low2=iLow(_Symbol,InpSignalTF,2);
      double high2=iHigh(_Symbol,InpSignalTF,2);

      bool upTrend=(cf>cs && tf>ts && plusDI>minusDI && adx>=InpMinADX);
      bool downTrend=(cf<cs && tf<ts && minusDI>plusDI && adx>=InpMinADX);

      bool touchedForBuy=(low1<=ema1+InpTouchToleranceATR*atr ||
                          low2<=ema2+InpTouchToleranceATR*atr ||
                          close2<=ema2);
      bool touchedForSell=(high1>=ema1-InpTouchToleranceATR*atr ||
                           high2>=ema2-InpTouchToleranceATR*atr ||
                           close2>=ema2);

      bool buyReclaim=(close1>ema1 && close1>open1 && touchedForBuy);
      bool sellReclaim=(close1<ema1 && close1<open1 && touchedForSell);

      if(upTrend && buyReclaim && rsi>=InpBuyRSIMin)
      {
         sig=SIG_BUY;
         reason="H1/M15 bullish trend; M5 pullback reclaimed EMA; ADX/DI/RSI confirm.";
      }
      else if(downTrend && sellReclaim && rsi<=InpSellRSIMax)
      {
         sig=SIG_SELL;
         reason="H1/M15 bearish trend; M5 pullback rejected EMA; ADX/DI/RSI confirm.";
      }
      else
      {
         reason=StringFormat("Filters not aligned. H1 EMA %.2f/%.2f; M15 ADX %.1f; M5 RSI %.1f.",tf,ts,adx,rsi);
      }
   }

   ShowStatus(sig,reason,adx,rsi,atr,spread);
   if(sig==SIG_BUY || sig==SIG_SELL) OpenSignal(sig,atr);
}
//+------------------------------------------------------------------+
