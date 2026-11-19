//+------------------------------------------------------------------+
//| Gold Session Liquidity Free MT5                                    |
//| Free educational build 1.10 - FXLINER - 2026                    |
//| OHLC-based liquidity proxy; does NOT inspect real resting orders. |
//| Contains techniques developed in Smart Liquidity Hunter v1.11,   |
//| (c) Smart Liquidity Hunter contributors, used under the MIT       |
//| License (see THIRD_PARTY_NOTICES.txt).                            |
//| Signal confirmation uses closed bars; never the forming bar.     |
//+------------------------------------------------------------------+
#property strict
#property copyright "FXLINER; Smart Liquidity Hunter contributors (MIT portions)"
#property link      "https://forexreview.top/"
#property version   "1.100"
#property description "FREE XAUUSD analysis: sessions, closed-bar liquidity sweeps, swing breaks and risk planner. Experimental trading signals off by default."
#property indicator_chart_window
#property indicator_buffers 17
#property indicator_plots 17
#property indicator_label1  "Confirmed BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_width1  2
#property indicator_label2  "Confirmed SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_width2  2
#property indicator_label3  "Completed Asian High"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDarkOrange
#property indicator_style3  STYLE_DOT
#property indicator_label4  "Completed Asian Low"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDeepSkyBlue
#property indicator_style4  STYLE_DOT

#property indicator_label14 "Liquidity sweep LOW (reclaimed)"
#property indicator_type14 DRAW_ARROW
#property indicator_color14 clrLimeGreen
#property indicator_width14 1
#property indicator_label15 "Liquidity sweep HIGH (rejected)"
#property indicator_type15 DRAW_ARROW
#property indicator_color15 clrTomato
#property indicator_width15 1
#property indicator_label16 "Confirmed swing break UP"
#property indicator_type16 DRAW_ARROW
#property indicator_color16 clrDeepSkyBlue
#property indicator_width16 1
#property indicator_label17 "Confirmed swing break DOWN"
#property indicator_type17 DRAW_ARROW
#property indicator_color17 clrOrange

// Buffer index map for EA iCustom / CopyBuffer:
// 0 BUY arrow; 1 SELL arrow; 2 completed Asia high; 3 Asia low;
// 4 BUY SL; 5 SELL SL; 6 BUY TP1; 7 SELL TP1;
// 8 BUY TP2; 9 SELL TP2; 10 BUY TP3; 11 SELL TP3;
// 12 signal quality 0..100 (EMPTY_VALUE without signal).
// 13 sweep low; 14 sweep high; 15 swing structure break up; 16 break down.
// Experimental signal buffers 0/1 and trade plan buffers 4..12 remain
// EMPTY_VALUE unless user explicitly opts into ShowExperimentalSignals.

enum ENUM_GSLP_BROKER_TIME
  {
   BROKER_FIXED_UTC = 0,         // Fixed server offset all year
   BROKER_EU_DST = 1             // Winter UTC+N; summer UTC+N+1
  };

input group "01 | Session clock (historical broker timestamps)"
input ENUM_GSLP_BROKER_TIME BrokerClock = BROKER_EU_DST;
input int    BrokerWinterUTCOffsetHours = 2; // Typical UTC+2 winter, +3 summer
input int    AsianStartUTCHour          = 0;
input int    AsianEndUTCHour            = 6; // Completed Asia range, [00:00,06:00)
input bool   TradeLondon                = true;
input bool   TradeNewYork               = true;
input bool   TradeAsia                  = false;
input bool   UseAsianLiquidity          = true;
input bool   ShowAsianRange             = true;

input group "02 | Liquidity and MSS confirmation"
input int    SwingStrength              = 3;
input int    MaxSwingAge                = 90;
input bool   RequireFreshLevel          = true;
input int    MinSweepPoints             = 10;
input double MinSweepToATR              = 0.10;
input double MinRejectionWickPct         = 20.0;
input double MinCloseLocationPct        = 55.0;
input int    StructureLookback          = 12; // Before sweep; no lookahead
input int    MSSConfirmBars             = 6;  // Strictly AFTER sweep bar
input double EqualLevelATR             = 0.12;

input group "03 | Market filters and setup score"
input int    MeanTrueRangePeriod        = 14;
input double MinBarRangeToATR           = 0.30;
input double MaxBarRangeToATR           = 3.50;
input double MaxSpreadToATR             = 0.15; // 0 disables, only if spread history known
input int    MinRecordedSpreadPoints    = 0;    // 0 disables minimum
input bool   RequireRecordedSpread      = false;
input bool   FilterChoppyMarkets        = true;
input int    EfficiencyLookback         = 12;
input double MinEfficiencyRatio         = 0.15;
input ENUM_TIMEFRAMES TrendTimeframe    = PERIOD_H1;
input int    TrendFastEMA               = 20;
input int    TrendSlowEMA               = 50;
input bool   RequireTrendAlignment      = false; // Context is scored regardless
input int    MinimumSignalScore         = 65;

input group "04 | Trade plan and presentation"
input double StopBufferATR              = 0.15;
input double MaxStopDistanceATR         = 3.50;
input double Target1R                   = 1.0;
input double Target2R                   = 2.0;
input double Target3R                   = 3.0;
input int    MaxBarsToScan              = 900;
input bool   ShowDashboard              = true;
input bool   ShowCurrentTradePlan       = false; // Research-only overlay, off by default
input int    MaximumDisplayPlanAgeBars  = 24; // Hide outdated chart trade lines
input string InstanceID                 = "GSLF"; // Different ID if multiple copies on chart
input int    DashboardX                 = 16;
input int    DashboardY                 = 26;
input color  DashboardBackground        = C'19,28,42';
input color  DashboardForeground        = clrWhiteSmoke;
input group "05 | Free analysis overlays (non-trading)"
input bool   ShowLiquiditySweeps        = true;
input bool   ShowStructureBreaks        = true;
input bool   ShowExperimentalSignals    = false; // UNVALIDATED research only
input group "06 | Manual broker-aware risk calculator"
input bool   ShowManualRiskPlanner      = true;
input double RiskBudgetPercent          = 0.50; // % of account equity
input double ManualEntryPrice           = 0.0;  // Set both entry and stop manually
input double ManualStopPrice            = 0.0;
input double ManualTargetPrice          = 0.0;  // Optional R:R illustration
input double CommissionPerLotRoundTrip  = 7.0;  // Estimated account currency/lot
input bool   PopupAlerts                = false;
input bool   PushAlerts                 = false;
input bool   SoundAlerts                = false;

