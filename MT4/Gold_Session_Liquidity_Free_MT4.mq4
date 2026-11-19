//+------------------------------------------------------------------+
//| Gold Session Liquidity Free MT4 v1.10 - FXLINER                   |
//| Educational OHLC-based XAUUSD analysis / NOT a trading EA.       |
//| Historical closed-bar pivots adapted from Smart Liquidity Hunter |
//| (c) Smart Liquidity Hunter contributors, MIT; see LICENSE.txt.   |
//| No orders, no profitability claims, no hidden dependencies.       |
//+------------------------------------------------------------------+
#property strict
#property copyright "FXLINER; Smart Liquidity Hunter contributors (MIT portions)"
#property link "https://forexreview.top/"
#property version "1.10"
#property description "Free gold sessions, completed Asian High/Low, closed-bar sweeps, swing breaks and manual risk planning."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_color1 clrDarkOrange
#property indicator_color2 clrDeepSkyBlue
#property indicator_color3 clrLimeGreen
#property indicator_color4 clrTomato
#property indicator_color5 clrDodgerBlue
#property indicator_color6 clrOrange

input string Context01             = "01 | Historical sessions / UTC offset";
input int    BrokerWinterUTCOffset = 2;  // common winter UTC+2; check broker
input bool   BrokerEUDST           = true; // summer UTC+3; broker dependent
input int    AsianStartUTC         = 0;
input int    AsianEndUTC           = 6; // exclusive
input bool   ShowAsianLevels       = true;

input string Context02             = "02 | Liquidity and structure markers";
input int    SwingStrength        = 3;
input int    MaxSwingAge          = 90;
input int    MaxBarsToScan        = 900;
input int    MinSweepPoints       = 10;
input int    ATRPeriod            = 14;
input double MinSweepATR          = 0.10;
input double MinWickPercent       = 20.0;
input bool   RequireFreshLevel    = true;
input bool   ShowLiquiditySweeps  = true;
input bool   ShowStructureBreaks  = true;

input string Context03             = "03 | Dashboard and planning";
input bool   ShowDashboard        = true;
input int    DashboardX           = 14;
input int    DashboardY           = 18;
input int    TrendFastEMA         = 20;
input int    TrendSlowEMA         = 50;
input double RiskBudgetPercent    = 0.50; // planned equity risk (NOT cap on fill losses)
input double ManualEntryPrice     = 0.0;
input double ManualStopPrice      = 0.0;
input double ManualTargetPrice    = 0.0;
input double CommissionRoundTrip  = 7.00; // per lot, in account currency
input string InstanceID           = "GSLF4";
input bool   EducationalPopup     = false; // sweep notices, NOT trade signals

// Public buffer map: 0 Asia High, 1 Asia Low, 2 low sweep,
// 3 high sweep, 4 break up, 5 break down. Buffer 0 of time is never
// used to confirm marker signals. No BUY/SELL trade signal buffers.
double AsiaHigh[],AsiaLow[],SweepLow[],SweepHigh[],BreakUp[],BreakDown[];
datetime g_opened=0,g_alerted=0;
string g_prefix="";

bool ValidInputs()
{
 return (BrokerWinterUTCOffset>=-12 && BrokerWinterUTCOffset<=14 &&
         AsianStartUTC>=0 && AsianStartUTC<23 &&
         AsianEndUTC>AsianStartUTC && AsianEndUTC<=23 &&
         SwingStrength>=1 && SwingStrength<=10 &&
         MaxSwingAge>=SwingStrength+3 && MaxSwingAge<=500 &&
         MaxBarsToScan>=100 && MaxBarsToScan<=5000 &&
         MinSweepPoints>=0 && ATRPeriod>=3 && ATRPeriod<=200 &&
         MinSweepATR>=0.0 && MinWickPercent>=0.0 && MinWickPercent<=95.0 &&
         DashboardX>=0 && DashboardY>=0 &&
         TrendFastEMA>=2 && TrendSlowEMA>TrendFastEMA &&
         RiskBudgetPercent>0.0 && RiskBudgetPercent<=5.0 &&
         ManualEntryPrice>=0.0 && ManualStopPrice>=0.0 &&
         ManualTargetPrice>=0.0 && CommissionRoundTrip>=0.0 &&
         StringLen(InstanceID)>0 && StringLen(InstanceID)<=30);
}

