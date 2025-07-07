#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade g_trade;
CSymbolInfo g_symbol;
CPositionInfo g_position;

input double InpLots = 0.1;                   // Lote inicial
input int    InpMagicNumberBase = 12345;      // Numero magico base
input int    InpMaxSpread = 30;               // Spread maximo em pontos
input double InpRiskPerTrade = 1.0;           // Risco (%) por operacao
input double InpMaxDailyLoss = 5.0;           // Perda diaria maxima (%)
input double InpMaxDrawdown = 20.0;           // Drawdown maximo (%)
input int    InpTradingStartHour = 0;         // Hora inicio trading (UTC)
input int    InpTradingEndHour = 23;          // Hora fim trading (UTC)
input int    InpUTCOffset = 0;                // Offset UTC
input int    InpSlippage = 3;                 // Slippage maximo

// Candlestick patterns
input bool InpEnableHammer = true;
input bool InpEnableInvertedHammer = true;
input bool InpEnableBullishEngulfing = true;
input bool InpEnableBearishEngulfing = true;
input bool InpEnablePiercingLine = true;
input bool InpEnableDarkCloudCover = true;
input bool InpEnableMorningStar = true;
input bool InpEnableEveningStar = true;

// Indicadores tecnicos
input int    InpFastEMAPeriod = 12;
input int    InpSlowEMAPeriod = 26;
input int    InpRSIPeriod = 14;
input int    InpStochKPeriod = 5;
input int    InpStochDPeriod = 3;
input int    InpMACDFast = 12;
input int    InpMACDSlow = 26;
input int    InpMACDSignal = 9;
input int    InpBollingerPeriod = 20;
input double InpBollingerDeviations = 2.0;

// SL/TP e trailing
input int  InpStopLossPips = 30;
input int  InpTakeProfitPips = 50;
input bool InpEnableTrailingStop = false;
input int  InpTrailingStopPips = 20;
input int  InpTrailingStepPips = 5;

// Alertas
input bool InpEnableAlerts = true;
input bool InpEnableEmailAlerts = false;
input bool InpEnablePushAlerts = false;

// Opcional
input bool InpEnableMarketRegimeDetector = false;
input int  InpADXPeriod = 14;
input bool InpEnableNewsFilter = false;

// Variaveis globais
double max_equity = 0.0;
datetime today_start = 0;
int g_magic = 0;                        // magic number por simbolo/timeframe

//--- Funcao auxiliar para saber se candle e bullish/bearish
bool Bullish(int shift){ return iClose(_Symbol,_Period,shift) > iOpen(_Symbol,_Period,shift); }
bool Bearish(int shift){ return iClose(_Symbol,_Period,shift) < iOpen(_Symbol,_Period,shift); }

//--- calcula magic number unico por simbolo e timeframe
int GetMagicNumber()
{
   uint hash=0;
   for(int i=0;i<StringLen(_Symbol);i++)
      hash = hash*33 + StringGetCharacter(_Symbol,i);
   return InpMagicNumberBase + (int)_Period*100 + (int)(hash%100);
}

bool CheckHammer(int shift)
{
   double body = MathAbs(iClose(_Symbol,_Period,shift)-iOpen(_Symbol,_Period,shift));
   double lower = MathMin(iOpen(_Symbol,_Period,shift),iClose(_Symbol,_Period,shift)) - iLow(_Symbol,_Period,shift);
   double upper = iHigh(_Symbol,_Period,shift) - MathMax(iOpen(_Symbol,_Period,shift),iClose(_Symbol,_Period,shift));
   if(lower >= 2*body && upper <= body*0.5)
      return true;
   return false;
}

bool CheckInvertedHammer(int shift)
{
   double body = MathAbs(iClose(_Symbol,_Period,shift)-iOpen(_Symbol,_Period,shift));
   double upper = iHigh(_Symbol,_Period,shift) - MathMax(iOpen(_Symbol,_Period,shift),iClose(_Symbol,_Period,shift));
   double lower = MathMin(iOpen(_Symbol,_Period,shift),iClose(_Symbol,_Period,shift)) - iLow(_Symbol,_Period,shift);
   if(upper >= 2*body && lower <= body*0.5)
      return true;
   return false;
}