double BuyArrow[],SellArrow[],AsiaHighLine[],AsiaLowLine[];
double BuySL[],SellSL[],BuyTP1[],SellTP1[],BuyTP2[],SellTP2[],BuyTP3[],SellTP3[],Quality[];
double LowSweepMark[],HighSweepMark[],BreakUpMark[],BreakDownMark[];
datetime g_lastOpening=0,g_lastAlert=0;
int g_fastHandle=INVALID_HANDLE,g_slowHandle=INVALID_HANDLE;
double g_fastEMA[],g_slowEMA[];
bool g_trendReady=false;
string g_prefix="";

//+------------------------------------------------------------------+
//| Pure clock functions: timestamps are interpreted as UTC.         |
//+------------------------------------------------------------------+
datetime UTCStamp(const int y,const int m,const int d,const int hh=0)
  {
   MqlDateTime x;
   ZeroMemory(x);
   x.year=y; x.mon=m; x.day=d; x.hour=hh;
   return(StructToTime(x));
  }
int WeekdayOf(const int y,const int m,const int d)
  {
   MqlDateTime x; TimeToStruct(UTCStamp(y,m,d),x); return(x.day_of_week);
  }
int LastSundayOf31(const int y,const int m)
  {return(31-WeekdayOf(y,m,31));}
int FirstSunday(const int y,const int m)
  {return(1+(7-WeekdayOf(y,m,1))%7);}
bool EuropeDST(const datetime utc)
  {
   MqlDateTime x; TimeToStruct(utc,x);
   const datetime begin=UTCStamp(x.year,3,LastSundayOf31(x.year,3),1);
   const datetime end=UTCStamp(x.year,10,LastSundayOf31(x.year,10),1);
   return(utc>=begin && utc<end);
  }
bool UnitedStatesDST(const datetime utc)
  {
   MqlDateTime x; TimeToStruct(utc,x);
   const datetime begin=UTCStamp(x.year,3,FirstSunday(x.year,3)+7,7);
   const datetime end=UTCStamp(x.year,11,FirstSunday(x.year,11),6);
   return(utc>=begin && utc<end);
  }
datetime BrokerToUTC(const datetime server)
  {
   // Determine the offset from candidate UTC values, not from server time.
   // Forex normally closes during the EU Sunday DST transition, when the
   // repeated local server hour is otherwise inherently ambiguous.
   const datetime winterUTC=server-BrokerWinterUTCOffsetHours*3600;
   if(BrokerClock==BROKER_FIXED_UTC) return(winterUTC);
   const datetime summerUTC=winterUTC-3600;
   if(EuropeDST(summerUTC)) return(summerUTC);
   return(winterUTC);
  }
int UTCDayKey(const datetime utc)
  {
   MqlDateTime x; TimeToStruct(utc,x);
   return(x.year*1000+x.day_of_year);
  }
int UTCHour(const datetime utc)
  {
   MqlDateTime x; TimeToStruct(utc,x); return(x.hour);
  }
// Session bitmask 1=Asia 2=London 4=New York.
int SessionMask(const datetime utc)
  {
   MqlDateTime x;TimeToStruct(utc,x);
   if(x.day_of_week==0 || x.day_of_week==6) return(0);
   const int minOfDay=x.hour*60+x.min;
   const int londonOpen=(EuropeDST(utc)?7:8)*60;
   const int newYorkOpen=(UnitedStatesDST(utc)?12:13)*60;
   int mask=0;
   if(minOfDay>=AsianStartUTCHour*60 && minOfDay<AsianEndUTCHour*60) mask|=1;
   if(minOfDay>=londonOpen && minOfDay<londonOpen+8*60) mask|=2;
   if(minOfDay>=newYorkOpen && minOfDay<newYorkOpen+9*60) mask|=4;
   return(mask);
  }
bool IsTradingSession(const datetime utc)
  {
   int mask=SessionMask(utc);
   return((TradeAsia && (mask&1)!=0) || (TradeLondon && (mask&2)!=0) ||
          (TradeNewYork && (mask&4)!=0));
  }
string SessionName(const datetime utc)
  {
   const int mask=SessionMask(utc);
   if((mask&2)!=0 && (mask&4)!=0) return("LONDON + NEW YORK");
   if((mask&4)!=0) return("NEW YORK");
   if((mask&2)!=0) return("LONDON");
   if((mask&1)!=0) return("ASIA");
   return("OUTSIDE SESSIONS");
  }

//+------------------------------------------------------------------+
//| Reference price data helpers. All indices are series (0=live).  |
//+------------------------------------------------------------------+
bool PivotHigh(const int j,const int bars,const double &h[])
  {
   if(j-SwingStrength<1 || j+SwingStrength>=bars) return(false);
   for(int n=1;n<=SwingStrength;n++)
      if(h[j]<=h[j-n] || h[j]<h[j+n]) return(false);
   return(true);
  }
bool PivotLow(const int j,const int bars,const double &l[])
  {
   if(j-SwingStrength<1 || j+SwingStrength>=bars) return(false);
   for(int n=1;n<=SwingStrength;n++)
      if(l[j]>=l[j-n] || l[j]>l[j+n]) return(false);
   return(true);
  }
int FindFreshPivot(const bool highs,const int i,const int bars,
                   const double &h[],const double &l[])
  {
   const int first=i+SwingStrength+1;
   const int last=(int)MathMin(i+MaxSwingAge,bars-SwingStrength-1);
   if(first>last) return(-1);
   double priorHi=-DBL_MAX,priorLo=DBL_MAX;
   if(RequireFreshLevel)
      for(int k=i+1;k<first;k++)
        {priorHi=MathMax(priorHi,h[k]);priorLo=MathMin(priorLo,l[k]);}
   for(int j=first;j<=last;j++)
     {
      const bool isPivot=highs?PivotHigh(j,bars,h):PivotLow(j,bars,l);
      if(isPivot && (!RequireFreshLevel ||
         (highs?priorHi<=h[j]+0.01*_Point:priorLo>=l[j]-0.01*_Point)))
         return(j);
      if(RequireFreshLevel)
        {priorHi=MathMax(priorHi,h[j]);priorLo=MathMin(priorLo,l[j]);}
     }
   return(-1);
  }
double MeanTrueRangeBefore(const int i,const int bars,const double &h[],
                           const double &l[],const double &c[])
  {
   if(i+MeanTrueRangePeriod+1>=bars) return(-1.0);
   double total=0.0;
   for(int k=i+1;k<=i+MeanTrueRangePeriod;k++)
     {
      double a=h[k]-l[k],b=MathAbs(h[k]-c[k+1]),d=MathAbs(l[k]-c[k+1]);
      total+=MathMax(a,MathMax(b,d));
     }
   return(total/MeanTrueRangePeriod);
  }