datetime LastSunday(const int year,const int month,const int hourUTC)
{
 MqlDateTime st;ZeroMemory(st);
 st.year=year;st.mon=month;st.day=(month==3?31:31);
 st.hour=hourUTC;
 datetime v=StructToTime(st);
 return(v-86400*TimeDayOfWeek(v));
}
bool EUDaylight(const datetime utc)
{
 MqlDateTime st;TimeToStruct(utc,st);
 return(utc>=LastSunday(st.year,3,1) &&
        utc<LastSunday(st.year,10,1));
}
bool USDaylight(const datetime utc)
{
 MqlDateTime st;TimeToStruct(utc,st);
 MqlDateTime march;ZeroMemory(march);
 march.year=st.year;march.mon=3;march.day=1;march.hour=7;
 datetime first=StructToTime(march);
 int skip=(7-TimeDayOfWeek(first))%7;
 datetime secondSunday=first+86400*(skip+7);
 MqlDateTime nov;ZeroMemory(nov);
 nov.year=st.year;nov.mon=11;nov.day=1;nov.hour=6;
 datetime november=StructToTime(nov);
 datetime firstSunday=november+86400*((7-TimeDayOfWeek(november))%7);
 return(utc>=secondSunday && utc<firstSunday);
}
datetime ServerUTC(const datetime serverTime)
{
 const datetime winterEstimate=(datetime)(serverTime-3600*BrokerWinterUTCOffset);
 const int summer=(BrokerEUDST && EUDaylight(winterEstimate))?1:0;
 return((datetime)(serverTime-3600*(BrokerWinterUTCOffset+summer)));
}
string SessionLabel(const datetime utc)
{
 MqlDateTime dt;TimeToStruct(utc,dt);
 const int h=dt.hour;
 const bool london=(h >= (EUDaylight(utc)?7:8) &&
                    h < (EUDaylight(utc)?16:17));
 const bool ny=(h >= (USDaylight(utc)?12:13) &&
                h < (USDaylight(utc)?21:22));
 const bool asia=(h>=AsianStartUTC && h<AsianEndUTC);
 if(london&&ny)return("LONDON + NEW YORK");
 if(london)return("LONDON");
 if(ny)return("NEW YORK");
 if(asia)return("ASIA");
 return("OFF-SESSION");
}