bool CheckBullishEngulfing(int shift)
{
   if(Bearish(shift+1) && Bullish(shift) &&
      iOpen(_Symbol,_Period,shift) < iClose(_Symbol,_Period,shift+1) && iClose(_Symbol,_Period,shift) > iOpen(_Symbol,_Period,shift+1))
      return true;
   return false;
}

bool CheckBearishEngulfing(int shift)
{
   if(Bullish(shift+1) && Bearish(shift) &&
      iOpen(_Symbol,_Period,shift) > iClose(_Symbol,_Period,shift+1) && iClose(_Symbol,_Period,shift) < iOpen(_Symbol,_Period,shift+1))
      return true;
   return false;
}

bool CheckPiercingLine(int shift)
{
   if(Bearish(shift+1) && Bullish(shift) &&
      iOpen(_Symbol,_Period,shift) < iLow(_Symbol,_Period,shift+1) && iClose(_Symbol,_Period,shift) > (iOpen(_Symbol,_Period,shift+1)+iClose(_Symbol,_Period,shift+1))/2)
      return true;
   return false;
}

bool CheckDarkCloudCover(int shift)
{
   if(Bullish(shift+1) && Bearish(shift) &&
      iOpen(_Symbol,_Period,shift) > iHigh(_Symbol,_Period,shift+1) && iClose(_Symbol,_Period,shift) < (iOpen(_Symbol,_Period,shift+1)+iClose(_Symbol,_Period,shift+1))/2)
      return true;
   return false;
}

bool CheckMorningStar(int shift)
{
   if(Bearish(shift+2) && MathAbs(iOpen(_Symbol,_Period,shift+1)-iClose(_Symbol,_Period,shift+1)) <= (iHigh(_Symbol,_Period,shift+1)-iLow(_Symbol,_Period,shift+1))*0.5 &&
      Bullish(shift) && iClose(_Symbol,_Period,shift) > (iOpen(_Symbol,_Period,shift+2)+iClose(_Symbol,_Period,shift+2))/2)
      return true;
   return false;
}

bool CheckEveningStar(int shift)
{
   if(Bullish(shift+2) && MathAbs(iOpen(_Symbol,_Period,shift+1)-iClose(_Symbol,_Period,shift+1)) <= (iHigh(_Symbol,_Period,shift+1)-iLow(_Symbol,_Period,shift+1))*0.5 &&
      Bearish(shift) && iClose(_Symbol,_Period,shift) < (iOpen(_Symbol,_Period,shift+2)+iClose(_Symbol,_Period,shift+2))/2)
      return true;
   return false;
}

//--- indicadores simples
bool BullIndicators()
{
   double fast = iMA(_Symbol,_Period,InpFastEMAPeriod,0,MODE_EMA,PRICE_CLOSE,0);
   double slow = iMA(_Symbol,_Period,InpSlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE,0);
   double rsi = iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,0);
   return (fast>slow && rsi>50);
}

bool BearIndicators()
{
   double fast = iMA(_Symbol,_Period,InpFastEMAPeriod,0,MODE_EMA,PRICE_CLOSE,0);
   double slow = iMA(_Symbol,_Period,InpSlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE,0);
   double rsi = iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,0);
   return (fast<slow && rsi<50);
}

bool CheckTradingSession()
{
   datetime gmt = TimeCurrent() + InpUTCOffset*3600;
   int hour = TimeHour(gmt);
   if(hour >= InpTradingStartHour && hour <= InpTradingEndHour)
      return true;
   return false;
}