double EfficiencyBefore(const int i,const int bars,const double &c[])
  {
   if(i+EfficiencyLookback+1>=bars) return(-1.0);
   double traveled=0.0;
   for(int k=i+1;k<=i+EfficiencyLookback;k++) traveled+=MathAbs(c[k]-c[k+1]);
   if(traveled<_Point*0.01) return(0.0);
   return(MathAbs(c[i+1]-c[i+EfficiencyLookback+1])/traveled);
  }
bool Rejects(const bool bullish,const int i,const double &o[],
             const double &h[],const double &l[],const double &c[])
  {
   const double range=h[i]-l[i]; if(range<=0.0) return(false);
   const double wick=bullish?MathMin(o[i],c[i])-l[i]:h[i]-MathMax(o[i],c[i]);
   const double location=bullish?(c[i]-l[i])/range:(h[i]-c[i])/range;
   return(wick/range*100.0+1e-9>=MinRejectionWickPct &&
          location*100.0+1e-9>=MinCloseLocationPct);
  }
// Only use bars OLDER than index i. No future session high/low.
bool CompletedAsianRange(const int i,const int bars,const datetime &time[],
                         const double &h[],const double &l[],
                         double &hi,double &lo)
  {
   const datetime utc=BrokerToUTC(time[i]);
   if(UTCHour(utc)<AsianEndUTCHour) return(false);
   const int day=UTCDayKey(utc);
   hi=-DBL_MAX;lo=DBL_MAX;
   int count=0;
   for(int k=i+1;k<bars;k++)
     {
      const datetime older=BrokerToUTC(time[k]);
      if(UTCDayKey(older)!=day) break;
      const int hh=UTCHour(older);
      if(hh>=AsianStartUTCHour && hh<AsianEndUTCHour)
        {hi=MathMax(hi,h[k]);lo=MathMin(lo,l[k]);count++;}
     }
   return(count>=2 && hi>lo);
  }
// Count matching older pivot near same level, for quality scoring.
bool HasEqualPartner(const bool highs,const int pivot,const int bars,
                     const double &h[],const double &l[],
                     const double tolerance)
  {
   if(pivot<0 || tolerance<=0.0) return(false);
   const int last=(int)MathMin(bars-SwingStrength-1,pivot+MaxSwingAge);
   for(int j=pivot+SwingStrength+1;j<=last;j++)
     {
      if(highs && PivotHigh(j,bars,h) && MathAbs(h[j]-h[pivot])<=tolerance) return(true);
      if(!highs && PivotLow(j,bars,l) && MathAbs(l[j]-l[pivot])<=tolerance) return(true);
     }
   return(false);
  }

struct SweepSetup
  {
   bool bullish;
   bool asianLevel;
   bool equalLevel;
   int  bar;
   double level;
   double extreme;
   double structure;
   double mtr;
  };

// Strictly closed-bar sweep on index k; structure level comes BEFORE k.
bool DetectSweep(const bool bullish,const int k,const int bars,
                 const datetime &time[],const double &o[],
                 const double &h[],const double &l[],const double &c[],
                 SweepSetup &s)
  {
   const datetime utc=BrokerToUTC(time[k]);
   if(!IsTradingSession(utc)) return(false);
   if(k+StructureLookback+1>=bars) return(false);
   const double mtr=MeanTrueRangeBefore(k,bars,h,l,c);
   if(mtr<=0.0 || !Rejects(bullish,k,o,h,l,c)) return(false);
   const double penetration=MathMax(MinSweepPoints*_Point,MinSweepToATR*mtr);
   const int pv=FindFreshPivot(!bullish,k,bars,h,l);
   double swing=-1.0;
   if(pv>=0) swing=(bullish?l[pv]:h[pv]);
   double asiaHi=0.0,asiaLo=0.0;
   const bool hasAsia=UseAsianLiquidity && CompletedAsianRange(k,bars,time,h,l,asiaHi,asiaLo);
   const double asian=hasAsia?(bullish?asiaLo:asiaHi):0.0;
   const bool swingPass=(pv>=0 &&
       (bullish?(l[k]<swing-penetration && c[k]>swing):
                (h[k]>swing+penetration && c[k]<swing)));
   const bool asiaPass=(hasAsia &&
       (bullish?(l[k]<asian-penetration && c[k]>asian):
                (h[k]>asian+penetration && c[k]<asian)));
   if(!swingPass && !asiaPass) return(false);
   s.bullish=bullish;
   s.bar=k;
   s.asianLevel=asiaPass;
   s.level=asiaPass?asian:swing;
   s.equalLevel=(!asiaPass && HasEqualPartner(!bullish,pv,bars,h,l,mtr*EqualLevelATR));
   s.extreme=bullish?l[k]:h[k];
   s.mtr=mtr;
   double structure=bullish?-DBL_MAX:DBL_MAX;
   for(int j=k+1;j<=k+StructureLookback;j++)
      structure=bullish?MathMax(structure,h[j]):MathMin(structure,l[j]);
   s.structure=structure;
   // Sweep candle itself must NOT have already broken MSS structure.
   if(bullish && c[k]>=structure) return(false);
   if(!bullish && c[k]<=structure) return(false);
   return(true);
  }

// An MSS must be the FIRST post-sweep CLOSED candle breaking structure.
// If stop sweeps further while waiting, invalidate that candidate.
bool ConfirmMSS(const bool bullish,const int i,const SweepSetup &s,
                const double &h[],const double &l[],const double &c[],
                double &extreme)
  {
   if(bullish ? c[i]<=s.structure : c[i]>=s.structure) return(false);
   extreme=s.extreme;
   for(int j=s.bar-1;j>=i;j--)
     {
      if(j>i && (bullish?c[j]>s.structure:c[j]<s.structure)) return(false);
      extreme=bullish?MathMin(extreme,l[j]):MathMax(extreme,h[j]);
      // A deeper re-sweep after the candidate invalidates it, INCLUDING
      // the confirmation candle: never shift a stop to salvage a signal.
      if(bullish && l[j]<s.extreme-0.10*s.mtr) return(false);
      if(!bullish && h[j]>s.extreme+0.10*s.mtr) return(false);
     }
   return(true);
  }

// Indicators refer only to fully CLOSED higher-timeframe bars.
// EMA buffer index: iBarShift(current bar OPEN) + 1, conservatively
// excluding the containing higher-timeframe candle even at boundary.
bool PrepareTrend(const int bars,const datetime &time[])
  {
   g_trendReady=false;
   if(g_fastHandle==INVALID_HANDLE || g_slowHandle==INVALID_HANDLE) return(false);
   const int oldest=(int)MathMin(MaxBarsToScan+MSSConfirmBars+2,bars-1);
   const int sh=iBarShift(_Symbol,TrendTimeframe,time[oldest],false);
   if(sh<0) return(false);
   const int need=sh+3;
   if(CopyBuffer(g_fastHandle,0,0,need,g_fastEMA)<need ||
      CopyBuffer(g_slowHandle,0,0,need,g_slowEMA)<need) return(false);
   ArraySetAsSeries(g_fastEMA,true);
   ArraySetAsSeries(g_slowEMA,true);
   g_trendReady=true;
   return(true);
  }