// Asian High/Low exist only once that day's range is fully finished.
// At older historical candles, do not inspect future candles.
bool CompletedAsianRange(const int i,const int bars,const datetime &time[],
                         const double &high[],const double &low[],
                         double &ah,double &al)
{
 const datetime utc=ServerUTC(time[i]);
 MqlDateTime dt;TimeToStruct(utc,dt);
 dt.hour=0;dt.min=0;dt.sec=0;
 datetime midnight=StructToTime(dt);
 datetime start=(datetime)(midnight+AsianStartUTC*3600);
 datetime end=(datetime)(midnight+AsianEndUTC*3600);
 if(utc<end)return(false);
 ah=-DBL_MAX;al=DBL_MAX;
 int found=0;
 const int maxBack=(int)MathMin(bars-1,i+1800);
 for(int j=i;j<=maxBack;j++)
 {
  const datetime t=ServerUTC(time[j]);
  if(t<start)break;
  if(t>=start && t<end)
  {
   ah=MathMax(ah,high[j]);al=MathMin(al,low[j]);
   found++;
  }
 }
 return(found>0 && ah>al && al>0);
}
bool IsPivot(const bool highSide,const int j,const int bars,
             const double &h[],const double &l[])
{
 if(j-SwingStrength<1 || j+SwingStrength>=bars)return(false);
 for(int n=1;n<=SwingStrength;n++)
 {
  if(highSide)
  {
   if(h[j]<=h[j-n] || h[j]<h[j+n])return(false);
  }
  else
  {
   if(l[j]>=l[j-n] || l[j]>l[j+n])return(false);
  }
 }
 return(true);
}
int ConfirmedPivot(const bool highSide,const int i,const int bars,
                   const double &h[],const double &l[])
{
 const int first=i+SwingStrength+1;
 const int last=(int)MathMin(i+MaxSwingAge,bars-SwingStrength-1);
 for(int j=first;j<=last;j++)
 {
  if(!IsPivot(highSide,j,bars,h,l))continue;
  bool fresh=true;
  if(RequireFreshLevel)
   for(int k=i+1;k<j;k++)
   {
    if(highSide && h[k]>h[j]+0.01*_Point) {fresh=false;break;}
    if(!highSide && l[k]<l[j]-0.01*_Point){fresh=false;break;}
   }
  if(fresh)return(j);
 }
 return(-1);
}
double HistoricalTR(const int i,const int bars,const double &h[],
                    const double &l[],const double &c[])
{
 if(i+ATRPeriod+1>=bars)return(-1.0);
 double sum=0;
 for(int k=i+1;k<=i+ATRPeriod;k++)
 {
  const double a=h[k]-l[k];
  const double b=MathAbs(h[k]-c[k+1]);
  const double d=MathAbs(l[k]-c[k+1]);
  sum+=MathMax(a,MathMax(b,d));
 }
 return(sum/ATRPeriod);
}
void ClearBar(const int i)
{
 AsiaHigh[i]=EMPTY_VALUE;AsiaLow[i]=EMPTY_VALUE;
 SweepLow[i]=EMPTY_VALUE;SweepHigh[i]=EMPTY_VALUE;
 BreakUp[i]=EMPTY_VALUE;BreakDown[i]=EMPTY_VALUE;
}
void Analyze(const int i,const int bars,const datetime &time[],
             const double &o[],const double &h[],
             const double &l[],const double &c[])
{
 ClearBar(i);
 if(ShowAsianLevels)
 {
  double ah=0,al=0;
  if(CompletedAsianRange(i,bars,time,h,l,ah,al))
   {AsiaHigh[i]=ah;AsiaLow[i]=al;}
 }
 if(i==0)return;
 const double atr=HistoricalTR(i,bars,h,l,c);
 if(atr<=0)return;
 const int highPivot=ConfirmedPivot(true,i,bars,h,l);
 const int lowPivot=ConfirmedPivot(false,i,bars,h,l);
 const double minimum=MathMax(MinSweepPoints*_Point,MinSweepATR*atr);
 const double range=h[i]-l[i];
 if(range<=0)return;
 const bool sweepBuy=ShowLiquiditySweeps && lowPivot>=0 &&
        l[i]<l[lowPivot]-minimum && c[i]>l[lowPivot] &&
        (MathMin(o[i],c[i])-l[i])/range*100.0>=MinWickPercent;
 const bool sweepSell=ShowLiquiditySweeps && highPivot>=0 &&
        h[i]>h[highPivot]+minimum && c[i]<h[highPivot] &&
        (h[i]-MathMax(o[i],c[i]))/range*100.0>=MinWickPercent;
 const double offset=MathMax(8*_Point,0.18*atr);
 if(sweepBuy && !sweepSell)SweepLow[i]=l[i]-offset;
 if(sweepSell && !sweepBuy)SweepHigh[i]=h[i]+offset;
 if(ShowStructureBreaks)
 {
  if(highPivot>=0 && c[i]>h[highPivot]+2*_Point &&
     c[i+1]<=h[highPivot]+2*_Point)
      BreakUp[i]=l[i]-offset*1.7;
  if(lowPivot>=0 && c[i]<l[lowPivot]-2*_Point &&
     c[i+1]>=l[lowPivot]-2*_Point)
      BreakDown[i]=h[i]+offset*1.7;
 }
}
string MoneyRisk()
{
 const double eq=AccountEquity();
 if(eq<=0)return("RISK: account equity unavailable");
 return("PLANNED RISK: "+DoubleToString(RiskBudgetPercent,2)+
        "% = "+DoubleToString(eq*RiskBudgetPercent/100.0,2)+" "+AccountCurrency());
}
string ManualLot()
{
 if(ManualEntryPrice<=0 || ManualStopPrice<=0 ||
    MathAbs(ManualEntryPrice-ManualStopPrice)<_Point)
    return("LOT: set ManualEntryPrice & ManualStopPrice");
 const double eq=AccountEquity();
 const double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
 const double tickPoints=MarketInfo(Symbol(),MODE_TICKSIZE);
 const double step=MarketInfo(Symbol(),MODE_LOTSTEP);
 const double minLots=MarketInfo(Symbol(),MODE_MINLOT);
 const double maxLots=MarketInfo(Symbol(),MODE_MAXLOT);
 if(eq<=0 || tickValue<=0 || tickPoints<=0 ||
    step<=0 || minLots<=0 || maxLots<minLots)
   return("LOT: broker tick/contract data unavailable");
 const bool buy=ManualEntryPrice>ManualStopPrice;
 const double distance=MathAbs(ManualEntryPrice-ManualStopPrice);
 const double perLot=(distance/(_Point*tickPoints))*tickValue+
                     CommissionRoundTrip;
 if(perLot<=0)return("LOT: invalid nominal stop value");
 const double budget=eq*RiskBudgetPercent/100.0;
 const double lots=NormalizeDouble(MathFloor(MathMin(maxLots,budget/perLot)/step+
                                            1e-9)*step,8);
 if(lots<minLots-1e-9)return("LOT: broker minimum exceeds risk budget");
 const double risk=lots*perLot;
 const double reward=buy?(ManualTargetPrice-ManualEntryPrice):
                           (ManualEntryPrice-ManualTargetPrice);
 string ratio="";
 if(ManualTargetPrice>0 && reward>0)
     ratio=" | price R:R "+DoubleToString(reward/distance,2);
 return("LOT "+DoubleToString(lots,2)+(buy?" BUY":" SELL")+
        " | nominal SL "+DoubleToString(risk,2)+" "+AccountCurrency()+ratio);
}
void PanelText(const string suffix,const string value,const int row,
               const color ink,const int font)
{
 const string name=g_prefix+suffix;
 if(ObjectFind(0,name)<0)
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))return;
 ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
 ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DashboardX+11);
 ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardY+12+19*row);
 ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
 ObjectSetInteger(0,name,OBJPROP_FONTSIZE,font);
 ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
 ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
 ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
 ObjectSetString(0,name,OBJPROP_TEXT,value);
}
void PanelUpdate(const int bars,const datetime &time[],
                 const double &h[],const double &l[],const double &c[])
{
 if(!ShowDashboard)return;
 string bg=g_prefix+"BACKGROUND";
 if(ObjectFind(0,bg)<0)ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
 ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
 ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,DashboardX);
 ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,DashboardY);
 ObjectSetInteger(0,bg,OBJPROP_XSIZE,580);
 ObjectSetInteger(0,bg,OBJPROP_YSIZE,220);
 ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrMidnightBlue);
 ObjectSetInteger(0,bg,OBJPROP_COLOR,clrSteelBlue);
 ObjectSetInteger(0,bg,OBJPROP_BACK,false);
 ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
 ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
 const datetime utc=ServerUTC(time[0]);
 string tf=EnumToString((ENUM_TIMEFRAMES)_Period);
 StringReplace(tf,"PERIOD_","");
 PanelText("A","GOLD SESSION LIQUIDITY FREE MT4  v1.10",0,clrDeepSkyBlue,11);
 PanelText("B",Symbol()+" "+tf+" | "+SessionLabel(utc)+" | UTC "+
           TimeToString(utc,TIME_DATE|TIME_MINUTES),1,clrWhite,9);
 int sh=iBarShift(Symbol(),PERIOD_H1,time[1],false);
 string direction="WAITING";
 if(sh>=0)
 {
  double fast=iMA(Symbol(),PERIOD_H1,TrendFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
  double slow=iMA(Symbol(),PERIOD_H1,TrendSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
  if(fast>0 && slow>0)
    direction=fast>slow?"UP":(fast<slow?"DOWN":"FLAT");
 }
 const int spread=(int)MarketInfo(Symbol(),MODE_SPREAD);
 PanelText("C","H1 EMA "+IntegerToString(TrendFastEMA)+"/"+
           IntegerToString(TrendSlowEMA)+" "+direction+" | spread "+
           IntegerToString(spread)+" pt",2,clrWhite,9);
 string asia="ASIA H/L: awaiting finished range";
 if(AsiaHigh[0]!=EMPTY_VALUE && AsiaLow[0]!=EMPTY_VALUE)
    asia="ASIA H "+DoubleToString(AsiaHigh[0],_Digits)+
         " | L "+DoubleToString(AsiaLow[0],_Digits);
 PanelText("D",asia,3,clrWhite,9);
 string sweep="SWEEP: no recent closed-bar event";
 string structure="STRUCTURE: no recent confirmed break";
 for(int i=1;i<=MathMin(bars-1,96);i++)
 {
  if(sweep=="SWEEP: no recent closed-bar event")
  {
   if(SweepLow[i]!=EMPTY_VALUE)
      sweep="SWEEP LOW reclaimed | "+TimeToString(time[i],TIME_DATE|TIME_MINUTES);
   else if(SweepHigh[i]!=EMPTY_VALUE)
      sweep="SWEEP HIGH rejected | "+TimeToString(time[i],TIME_DATE|TIME_MINUTES);
  }
  if(structure=="STRUCTURE: no recent confirmed break")
  {
   if(BreakUp[i]!=EMPTY_VALUE)
      structure="SWING BREAK UP | "+TimeToString(time[i],TIME_DATE|TIME_MINUTES);
   else if(BreakDown[i]!=EMPTY_VALUE)
      structure="SWING BREAK DOWN | "+TimeToString(time[i],TIME_DATE|TIME_MINUTES);
  }
 }
 PanelText("E",sweep,4,clrLimeGreen,9);
 PanelText("F",structure,5,clrDeepSkyBlue,9);
 PanelText("G",MoneyRisk(),6,clrWhite,9);
 PanelText("H",ManualLot(),7,clrWhite,9);
 PanelText("I","FOREXREVIEW.TOP | OHLC sweep proxy | no BUY/SELL signals",8,clrSilver,8);
 PanelText("J","Stops can gap; no proven profitable trading edge",9,clrSilver,8);
}
void DeletePanel()
{
 if(g_prefix=="")return;
 string names[11]={"BACKGROUND","A","B","C","D","E","F","G","H","I","J"};
 for(int i=0;i<11;i++)ObjectDelete(0,g_prefix+names[i]);
}
void SignalAlert(const datetime &time[])
{
 if(!EducationalPopup || time[1]==g_alerted)return;
 if(SweepLow[1]==EMPTY_VALUE && SweepHigh[1]==EMPTY_VALUE)return;
 g_alerted=time[1];
 Alert("GSLF MT4 closed-bar ",Symbol()," ",
       (SweepLow[1]!=EMPTY_VALUE?"LOW sweep":"HIGH sweep"),
       " -- educational observation only");
}
int OnInit()
{
 if(!ValidInputs())
 {
  Print("GSLF4: invalid input ranges, check Parameters");
  return(INIT_PARAMETERS_INCORRECT);
 }
 IndicatorBuffers(6);
 if(!SetIndexBuffer(0,AsiaHigh) || !SetIndexBuffer(1,AsiaLow) ||
    !SetIndexBuffer(2,SweepLow) || !SetIndexBuffer(3,SweepHigh) ||
    !SetIndexBuffer(4,BreakUp) || !SetIndexBuffer(5,BreakDown))
    return(INIT_FAILED);
 ArraySetAsSeries(AsiaHigh,true);ArraySetAsSeries(AsiaLow,true);
 ArraySetAsSeries(SweepLow,true);ArraySetAsSeries(SweepHigh,true);
 ArraySetAsSeries(BreakUp,true);ArraySetAsSeries(BreakDown,true);
 SetIndexStyle(0,ShowAsianLevels?DRAW_LINE:DRAW_NONE,STYLE_DOT,1,clrDarkOrange);
 SetIndexStyle(1,ShowAsianLevels?DRAW_LINE:DRAW_NONE,STYLE_DOT,1,clrDeepSkyBlue);
 SetIndexStyle(2,ShowLiquiditySweeps?DRAW_ARROW:DRAW_NONE,STYLE_SOLID,1,clrLimeGreen);
 SetIndexStyle(3,ShowLiquiditySweeps?DRAW_ARROW:DRAW_NONE,STYLE_SOLID,1,clrTomato);
 SetIndexStyle(4,ShowStructureBreaks?DRAW_ARROW:DRAW_NONE,STYLE_SOLID,1,clrDodgerBlue);
 SetIndexStyle(5,ShowStructureBreaks?DRAW_ARROW:DRAW_NONE,STYLE_SOLID,1,clrOrange);
 SetIndexArrow(2,233);SetIndexArrow(3,234);
 SetIndexArrow(4,233);SetIndexArrow(5,234);
 SetIndexLabel(0,"Completed Asian High");SetIndexLabel(1,"Completed Asian Low");
 SetIndexLabel(2,"Liquidity Sweep LOW");SetIndexLabel(3,"Liquidity Sweep HIGH");
 SetIndexLabel(4,"Confirmed Swing Break UP");SetIndexLabel(5,"Confirmed Swing Break DOWN");
 for(int i=0;i<6;i++)SetIndexEmptyValue(i,EMPTY_VALUE);
 IndicatorDigits(_Digits);
 IndicatorShortName("Gold Session Liquidity Free MT4 v1.10");
 g_prefix="GSLF4_"+IntegerToString((long)ChartID())+"_"+InstanceID+"_";
 g_opened=0;g_alerted=0;
 return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){DeletePanel();}
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],
                const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
 ArraySetAsSeries(time,true);ArraySetAsSeries(open,true);
 ArraySetAsSeries(high,true);ArraySetAsSeries(low,true);ArraySetAsSeries(close,true);
 const int needed=(int)MathMax(2*SwingStrength+ATRPeriod+5,
                             SwingStrength+MaxSwingAge+4);
 if(rates_total<needed)
 {
  for(int i=0;i<6;i++){}
  g_opened=0;
  return(0);
 }
 bool full=(prev_calculated<=0 || g_opened==0 || prev_calculated>rates_total);
 const bool newbar=(g_opened!=time[0]);
 if(!full && !newbar && prev_calculated==rates_total)return(rates_total);
 if(!full && !newbar && prev_calculated!=rates_total)full=true;
 int added=0;
 if(!full && newbar)
 {
  for(int i=1;i<=MathMin(MaxBarsToScan,rates_total-1);i++)
    if(time[i]==g_opened){added=i;break;}
  if(added<1)full=true;
 }
 if(full)
 {
  ArrayInitialize(AsiaHigh,EMPTY_VALUE);ArrayInitialize(AsiaLow,EMPTY_VALUE);
  ArrayInitialize(SweepLow,EMPTY_VALUE);ArrayInitialize(SweepHigh,EMPTY_VALUE);
  ArrayInitialize(BreakUp,EMPTY_VALUE);ArrayInitialize(BreakDown,EMPTY_VALUE);
 }
 const int maxscan=(int)MathMin(MaxBarsToScan,
                               rates_total-2*SwingStrength-ATRPeriod-4);
 const int start=full?maxscan:(int)MathMin(added,maxscan);
 for(int i=start;i>=1;i--)
 {
  if(IsStopped())return(0);
  Analyze(i,rates_total,time,open,high,low,close);
 }
 if(!full)
 {
  const int last=(int)MathMin(rates_total-1,maxscan+added);
  for(int i=maxscan+1;i<=last;i++)ClearBar(i);
 }
 Analyze(0,rates_total,time,open,high,low,close);
 PanelUpdate(rates_total,time,high,low,close);
 if(!full && added==1)SignalAlert(time);
 g_opened=time[0];
 return(rates_total);
}
//+------------------------------------------------------------------+