//--- calcula perda de hoje
double GetTodayLoss()
{
   if(today_start==0)
      today_start = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(TimeCurrent() - today_start >= 86400)
   {
      today_start = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
      max_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   double loss = 0.0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      datetime dtime = (datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      if(dtime < today_start) break;
      double profit = HistoryDealGetDouble(ticket,DEAL_PROFIT);
      if(profit<0) loss += -profit;
   }
   return loss;
}

bool RiskLimitsOK()
{
   if(max_equity==0) max_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(AccountInfoDouble(ACCOUNT_EQUITY)>max_equity) max_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = (max_equity-AccountInfoDouble(ACCOUNT_EQUITY))/max_equity*100.0;
   double today_loss = GetTodayLoss()/AccountBalance()*100.0;
   if(drawdown>InpMaxDrawdown || today_loss>InpMaxDailyLoss)
      return false;
   return true;
}

//--- verifica regime de mercado utilizando ADX
bool MarketRegimeOK()
{
   if(!InpEnableMarketRegimeDetector)
      return true;
   double adx = iADX(_Symbol, _Period, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, 0);
   return (adx >= 25.0);
}

//--- filtro de noticias (placeholder)
bool CheckNewsFilter()
{
   if(!InpEnableNewsFilter)
      return true;
   // Implementar leitura de calendario economico conforme necessario
   return true;
}

//--- calcula lote baseado no risco
double CalculateLot()
{
   double tick_val = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double lot_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double risk = AccountBalance()*InpRiskPerTrade/100.0;
   double sl_value = InpStopLossPips*_Point / SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE) * tick_val;
   double volume = risk/sl_value;
   volume = MathFloor(volume/lot_step)*lot_step;
   if(volume<g_symbol.VolumeMin()) volume=g_symbol.VolumeMin();
   if(volume>g_symbol.VolumeMax()) volume=g_symbol.VolumeMax();
   if(volume<=0) volume=InpLots;
   return volume;
}

//--- abre posicao
bool OpenPosition(bool buy)
{
   double price = buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = buy ? price - InpStopLossPips*_Point : price + InpStopLossPips*_Point;
   double tp = buy ? price + InpTakeProfitPips*_Point : price - InpTakeProfitPips*_Point;
   double lot = CalculateLot();
   g_trade.SetExpertMagicNumber(g_magic);
   g_trade.SetSlippage(InpSlippage);
   bool res = buy ? g_trade.Buy(lot,_Symbol,price,sl,tp,"ManusAI") :
                    g_trade.Sell(lot,_Symbol,price,sl,tp,"ManusAI");
   if(res)
   {
      if(InpEnableAlerts) Alert("ManusAI ordem aberta: ", buy?"BUY":"SELL");
      if(InpEnableEmailAlerts) SendMail("ManusAI","Ordem aberta");
      if(InpEnablePushAlerts) SendNotification("ManusAI ordem aberta");
   }
   return res;
}

void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Magic()==g_magic && g_position.Symbol()==_Symbol)
         {
            if(InpEnableTrailingStop)
            {
               double price = g_position.PositionType()==POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
               double sl = g_position.StopLoss();
               double new_sl = sl;
               if(g_position.PositionType()==POSITION_TYPE_BUY)
               {
                  double level = price - InpTrailingStopPips*_Point;
                  if(level>sl+InpTrailingStepPips*_Point) new_sl=level;
               }
               else
               {
                  double level = price + InpTrailingStopPips*_Point;
                  if(level<sl-InpTrailingStepPips*_Point) new_sl=level;
               }
               if(new_sl!=sl)
                  g_trade.PositionModify(g_position.Ticket(),new_sl,g_position.TakeProfit());
            }
         }
      }
   }
}

bool EntryBuy()
{
   if(InpEnableBullishEngulfing && CheckBullishEngulfing(1) && BullIndicators()) return true;
   if(InpEnableHammer && CheckHammer(1) && BullIndicators()) return true;
   if(InpEnablePiercingLine && CheckPiercingLine(1) && BullIndicators()) return true;
   if(InpEnableMorningStar && CheckMorningStar(1) && BullIndicators()) return true;
   return false;
}

bool EntrySell()
{
   if(InpEnableBearishEngulfing && CheckBearishEngulfing(1) && BearIndicators()) return true;
   if(InpEnableInvertedHammer && CheckInvertedHammer(1) && BearIndicators()) return true;
   if(InpEnableDarkCloudCover && CheckDarkCloudCover(1) && BearIndicators()) return true;
   if(InpEnableEveningStar && CheckEveningStar(1) && BearIndicators()) return true;
   return false;
}

int OnInit()
{
   g_symbol.Name(_Symbol);
   today_start = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   max_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_magic = GetMagicNumber();
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!CheckTradingSession()) return;
   if(g_symbol.Spread() > InpMaxSpread) return;
   if(!MarketRegimeOK()) return;
   if(!CheckNewsFilter()) return;
   if(!RiskLimitsOK()) return;

   ManagePositions();
   if(PositionsTotal()==0)
   {
      if(EntryBuy())
         OpenPosition(true);
      else if(EntrySell())
         OpenPosition(false);
   }
}