int TrendDirection(const datetime when)
  {
   if(!g_trendReady) return(0);
   const int shift=iBarShift(_Symbol,TrendTimeframe,when,false)+1;
   if(shift<1 || shift>=ArraySize(g_fastEMA) || shift>=ArraySize(g_slowEMA)) return(0);
   if(g_fastEMA[shift]>g_slowEMA[shift]) return(1);
   if(g_fastEMA[shift]<g_slowEMA[shift]) return(-1);
   return(0);
  }

bool PassSignalFilters(const int i,const int bars,const int &spread[],
                       const double &h[],const double &l[],const double &c[],
                       double &mtr,double &efficiency,string &reason)
  {
   reason="OK";
   mtr=MeanTrueRangeBefore(i,bars,h,l,c);
   if(mtr<=0.0) {reason="MTR HISTORY";return(false);}
   const double range=(h[i]-l[i])/mtr;
   if(range<MinBarRangeToATR || range>MaxBarRangeToATR)
     {reason="VOLATILITY";return(false);}
   if(spread[i]>0 && MaxSpreadToATR>0.0 && spread[i]*_Point>MaxSpreadToATR*mtr)
     {reason="SPREAD";return(false);}
   if(RequireRecordedSpread && spread[i]<=0)
     {reason="SPREAD UNKNOWN";return(false);}
   if(spread[i]>0 && spread[i]<MinRecordedSpreadPoints)
     {reason="SPREAD INVALID";return(false);}
   efficiency=EfficiencyBefore(i,bars,c);
   if(efficiency<0.0) {reason="EFFICIENCY HISTORY";return(false);}
   if(FilterChoppyMarkets && efficiency<MinEfficiencyRatio)
     {reason="CHOPPY";return(false);}
   return(true);
  }
int SignalScore(const int i,const bool bullish,const SweepSetup &s,
                const datetime &time[],const double &o[],const double &h[],const double &l[],
                const double &c[],const int trendDir)
  {
   int score=40;  // confirmed sweep (20) + first confirmed MSS (20)
   const double full=MathMax(h[s.bar]-l[s.bar],_Point);
   const double wick=bullish?MathMin(o[s.bar],c[s.bar])-l[s.bar]:
                           h[s.bar]-MathMax(o[s.bar],c[s.bar]);
   if(wick/full>=0.35) score+=10;
   else if(wick/full>=0.22) score+=6;
   if(s.asianLevel) score+=10;
   else if(s.equalLevel) score+=8;
   else score+=5;
   const int mask=SessionMask(BrokerToUTC(time[i]));
   if((mask&2)!=0 && (mask&4)!=0) score+=15;
   else if((mask&6)!=0) score+=12;
   else score+=5;
   if(trendDir==(bullish?1:-1)) score+=15;
   else if(trendDir==0) score+=5;
   const double barRange=MathMax(h[i]-l[i],_Point);
   const double closeLocation=bullish?(c[i]-l[i])/barRange:(h[i]-c[i])/barRange;
   if(closeLocation>=0.75) score+=10;
   else if(closeLocation>=0.60) score+=5;
   if(s.bar-i<=3) score+=5;
   return((int)MathMin(100,score));
  }

struct TradeSignal
  {
   bool bullish;
   int score;
   int sweepBar;
   bool fromAsia;
   double level;
   double structure;
   double entry;
   double stop;
   double tp1;
   double tp2;
   double tp3;
  };

bool FindTrade(const bool bullish,const int i,const int bars,
               const datetime &time[],const double &o[],
               const double &h[],const double &l[],const double &c[],
               const int &spread[],TradeSignal &result)
  {
   if(!IsTradingSession(BrokerToUTC(time[i]))) return(false);
   double mtr,efficiency; string reject;
   if(!PassSignalFilters(i,bars,spread,h,l,c,mtr,efficiency,reject)) return(false);
   const int trend=TrendDirection(time[i]);
   if(RequireTrendAlignment && trend!=(bullish?1:-1)) return(false);
   for(int k=i+1;k<=i+MSSConfirmBars && k<bars;k++)
     {
      SweepSetup s;
      if(!DetectSweep(bullish,k,bars,time,o,h,l,c,s)) continue;
      double extreme;
      if(!ConfirmMSS(bullish,i,s,h,l,c,extreme)) continue;
      const double stop=bullish?(extreme-StopBufferATR*mtr):(extreme+StopBufferATR*mtr);
      const double risk=bullish?c[i]-stop:stop-c[i];
      if(risk<0.25*mtr || risk>MaxStopDistanceATR*mtr) continue;
      const int score=SignalScore(i,bullish,s,time,o,h,l,c,trend);
      if(score<MinimumSignalScore) continue;
      result.bullish=bullish;
      result.score=score;
      result.sweepBar=k;
      result.fromAsia=s.asianLevel;
      result.level=s.level;
      result.structure=s.structure;
      result.entry=c[i];
      result.stop=NormalizeDouble(stop,_Digits);
      const double direction=bullish?1.0:-1.0;
      result.tp1=NormalizeDouble(c[i]+direction*Target1R*risk,_Digits);
      result.tp2=NormalizeDouble(c[i]+direction*Target2R*risk,_Digits);
      result.tp3=NormalizeDouble(c[i]+direction*Target3R*risk,_Digits);
      return(true); // most recent qualifying sweep; avoids multiple signals
     }
   return(false);
  }

void ClearBar(const int i)
  {
   BuyArrow[i]=EMPTY_VALUE;SellArrow[i]=EMPTY_VALUE;
   AsiaHighLine[i]=EMPTY_VALUE;AsiaLowLine[i]=EMPTY_VALUE;
   BuySL[i]=EMPTY_VALUE;SellSL[i]=EMPTY_VALUE;
   BuyTP1[i]=EMPTY_VALUE;SellTP1[i]=EMPTY_VALUE;
   BuyTP2[i]=EMPTY_VALUE;SellTP2[i]=EMPTY_VALUE;
   BuyTP3[i]=EMPTY_VALUE;SellTP3[i]=EMPTY_VALUE;
   Quality[i]=EMPTY_VALUE;
   LowSweepMark[i]=EMPTY_VALUE;HighSweepMark[i]=EMPTY_VALUE;
   BreakUpMark[i]=EMPTY_VALUE;BreakDownMark[i]=EMPTY_VALUE;
  }
void ClearEverything()
  {
   ArrayInitialize(BuyArrow,EMPTY_VALUE);
   ArrayInitialize(SellArrow,EMPTY_VALUE);
   ArrayInitialize(AsiaHighLine,EMPTY_VALUE);
   ArrayInitialize(AsiaLowLine,EMPTY_VALUE);
   ArrayInitialize(BuySL,EMPTY_VALUE);
   ArrayInitialize(SellSL,EMPTY_VALUE);
   ArrayInitialize(BuyTP1,EMPTY_VALUE);
   ArrayInitialize(SellTP1,EMPTY_VALUE);
   ArrayInitialize(BuyTP2,EMPTY_VALUE);
   ArrayInitialize(SellTP2,EMPTY_VALUE);
   ArrayInitialize(BuyTP3,EMPTY_VALUE);
   ArrayInitialize(SellTP3,EMPTY_VALUE);
   ArrayInitialize(Quality,EMPTY_VALUE);
   ArrayInitialize(LowSweepMark,EMPTY_VALUE);
   ArrayInitialize(HighSweepMark,EMPTY_VALUE);
   ArrayInitialize(BreakUpMark,EMPTY_VALUE);
   ArrayInitialize(BreakDownMark,EMPTY_VALUE);
  }
void CalculateClosedBar(const int i,const int bars,
                        const datetime &time[],const double &o[],
                        const double &h[],const double &l[],const double &c[],
                        const int &spread[])
  {
   ClearBar(i);
   if(ShowAsianRange)
     {
      double ah,al;
      if(CompletedAsianRange(i,bars,time,h,l,ah,al))
        {AsiaHighLine[i]=ah;AsiaLowLine[i]=al;}
     }
   // All overlay pivots and sweeps are computed using CLOSED bars only.
   // A liquidity sweep is an OHLC inference, NOT actual broker order-book liquidity.
   if(ShowLiquiditySweeps)
     {
      SweepSetup sweepLow,sweepHigh;
      const double mtr=MeanTrueRangeBefore(i,bars,h,l,c);
      if(mtr>0.0)
        {
         if(DetectSweep(true,i,bars,time,o,h,l,c,sweepLow))
            LowSweepMark[i]=l[i]-0.12*mtr;
         if(DetectSweep(false,i,bars,time,o,h,l,c,sweepHigh))
            HighSweepMark[i]=h[i]+0.12*mtr;
        }
     }
   if(ShowStructureBreaks)
     {
      const int highPivot=FindFreshPivot(true,i,bars,h,l);
      const int lowPivot =FindFreshPivot(false,i,bars,h,l);
      const double mtr=MeanTrueRangeBefore(i,bars,h,l,c);
      if(mtr>0.0)
        {
         if(highPivot>=0 && c[i]>h[highPivot]+2*_Point &&
            c[i+1]<=h[highPivot]+2*_Point)
            BreakUpMark[i]=l[i]-0.32*mtr;
         if(lowPivot>=0 && c[i]<l[lowPivot]-2*_Point &&
            c[i+1]>=l[lowPivot]-2*_Point)
            BreakDownMark[i]=h[i]+0.32*mtr;
        }
     }
   if(!ShowExperimentalSignals) return; // No BUY/SELL arrow or trade plan by default.
   TradeSignal buy,sell;
   const bool longFound=FindTrade(true,i,bars,time,o,h,l,c,spread,buy);
   const bool shortFound=FindTrade(false,i,bars,time,o,h,l,c,spread,sell);
   if(longFound && shortFound) return; // same-bar conflicting MSS: WAIT
   if(longFound)
     {
      const double mtr=MeanTrueRangeBefore(i,bars,h,l,c);
      BuyArrow[i]=l[i]-0.18*mtr;
      BuySL[i]=buy.stop;
      BuyTP1[i]=buy.tp1;BuyTP2[i]=buy.tp2;BuyTP3[i]=buy.tp3;
      Quality[i]=buy.score;
     }
   if(shortFound)
     {
      const double mtr=MeanTrueRangeBefore(i,bars,h,l,c);
      SellArrow[i]=h[i]+0.18*mtr;
      SellSL[i]=sell.stop;
      SellTP1[i]=sell.tp1;SellTP2[i]=sell.tp2;SellTP3[i]=sell.tp3;
      Quality[i]=sell.score;
     }
  }

//+------------------------------------------------------------------+
//| UI and chart objects - named per instance and deleted on remove. |
//+------------------------------------------------------------------+
void SetPanelLabel(const string key,const string value,const int row,
                   const int fontSize,const color ink)
  {
   const string name=g_prefix+key;
   if(ObjectFind(0,name)<0)
      if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0)) return;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DashboardX+14);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardY+14+row*23);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,200);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetString(0,name,OBJPROP_TEXT,value);
  }
void SetupPanel()
  {
   if(!ShowDashboard) return;
   const string name=g_prefix+"PANEL_BG";
   if(ObjectFind(0,name)<0)
      if(!ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0)) return;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DashboardX);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardY);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,520);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,284);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,DashboardBackground);
   ObjectSetInteger(0,name,OBJPROP_COLOR,C'55,76,99');
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,100);
  }
int RecentSignalIndex(const int bars)
  {
   const int max=(int)MathMin(bars-1,MaxBarsToScan);
   for(int i=1;i<=max;i++)
      if(BuyArrow[i]!=EMPTY_VALUE || SellArrow[i]!=EMPTY_VALUE) return(i);
   return(-1);
  }
string RiskMoneyLabel()
  {
   if(!ShowManualRiskPlanner) return("RISK PLANNER: DISABLED");
   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0) return("RISK PLANNER: equity unavailable (connect demo account)");
   return("BUDGET "+DoubleToString(RiskBudgetPercent,2)+"% of equity  =  "+
          DoubleToString(equity*RiskBudgetPercent/100.0,2)+" "+
          AccountInfoString(ACCOUNT_CURRENCY));
  }
string SuggestedManualLots()
  {
   if(!ShowManualRiskPlanner) return("LOT: manual planner disabled");
   if(ManualEntryPrice<=0.0 || ManualStopPrice<=0.0 ||
      MathAbs(ManualEntryPrice-ManualStopPrice)<_Point)
      return("LOT: set ManualEntryPrice + ManualStopPrice in inputs");
   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0) return("LOT: no account equity");
   const bool buy=(ManualEntryPrice>ManualStopPrice);
   const double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   const double maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   const double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(minimum<=0.0 || maximum<minimum || step<=0.0)
      return("LOT: broker lot specification unavailable");
   double loss=0.0;
   if(!OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,
                      _Symbol,minimum,ManualEntryPrice,ManualStopPrice,loss) ||
      loss>=0.0)
      return("LOT: check symbol or entry/stop levels");
   const double riskPerLot=(-loss/minimum)+CommissionPerLotRoundTrip;
   const double budget=equity*RiskBudgetPercent/100.0;
   if(riskPerLot<=0.0) return("LOT: risk calculation unavailable");
   const double rawLots=MathMin(maximum,budget/riskPerLot);
   const double lots=NormalizeDouble(MathFloor(rawLots/step+1e-9)*step,8);
   if(lots<minimum-1e-9)
      return("LOT: min broker lot exceeds your chosen risk budget");
   const double expectedNominal=lots*riskPerLot;
   const double targetDistance=buy?ManualTargetPrice-ManualEntryPrice:
                                   ManualEntryPrice-ManualTargetPrice;
   const string rr=(ManualTargetPrice>0.0 && targetDistance>0.0)?
          "  |  price R:R "+DoubleToString(targetDistance/
                      MathAbs(ManualEntryPrice-ManualStopPrice),2):"";
   return("LOT "+DoubleToString(lots,2)+" "+(buy?"BUY":"SELL")+
          "  |  nominal SL "+DoubleToString(expectedNominal,2)+
          " "+AccountInfoString(ACCOUNT_CURRENCY)+rr);
  }

int RecentOverlay(const int bars,int &kind)
  {
   kind=0;
   const int limit=(int)MathMin(bars-1,96); // no stale historical setups
   for(int i=1;i<=limit;i++)
     {
      if(LowSweepMark[i]!=EMPTY_VALUE) {kind=1;return(i);}
      if(HighSweepMark[i]!=EMPTY_VALUE) {kind=2;return(i);}
     }
   return(-1);
  }
int RecentStructure(const int bars,int &kind)
  {
   kind=0;
   const int limit=(int)MathMin(bars-1,96);
   for(int i=1;i<=limit;i++)
     {
      if(BreakUpMark[i]!=EMPTY_VALUE) {kind=1;return(i);}
      if(BreakDownMark[i]!=EMPTY_VALUE) {kind=2;return(i);}
     }
   return(-1);
  }
void UpdatePanel(const int bars,const datetime &time[],const double &c[],
                 const double &h[],const double &l[],const int &spread[])
  {
   if(!ShowDashboard) return;
   SetupPanel();
   const datetime utc=BrokerToUTC(time[0]);
   const string tf=EnumToString((ENUM_TIMEFRAMES)_Period);
   const int trend=TrendDirection(time[1]);
   const string trendName=trend>0?"UP":(trend<0?"DOWN":"NEUTRAL / LOADING");
   const bool active=IsTradingSession(utc);
   SetPanelLabel("TITLE","GOLD SESSION LIQUIDITY FREE  |  MT5 v1.10",0,11,clrDeepSkyBlue);
   SetPanelLabel("SYMBOL",_Symbol+"  |  "+tf+"  |  "+SessionName(utc),1,9,DashboardForeground);
   SetPanelLabel("CLOCK","UTC "+TimeToString(utc,TIME_DATE|TIME_MINUTES)+
                 "  |  Session "+(active?"ACTIVE":"WAIT"),2,9,
                 active?clrLimeGreen:clrSilver);
   const long liveSpread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   const double mtr=MeanTrueRangeBefore(1,bars,h,l,c);
   const string costContext=(mtr>0.0 && liveSpread>0)?
           "  |  spread/ATR "+DoubleToString(100.0*liveSpread*_Point/mtr,1)+"%":"";
   SetPanelLabel("TREND",EnumToString(TrendTimeframe)+" EMA "+IntegerToString(TrendFastEMA)+"/"+
                 IntegerToString(TrendSlowEMA)+" "+trendName+
                 "  |  spread "+IntegerToString((int)liveSpread)+" pt"+costContext,
                 3,9,DashboardForeground);
   if(AsiaHighLine[0]!=EMPTY_VALUE && AsiaLowLine[0]!=EMPTY_VALUE)
      SetPanelLabel("ASIA","ASIA completed  H "+DoubleToString(AsiaHighLine[0],_Digits)+
                    "  |  L "+DoubleToString(AsiaLowLine[0],_Digits),4,9,DashboardForeground);
   else
      SetPanelLabel("ASIA","ASIA range: not yet completed / data unavailable",4,9,clrSilver);
   int kind=0;
   const int sw=RecentOverlay(bars,kind);
   if(sw>=1)
      SetPanelLabel("SWEEP",(kind==1?"SWEEP LOW reclaimed":"SWEEP HIGH rejected")+
                   "  |  "+TimeToString(time[sw],TIME_DATE|TIME_MINUTES),5,9,
                   kind==1?clrLimeGreen:clrTomato);
   else
      SetPanelLabel("SWEEP","SWEEPS: no recent closed-bar event",5,9,clrSilver);
   int skind=0;
   const int br=RecentStructure(bars,skind);
   if(br>=1)
      SetPanelLabel("STRUCTURE",(skind==1?"SWING BREAK UP":"SWING BREAK DOWN")+
           "  |  "+TimeToString(time[br],TIME_DATE|TIME_MINUTES),6,9,
           skind==1?clrDeepSkyBlue:clrOrange);
   else
      SetPanelLabel("STRUCTURE","STRUCTURE: no recent closed-bar break",6,9,clrSilver);
   if(!ShowExperimentalSignals)
      SetPanelLabel("SIGNAL","EXPERIMENTAL BUY/SELL: OFF (research not validated)",7,9,clrSilver);
   else
     {
      const int latest=RecentSignalIndex(bars);
      if(latest<1 || latest>MaximumDisplayPlanAgeBars)
        SetPanelLabel("SIGNAL","EXPERIMENTAL BUY/SELL: no recent setup",7,9,clrSilver);
      else
        {
         const bool bull=(BuyArrow[latest]!=EMPTY_VALUE);
         SetPanelLabel("SIGNAL",string("RESEARCH ONLY: ")+(bull?"BUY":"SELL")+
              "  |  heuristic score "+IntegerToString((int)Quality[latest])+"/100",
              7,9,bull?clrLimeGreen:clrTomato);
        }
     }
   SetPanelLabel("RISK",RiskMoneyLabel(),8,9,DashboardForeground);
   SetPanelLabel("LOT",SuggestedManualLots(),9,9,DashboardForeground);
   SetPanelLabel("NOTICE","OHLC sweep proxy | SL not guaranteed | no proven trading edge",
                   10,8,clrSilver);
  }void TradeSegment(const string suffix,const datetime from,const datetime to,
                  const double price,const color ink,const ENUM_LINE_STYLE style)
  {
   const string name=g_prefix+"PLAN_"+suffix;
   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_TREND,0,from,price,to,price)) return;
     }
   else
     {
      ObjectMove(0,name,0,from,price);
      ObjectMove(0,name,1,to,price);
     }
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }
void DeleteTradeLines()
  {
   ObjectDelete(0,g_prefix+"PLAN_ENTRY");
   ObjectDelete(0,g_prefix+"PLAN_SL");
   ObjectDelete(0,g_prefix+"PLAN_TP1");
   ObjectDelete(0,g_prefix+"PLAN_TP2");
   ObjectDelete(0,g_prefix+"PLAN_TP3");
  }
void UpdateTradeLines(const int bars,const datetime &time[],const double &c[])
  {
   if(!ShowCurrentTradePlan) {DeleteTradeLines();return;}
   const int latest=RecentSignalIndex(bars);
   if(latest<0 || latest>MaximumDisplayPlanAgeBars) {DeleteTradeLines();return;}
   const bool longTrade=BuyArrow[latest]!=EMPTY_VALUE;
   const double sl=longTrade?BuySL[latest]:SellSL[latest];
   if(sl==EMPTY_VALUE) {DeleteTradeLines();return;}
   const int ps=PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   const datetime from=time[latest];
   const datetime to=(datetime)(time[0]+12*ps);
   const color signalColor=longTrade?clrLimeGreen:clrTomato;
   TradeSegment("ENTRY",from,to,c[latest],signalColor,STYLE_SOLID);
   TradeSegment("SL",from,to,sl,clrTomato,STYLE_DASH);
   TradeSegment("TP1",from,to,longTrade?BuyTP1[latest]:SellTP1[latest],clrDeepSkyBlue,STYLE_DOT);
   TradeSegment("TP2",from,to,longTrade?BuyTP2[latest]:SellTP2[latest],clrDeepSkyBlue,STYLE_DOT);
   TradeSegment("TP3",from,to,longTrade?BuyTP3[latest]:SellTP3[latest],clrDeepSkyBlue,STYLE_DOT);
  }
void AlertOnFreshClosedBar(const datetime &time[])
  {
   if(!ShowExperimentalSignals) return;
   if(!PopupAlerts && !PushAlerts && !SoundAlerts) return;
   if(time[1]==g_lastAlert) return;
   const bool buy=BuyArrow[1]!=EMPTY_VALUE;
   const bool sell=SellArrow[1]!=EMPTY_VALUE;
   if(!buy && !sell) return;
   g_lastAlert=time[1];
   const string msg="Gold Session Liquidity FREE (experimental) | "+_Symbol+" "+
     EnumToString((ENUM_TIMEFRAMES)_Period)+" | "+(buy?"BUY":"SELL")+
     " confirmed MSS | quality "+IntegerToString((int)Quality[1])+
     "/100 | "+TimeToString(time[1],TIME_DATE|TIME_MINUTES);
   if(PopupAlerts) Alert(msg);
   if(SoundAlerts) PlaySound("alert.wav");
   if(PushAlerts && !SendNotification(msg))
      Print("GSLP: push notification failed, error=",GetLastError());
  }
int NewlyClosed(const int bars,const datetime &time[])
  {
   const int cap=(int)MathMin(MaxBarsToScan,bars-1);
   for(int i=1;i<=cap;i++) if(time[i]==g_lastOpening) return(i);
   return(-1);
  }
bool ValidInputs()
  {
   return(BrokerWinterUTCOffsetHours>=-12 && BrokerWinterUTCOffsetHours<=14 &&
          AsianStartUTCHour>=0 && AsianStartUTCHour<24 &&
          AsianEndUTCHour>AsianStartUTCHour && AsianEndUTCHour<=24 &&
          (TradeLondon || TradeNewYork || TradeAsia) &&
          SwingStrength>=1 && SwingStrength<=15 &&
          MaxSwingAge>=SwingStrength+2 && MaxSwingAge<=500 &&
          StructureLookback>=3 && StructureLookback<=150 &&
          MSSConfirmBars>=1 && MSSConfirmBars<=20 &&
          MeanTrueRangePeriod>=3 && MeanTrueRangePeriod<=200 &&
          MinSweepPoints>=0 && MinSweepToATR>=0.0 &&
          MinRejectionWickPct>=0.0 && MinRejectionWickPct<=100.0 &&
          MinCloseLocationPct>=0.0 && MinCloseLocationPct<=100.0 &&
          EqualLevelATR>=0 && EqualLevelATR<=5.0 &&
          MinBarRangeToATR>=0.0 && MaxBarRangeToATR>MinBarRangeToATR &&
          MaxSpreadToATR>=0.0 && MinRecordedSpreadPoints>=0 &&
          EfficiencyLookback>=3 && EfficiencyLookback<=200 &&
          MinEfficiencyRatio>=0.0 && MinEfficiencyRatio<=1.0 &&
          TrendFastEMA>=2 && TrendSlowEMA>TrendFastEMA &&
          PeriodSeconds(TrendTimeframe)>0 &&
          MinimumSignalScore>=0 && MinimumSignalScore<=100 &&
          StopBufferATR>=0.0 && MaxStopDistanceATR>0.25 &&
          Target1R>0.0 && Target2R>Target1R && Target3R>Target2R &&
          MaxBarsToScan>=100 && MaxBarsToScan<=10000 &&
          MaximumDisplayPlanAgeBars>=1 && MaximumDisplayPlanAgeBars<=500 &&
          DashboardX>=0 && DashboardY>=0 &&
          StringLen(InstanceID)>=1 && StringLen(InstanceID)<=30 &&
          RiskBudgetPercent>0.0 && RiskBudgetPercent<=5.0 &&
          CommissionPerLotRoundTrip>=0.0 &&
          ManualEntryPrice>=0.0 && ManualStopPrice>=0.0 &&
          ManualTargetPrice>=0.0);
  }
int OnInit()
  {
   if(!ValidInputs())
     {Print("GSLF: invalid inputs. Please review parameter ranges.");return(INIT_PARAMETERS_INCORRECT);}
   if(!SetIndexBuffer(0,BuyArrow,INDICATOR_DATA) ||
      !SetIndexBuffer(1,SellArrow,INDICATOR_DATA) ||
      !SetIndexBuffer(2,AsiaHighLine,INDICATOR_DATA) ||
      !SetIndexBuffer(3,AsiaLowLine,INDICATOR_DATA) ||
      !SetIndexBuffer(4,BuySL,INDICATOR_DATA) ||
      !SetIndexBuffer(5,SellSL,INDICATOR_DATA) ||
      !SetIndexBuffer(6,BuyTP1,INDICATOR_DATA) ||
      !SetIndexBuffer(7,SellTP1,INDICATOR_DATA) ||
      !SetIndexBuffer(8,BuyTP2,INDICATOR_DATA) ||
      !SetIndexBuffer(9,SellTP2,INDICATOR_DATA) ||
      !SetIndexBuffer(10,BuyTP3,INDICATOR_DATA) ||
      !SetIndexBuffer(11,SellTP3,INDICATOR_DATA) ||
      !SetIndexBuffer(12,Quality,INDICATOR_DATA) ||
      !SetIndexBuffer(13,LowSweepMark,INDICATOR_DATA) ||
      !SetIndexBuffer(14,HighSweepMark,INDICATOR_DATA) ||
      !SetIndexBuffer(15,BreakUpMark,INDICATOR_DATA) ||
      !SetIndexBuffer(16,BreakDownMark,INDICATOR_DATA))
     {Print("GSLP: SetIndexBuffer failed");return(INIT_FAILED);}
   ArraySetAsSeries(BuyArrow,true);ArraySetAsSeries(SellArrow,true);
   ArraySetAsSeries(AsiaHighLine,true);ArraySetAsSeries(AsiaLowLine,true);
   ArraySetAsSeries(BuySL,true);ArraySetAsSeries(SellSL,true);
   ArraySetAsSeries(BuyTP1,true);ArraySetAsSeries(SellTP1,true);
   ArraySetAsSeries(BuyTP2,true);ArraySetAsSeries(SellTP2,true);
   ArraySetAsSeries(BuyTP3,true);ArraySetAsSeries(SellTP3,true);
   ArraySetAsSeries(Quality,true);
   ArraySetAsSeries(LowSweepMark,true);ArraySetAsSeries(HighSweepMark,true);
   ArraySetAsSeries(BreakUpMark,true);ArraySetAsSeries(BreakDownMark,true);
   for(int j=0;j<17;j++)
     {
      PlotIndexSetDouble(j,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      if(j>=4 && j<=12) PlotIndexSetInteger(j,PLOT_DRAW_TYPE,DRAW_NONE);
     }
   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(13,PLOT_ARROW,159); // swept low marker
   PlotIndexSetInteger(14,PLOT_ARROW,159); // swept high marker
   PlotIndexSetInteger(15,PLOT_ARROW,233); // structure break up
   PlotIndexSetInteger(16,PLOT_ARROW,234); // structure break down
   if(!ShowExperimentalSignals)
     {
      PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_NONE);
     }
   if(!ShowLiquiditySweeps)
     {
      PlotIndexSetInteger(13,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetInteger(14,PLOT_DRAW_TYPE,DRAW_NONE);
     }
   if(!ShowStructureBreaks)
     {
      PlotIndexSetInteger(15,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetInteger(16,PLOT_DRAW_TYPE,DRAW_NONE);
     }
   if(!ShowAsianRange)
     {
      PlotIndexSetInteger(2,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetInteger(3,PLOT_DRAW_TYPE,DRAW_NONE);
     }
   PlotIndexSetString(4,PLOT_LABEL,"Buy SL");
   PlotIndexSetString(5,PLOT_LABEL,"Sell SL");
   PlotIndexSetString(6,PLOT_LABEL,"Buy TP1");
   PlotIndexSetString(7,PLOT_LABEL,"Sell TP1");
   PlotIndexSetString(8,PLOT_LABEL,"Buy TP2");
   PlotIndexSetString(9,PLOT_LABEL,"Sell TP2");
   PlotIndexSetString(10,PLOT_LABEL,"Buy TP3");
   PlotIndexSetString(11,PLOT_LABEL,"Sell TP3");
   PlotIndexSetString(12,PLOT_LABEL,"Signal Quality 0..100");
   IndicatorSetString(INDICATOR_SHORTNAME,"Gold Session Liquidity Free MT5 [v1.10]");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   g_fastHandle=iMA(_Symbol,TrendTimeframe,TrendFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowHandle=iMA(_Symbol,TrendTimeframe,TrendSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   if(g_fastHandle==INVALID_HANDLE || g_slowHandle==INVALID_HANDLE)
     {Print("GSLP: EMA handle failed");return(INIT_FAILED);}
   g_lastOpening=0;g_lastAlert=0;
   g_prefix="GSLF_"+InstanceID+"_";
   ObjectsDeleteAll(0,g_prefix);
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,g_prefix);
   if(g_fastHandle!=INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle!=INVALID_HANDLE) IndicatorRelease(g_slowHandle);
  }
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],
                const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   ArraySetAsSeries(time,true);ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);ArraySetAsSeries(spread,true);
   const int minimum=(int)MathMax(120,
             MathMax(MaxSwingAge+SwingStrength+5,
             MathMax(MeanTrueRangePeriod+MSSConfirmBars+3,StructureLookback+MSSConfirmBars+3)));
   if(rates_total<minimum)
     {
      ClearEverything();
      g_lastOpening=0;
      return(0);
     }
   bool full=(prev_calculated<=0 || prev_calculated>rates_total || g_lastOpening==0);
   const bool newbar=(time[0]!=g_lastOpening);
   if(!full && !newbar && rates_total!=prev_calculated) full=true;
   if(!full && !newbar) return(rates_total);
   int added=0;
   if(!full)
     {
      added=NewlyClosed(rates_total,time);
      if(added<1) full=true;
     }
   if(!PrepareTrend(rates_total,time))
      return(0); // Wait for H1/H4 history, not a provisional score.
   if(full) ClearEverything();
   const int maximum=(int)MathMin(MaxBarsToScan,rates_total-2*SwingStrength-2);
   const int start=full?maximum:(int)MathMin(added,maximum);
   for(int i=start;i>=1;i--)
     {
      if(IsStopped()) return(0);
      CalculateClosedBar(i,rates_total,time,open,high,low,close,spread);
     }
   if(!full)
     {
      const int oldEnd=(int)MathMin(rates_total-1,maximum+added);
      for(int i=maximum+1;i<=oldEnd;i++) ClearBar(i);
     }
   ClearBar(0); // Zero current-candle arrows, stops, targets, and score.
   if(ShowAsianRange)
     {
      double ah,al;
      if(CompletedAsianRange(0,rates_total,time,high,low,ah,al))
        {AsiaHighLine[0]=ah;AsiaLowLine[0]=al;}
     }
   UpdatePanel(rates_total,time,close,high,low,spread);
   UpdateTradeLines(rates_total,time,close);
   // No startup alerts, reattach alerts, or multi-candle catch-up spam.
   if(!full && newbar && added==1) AlertOnFreshClosedBar(time);
   g_lastOpening=time[0];
   return(rates_total);
  }
//+------------------------------------------------------------------+
