//+------------------------------------------------------------------+
//|                                          ICT_IRL_ERL_FVG_EA.mq5   |
//|                                                       IA Trading  |
//|  Expert Advisor MetaTrader 5 — Stratégie ICT automatisée         |
//|                                                                  |
//|  Concepts : IRL->ERL | FVG H4/M15 | 50% Premium/Discount | KZ    |
//|  Plan de trade :                                                 |
//|   1. FVG H4 dans le sens du biais.                               |
//|   2. Tap de la zone H4.                                          |
//|   3. FVG M15 même sens, en Killzone, du bon côté du 50%.         |
//|   4. Ordre LIMIT au bord du FVG M15, SL sous/au-dessus du FVG,   |
//|      RR 1:2.                                                     |
//|   5. À 1R : Break Even + prise partielle 25%.                    |
//|   6. Viser 2R (liquidité externe / ERL).                        |
//|                                                                  |
//|  IMPORTANT : tester d'abord sur COMPTE DÉMO. Le trading comporte  |
//|  un risque de perte en capital.                                  |
//+------------------------------------------------------------------+
#property copyright "IA Trading"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;
COrderInfo     ordInfo;

//====================================================================
//  INPUTS
//====================================================================
input group "== Général =="
input long    InpMagic            = 20260711;   // Magic number (identifiant de l'EA)
input bool    InpTradingEnabled   = false;      // Trading auto activé (false = ALERTE SEULE)
input int     InpMaxSpreadPoints  = 40;         // Spread max autorisé (points, 0 = off)
input string  InpComment          = "ICT_FVG";  // Commentaire des ordres

input group "== Alertes Telegram =="
input bool    InpUseTelegram      = true;       // Envoyer les alertes sur Telegram
input string  InpTgToken          = "";         // Token du bot (@BotFather)
input string  InpTgChatId         = "";         // Chat ID (getUpdates)
input bool    InpTgTestOnInit     = true;       // Envoyer un message test au démarrage
input bool    InpUsePush          = false;      // Aussi notifier l'app MT5 (SendNotification)

input group "== Biais / Tendance (H4) =="
enum ENUM_BIAS_MODE { BIAS_STRUCTURE=0, BIAS_EMA=1 };
input ENUM_BIAS_MODE InpBiasMode  = BIAS_STRUCTURE; // Méthode de biais
input int     InpPivotLen         = 5;          // Longueur pivots (structure BOS)
input int     InpEmaPeriod        = 50;         // Période EMA (mode EMA)

input group "== Fair Value Gaps =="
input bool    InpUseDisplacement  = true;       // Exiger un déplacement (bougie centrale directionnelle)
input double  InpMinGapATR        = 0.0;        // Taille min. du FVG (x ATR14, 0 = off)

input group "== Premium / Discount (50%) =="
input bool    InpUsePremDisc      = true;       // Filtrer par Premium/Discount

input group "== Killzones (heure SERVEUR du broker) =="
input bool    InpUseLondon        = true;       // London KZ
input int     InpLondonStart      = 9;          // London début (heure serveur)
input int     InpLondonEnd        = 12;         // London fin
input bool    InpUseNYAM          = true;       // New York AM KZ
input int     InpNYAMStart        = 14;         // NY AM début (heure serveur)
input int     InpNYAMEnd          = 17;         // NY AM fin
input bool    InpUseNYPM          = false;      // New York PM KZ
input int     InpNYPMStart        = 19;         // NY PM début (heure serveur)
input int     InpNYPMEnd          = 21;         // NY PM fin

input group "== Gestion du risque =="
input double  InpRiskPercent      = 1.0;        // Risque par trade (% du solde)
input double  InpRR               = 2.0;        // Ratio Risque/Rendement (TP2)
input double  InpTP1_R            = 1.0;        // Niveau TP1 partiel (en R)
input double  InpPartialPct       = 25.0;       // % pris au TP1
input bool    InpMoveBE           = true;       // Passer en Break Even après TP1
enum ENUM_BUFFER_MODE { BUF_ATR=0, BUF_POINTS=1 };
input ENUM_BUFFER_MODE InpBufferMode = BUF_ATR; // Buffer du stop
input double  InpBufferATR        = 0.10;       // Buffer stop (x ATR14)
input int     InpBufferPoints     = 20;         // Buffer stop (points)
input int     InpExpiryBars       = 12;         // Expiration ordre limit (bougies M15)

input group "== Divers =="
input bool    InpShowPanel        = true;       // Afficher le panneau d'info
input bool    InpDrawZones        = true;       // Dessiner les zones FVG H4

//====================================================================
//  ÉTAT GLOBAL
//====================================================================
int      atrHandle       = INVALID_HANDLE;
int      emaHandle       = INVALID_HANDLE;

datetime lastH4Time      = 0;
datetime lastM15Time     = 0;

// Zone H4 haussière (support / demande)
double   h4BullTop=0, h4BullBot=0;
bool     h4BullValid=false, h4BullTapped=false, h4BullUsed=false;
// Zone H4 baissière (résistance / offre)
double   h4BearTop=0, h4BearBot=0;
bool     h4BearValid=false, h4BearTapped=false, h4BearUsed=false;

// Dealing range (ERL) + biais
double   lastPH=0, lastPL=0;
int      bias=0;   // 1 haussier, -1 baissier, 0 neutre

// Ordre / position en cours
ulong    pendingTicket=0;
int      pendingBarsLeft=0;
int      pendingDir=0;       // 1 long, -1 short
ulong    posTicket=0;
bool     bePartialDone=false;
double   posEntry=0, posSL=0, posTP=0, posTP1=0;
int      posDir=0;

string   PANEL="ICT_PANEL";

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);

   atrHandle = iATR(_Symbol, PERIOD_M15, 14);
   emaHandle = iMA(_Symbol, PERIOD_H4, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(atrHandle==INVALID_HANDLE || emaHandle==INVALID_HANDLE)
     {
      Print("Erreur création des handles d'indicateurs.");
      return(INIT_FAILED);
     }

   // Récupère une éventuelle position déjà ouverte par cet EA
   AdoptExistingPosition();

   // Message test Telegram pour vérifier le câblage tout de suite
   if(InpUseTelegram && InpTgTestOnInit)
      SendTelegram("ICT EA connecte sur " + _Symbol + " (" +
                   (InpTradingEnabled ? "trading AUTO" : "ALERTE seule") + "). Pret a te prevenir.");

   Print("ICT IRL->ERL FVG EA initialisé sur ", _Symbol,
         " | Magic=", InpMagic, " | Trading=", (InpTradingEnabled?"ON":"OFF"),
         " | Telegram=", (InpUseTelegram?"ON":"OFF"));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(emaHandle!=INVALID_HANDLE) IndicatorRelease(emaHandle);
   ObjectsDeleteAll(0, "ICT_");
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // 1) Gestion de la position en cours (BE + partiel) à chaque tick
   ManageOpenPosition();

   // 2) Nouvelle bougie H4 -> maj biais, dealing range, zones FVG H4
   datetime t4 = iTime(_Symbol, PERIOD_H4, 0);
   if(t4!=lastH4Time)
     {
      lastH4Time = t4;
      OnNewH4Bar();
     }

   // 3) Nouvelle bougie M15 -> tap H4, FVG M15, évaluation setup, expiration
   datetime t15 = iTime(_Symbol, PERIOD_M15, 0);
   if(t15!=lastM15Time)
     {
      lastM15Time = t15;
      OnNewM15Bar();
     }

   if(InpShowPanel) DrawPanel();
  }

//====================================================================
//  NOUVELLE BOUGIE H4
//====================================================================
void OnNewH4Bar()
  {
   UpdateBiasAndRange();
   DetectH4FVG();
   // Invalidation (mitigation) des zones H4 par clôture H4
   double c1 = iClose(_Symbol, PERIOD_H4, 1);
   if(h4BullValid && c1 < h4BullBot) { h4BullValid=false; h4BullTapped=false; DeleteZone("ICT_H4BULL"); }
   if(h4BearValid && c1 > h4BearTop) { h4BearValid=false; h4BearTapped=false; DeleteZone("ICT_H4BEAR"); }
  }

//------------------------------------------------------------------
//  Biais (structure BOS ou EMA) + dealing range (derniers swings)
//------------------------------------------------------------------
void UpdateBiasAndRange()
  {
   // Dernier swing high / low confirmés sur H4 (pivots)
   double ph = FindLastPivot(PERIOD_H4, true,  InpPivotLen, 150);
   double pl = FindLastPivot(PERIOD_H4, false, InpPivotLen, 150);
   if(ph>0) lastPH = ph;
   if(pl>0) lastPL = pl;

   double c1 = iClose(_Symbol, PERIOD_H4, 1);

   if(InpBiasMode==BIAS_STRUCTURE)
     {
      if(lastPH>0 && c1>lastPH) bias = 1;
      if(lastPL>0 && c1<lastPL) bias = -1;
     }
   else // EMA
     {
      double emaBuf[];
      if(CopyBuffer(emaHandle, 0, 1, 1, emaBuf)==1)
        {
         if(c1>emaBuf[0]) bias = 1;
         else if(c1<emaBuf[0]) bias = -1;
        }
     }
  }

//------------------------------------------------------------------
//  Détection FVG H4 sur les 3 dernières bougies H4 clôturées
//    c1=shift3 (ancienne), c2=shift2 (centrale), c3=shift1 (récente)
//------------------------------------------------------------------
void DetectH4FVG()
  {
   double H1=iHigh(_Symbol,PERIOD_H4,3), L1=iLow(_Symbol,PERIOD_H4,3);   // c1
   double O2=iOpen(_Symbol,PERIOD_H4,2), C2=iClose(_Symbol,PERIOD_H4,2); // c2
   double H3=iHigh(_Symbol,PERIOD_H4,1), L3=iLow(_Symbol,PERIOD_H4,1);   // c3

   double minGap = MinGapSize();
   bool displBull = !InpUseDisplacement || (C2>O2);
   bool displBear = !InpUseDisplacement || (C2<O2);

   // FVG H4 haussier : Low(c3) > High(c1)
   if(L3 > H1 && (L3-H1)>=minGap && displBull)
     {
      h4BullTop=L3; h4BullBot=H1; h4BullValid=true; h4BullTapped=false; h4BullUsed=false;
      if(InpDrawZones) DrawZone("ICT_H4BULL", h4BullBot, h4BullTop, clrTeal);
     }
   // FVG H4 baissier : High(c3) < Low(c1)
   if(H3 < L1 && (L1-H3)>=minGap && displBear)
     {
      h4BearTop=L1; h4BearBot=H3; h4BearValid=true; h4BearTapped=false; h4BearUsed=false;
      if(InpDrawZones) DrawZone("ICT_H4BEAR", h4BearBot, h4BearTop, clrMaroon);
     }
  }

//====================================================================
//  NOUVELLE BOUGIE M15
//====================================================================
void OnNewM15Bar()
  {
   // Tap de la zone H4 (bougie M15 précédente)
   double hi = iHigh(_Symbol, PERIOD_M15, 1);
   double lo = iLow(_Symbol,  PERIOD_M15, 1);
   if(h4BullValid && lo<=h4BullTop && hi>=h4BullBot) h4BullTapped=true;
   if(h4BearValid && hi>=h4BearBot && lo<=h4BearTop) h4BearTapped=true;

   // Expiration / invalidation de l'ordre limit non rempli
   ManagePendingExpiry();

   // Un seul trade/ordre à la fois (n'empêche pas l'analyse, mais évite de re-signaler)
   if(HasPositionOrPending()) return;

   // Détection FVG M15 sur les 3 dernières M15 clôturées
   double H1=iHigh(_Symbol,PERIOD_M15,3), L1=iLow(_Symbol,PERIOD_M15,3);   // c1
   double O2=iOpen(_Symbol,PERIOD_M15,2), C2=iClose(_Symbol,PERIOD_M15,2); // c2
   double H3=iHigh(_Symbol,PERIOD_M15,1), L3=iLow(_Symbol,PERIOD_M15,1);   // c3

   double minGap = MinGapSize();
   bool displBull = !InpUseDisplacement || (C2>O2);
   bool displBear = !InpUseDisplacement || (C2<O2);
   bool m15Bull = (L3>H1) && ((L3-H1)>=minGap) && displBull;
   bool m15Bear = (H3<L1) && ((L1-H3)>=minGap) && displBear;

   bool inKZ = InKillzone();
   double eq = DealingEquilibrium();
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool discount = (eq>0 && price<eq);
   bool premium  = (eq>0 && price>eq);
   bool pdOkLong  = !InpUsePremDisc || discount;
   bool pdOkShort = !InpUsePremDisc || premium;

   // ---- SETUP LONG (toutes confirmations) ----
   if(bias==1 && h4BullValid && h4BullTapped && !h4BullUsed && m15Bull && inKZ && pdOkLong)
     {
      double entry = L3;                // bord d'entrée du FVG (haut du gap)
      double sl    = H1 - StopBuffer(); // juste sous le FVG (bas du gap)
      if(sl < entry)
        {
         double r   = entry - sl;
         double tp1 = entry + InpTP1_R*r;
         double tp2 = entry + InpRR*r;
         SendSetupAlert(1, entry, sl, tp1, tp2);        // ALERTE Telegram
         if(InpTradingEnabled) PlaceLimit(1, entry, sl);// trade seulement si activé
         h4BullUsed = true;                             // une alerte par zone H4
        }
     }

   // ---- SETUP SHORT (toutes confirmations) ----
   if(bias==-1 && h4BearValid && h4BearTapped && !h4BearUsed && m15Bear && inKZ && pdOkShort)
     {
      double entry = H3;                // bord d'entrée du FVG (bas du gap)
      double sl    = L1 + StopBuffer(); // juste au-dessus du FVG (haut du gap)
      if(sl > entry)
        {
         double r   = sl - entry;
         double tp1 = entry - InpTP1_R*r;
         double tp2 = entry - InpRR*r;
         SendSetupAlert(-1, entry, sl, tp1, tp2);         // ALERTE Telegram
         if(InpTradingEnabled) PlaceLimit(-1, entry, sl); // trade seulement si activé
         h4BearUsed = true;                               // une alerte par zone H4
        }
     }
  }

//====================================================================
//  ALERTES TELEGRAM
//====================================================================
string JsonEscape(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "");
   return s;
  }

bool SendTelegram(string text)
  {
   if(!InpUseTelegram) return false;
   if(InpTgToken=="" || InpTgChatId=="")
     {
      Print("Telegram non configure (token / chat_id manquant).");
      return false;
     }
   string url  = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string json = "{\"chat_id\":\"" + InpTgChatId + "\",\"text\":\"" + JsonEscape(text) +
                 "\",\"disable_web_page_preview\":true}";

   char post[];
   int total = StringToCharArray(json, post, 0, WHOLE_ARRAY, CP_UTF8);
   if(total>0) ArrayResize(post, total-1); // retire le zero terminal

   char   result[];
   string resHeaders;
   ResetLastError();
   int res = WebRequest("POST", url, "Content-Type: application/json\r\n", 5000, post, result, resHeaders);
   if(res==-1)
     {
      int err = GetLastError();
      PrintFormat("WebRequest echec (%d). Autorise l'URL https://api.telegram.org dans "
                  "Outils > Options > Expert Advisors > 'Autoriser WebRequest'.", err);
      return false;
     }
   if(res!=200)
      PrintFormat("Telegram a repondu %d : %s", res, CharArrayToString(result));
   return (res==200);
  }

//  Compose et envoie l'alerte de setup complet (texte ASCII pour eviter tout souci d'encodage)
void SendSetupAlert(int dir, double entry, double sl, double tp1, double tp2)
  {
   string d   = (dir==1) ? "LONG" : "SHORT";
   string pd  = (dir==1) ? "Discount" : "Premium";
   string txt = "SETUP " + d + " ICT - " + _Symbol + "\n";
   txt += "Toutes confirmations OK (Killzone + FVG H4 tape + FVG M15 + " + pd + ")\n";
   txt += "Entree limit : " + DoubleToString(entry, _Digits) + "\n";
   txt += "SL : " + DoubleToString(sl, _Digits) + "\n";
   txt += "TP1 (1R -> BE + " + DoubleToString(InpPartialPct,0) + "%) : " + DoubleToString(tp1, _Digits) + "\n";
   txt += "TP2 (2R) : " + DoubleToString(tp2, _Digits) + "\n";
   txt += "RR 1:" + DoubleToString(InpRR,1);

   Print(txt);
   SendTelegram(txt);
   if(InpUsePush) SendNotification(txt);
  }

//====================================================================
//  PLACEMENT DE L'ORDRE LIMIT
//====================================================================
void PlaceLimit(int dir, double entry, double sl)
  {
   // Garde-fou spread
   if(InpMaxSpreadPoints>0)
     {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread>InpMaxSpreadPoints) { Print("Spread trop élevé (", spread, "), setup ignoré."); return; }
     }

   double r  = MathAbs(entry - sl);
   if(r<=0) return;
   double tp = (dir==1) ? entry + InpRR*r : entry - InpRR*r;

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl,    _Digits);
   tp    = NormalizeDouble(tp,    _Digits);

   // Respect de la distance minimale (stops level)
   double point = _Point;
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel*point;
   double ref = (dir==1) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(MathAbs(ref-entry) < minDist)
     {
      Print("Prix limit trop proche du marché (stops level). Setup ignoré.");
      return;
     }

   double vol = CalcVolume(r);
   if(vol<=0) { Print("Volume calculé nul, setup ignoré."); return; }

   bool ok=false;
   if(dir==1) ok = trade.BuyLimit(vol, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment);
   else       ok = trade.SellLimit(vol, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment);

   if(ok)
     {
      pendingTicket   = trade.ResultOrder();
      pendingDir      = dir;
      pendingBarsLeft = InpExpiryBars;
      // Mémorise les niveaux pour la gestion post-remplissage
      posEntry=entry; posSL=sl; posTP=tp;
      posTP1 = (dir==1) ? entry + InpTP1_R*r : entry - InpTP1_R*r;
      posDir = dir;
      PrintFormat("Ordre %s LIMIT placé @ %.5f | SL %.5f | TP %.5f | vol %.2f",
                  (dir==1?"BUY":"SELL"), entry, sl, tp, vol);
     }
   else
      PrintFormat("Échec placement ordre: %d - %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

//====================================================================
//  EXPIRATION DE L'ORDRE LIMIT NON REMPLI
//====================================================================
void ManagePendingExpiry()
  {
   if(pendingTicket==0) return;
   if(!ordInfo.Select(pendingTicket)) { pendingTicket=0; return; } // déjà rempli ou supprimé

   pendingBarsLeft--;
   bool invalid = (pendingDir==1 && !h4BullValid) || (pendingDir==-1 && !h4BearValid);
   if(pendingBarsLeft<=0 || invalid)
     {
      if(trade.OrderDelete(pendingTicket))
         Print("Ordre limit expiré/invalidé -> supprimé.");
      pendingTicket=0; pendingDir=0;
     }
  }

//====================================================================
//  GESTION DE LA POSITION OUVERTE : 1R -> BE + partiel 25%
//====================================================================
void ManageOpenPosition()
  {
   // Détecte le remplissage : une position de notre magic existe ?
   if(!SelectOurPosition())
     {
      posTicket=0;
      return;
     }

   // Nouveau remplissage détecté
   if(posTicket != posInfo.Ticket())
     {
      posTicket     = posInfo.Ticket();
      bePartialDone = false;
      posDir        = (posInfo.PositionType()==POSITION_TYPE_BUY) ? 1 : -1;
      posEntry      = posInfo.PriceOpen();
      posSL         = posInfo.StopLoss();
      posTP         = posInfo.TakeProfit();
      double r      = MathAbs(posEntry - posSL);
      posTP1        = (posDir==1) ? posEntry + InpTP1_R*r : posEntry - InpTP1_R*r;
      // Marque la zone H4 comme utilisée pour éviter de re-trader la même
      if(posDir==1) h4BullUsed=true; else h4BearUsed=true;
      pendingTicket=0;
     }

   if(bePartialDone) return;

   double price = (posDir==1) ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                              : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   bool reached1R = (posDir==1) ? (price>=posTP1) : (price<=posTP1);
   if(!reached1R) return;

   // Prise partielle 25%
   double vol = posInfo.Volume();
   double part = NormalizeVolume(vol * InpPartialPct/100.0);
   if(part>0 && part<vol)
     {
      if(trade.PositionClosePartial(posTicket, part))
         PrintFormat("TP1 atteint (1R): prise partielle %.2f lots.", part);
     }

   // Passage Break Even
   if(InpMoveBE)
     {
      double be = NormalizeDouble(posEntry, _Digits);
      if(trade.PositionModify(posTicket, be, posInfo.TakeProfit()))
         Print("Stop déplacé au Break Even.");
     }

   bePartialDone = true;
  }

//====================================================================
//  OUTILS
//====================================================================
double MinGapSize()
  {
   if(InpMinGapATR<=0) return 0.0;
   double a[]; if(CopyBuffer(atrHandle,0,1,1,a)==1) return InpMinGapATR*a[0];
   return 0.0;
  }

double StopBuffer()
  {
   if(InpBufferMode==BUF_POINTS) return InpBufferPoints*_Point;
   double a[]; if(CopyBuffer(atrHandle,0,1,1,a)==1) return InpBufferATR*a[0];
   return 0.0;
  }

double DealingEquilibrium()
  {
   if(lastPH>0 && lastPL>0) return (lastPH+lastPL)/2.0;
   return 0.0;
  }

//  Position sizing par risque (% du solde) selon la distance au SL
double CalcVolume(double slDistancePrice)
  {
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent/100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0 || tickValue<=0) return 0.0;
   double lossPerLot = (slDistancePrice/tickSize)*tickValue;
   if(lossPerLot<=0) return 0.0;
   double vol = riskMoney/lossPerLot;
   return NormalizeVolume(vol);
  }

double NormalizeVolume(double vol)
  {
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   vol = MathFloor(vol/step)*step;
   if(vol<minV) vol=0.0;          // trop petit pour respecter le risque -> on ne trade pas
   if(vol>maxV) vol=maxV;
   return NormalizeDouble(vol, 2);
  }

//  Killzone par heure serveur
bool InKillzone()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   bool ok=false;
   if(InpUseLondon && h>=InpLondonStart && h<InpLondonEnd) ok=true;
   if(InpUseNYAM   && h>=InpNYAMStart   && h<InpNYAMEnd)   ok=true;
   if(InpUseNYPM   && h>=InpNYPMStart   && h<InpNYPMEnd)   ok=true;
   return ok;
  }

//  Dernier pivot confirmé (true=high, false=low) sur `tf`, len bougies de chaque côté
double FindLastPivot(ENUM_TIMEFRAMES tf, bool findHigh, int len, int lookback)
  {
   int bars = iBars(_Symbol, tf);
   int maxScan = MathMin(lookback, bars-len-1);
   for(int i=len+1; i<=maxScan; i++)
     {
      bool isPivot=true;
      double ref = findHigh ? iHigh(_Symbol,tf,i) : iLow(_Symbol,tf,i);
      for(int j=1; j<=len; j++)
        {
         if(findHigh)
           {
            if(iHigh(_Symbol,tf,i-j)>=ref || iHigh(_Symbol,tf,i+j)>=ref) { isPivot=false; break; }
           }
         else
           {
            if(iLow(_Symbol,tf,i-j)<=ref || iLow(_Symbol,tf,i+j)<=ref) { isPivot=false; break; }
           }
        }
      if(isPivot) return ref;
     }
   return 0.0;
  }

bool HasPositionOrPending()
  {
   if(SelectOurPosition()) return true;
   if(pendingTicket!=0 && ordInfo.Select(pendingTicket)) return true;
   // Scan de sécurité des ordres en attente de notre magic
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong tk=OrderGetTicket(i);
      if(ordInfo.Select(tk) && ordInfo.Magic()==InpMagic && ordInfo.Symbol()==_Symbol) return true;
     }
   return false;
  }

bool SelectOurPosition()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk=PositionGetTicket(i);
      if(posInfo.SelectByTicket(tk) && posInfo.Magic()==InpMagic && posInfo.Symbol()==_Symbol)
         return true;
     }
   return false;
  }

void AdoptExistingPosition()
  {
   if(SelectOurPosition())
     {
      posTicket = posInfo.Ticket();
      posDir    = (posInfo.PositionType()==POSITION_TYPE_BUY)?1:-1;
      posEntry  = posInfo.PriceOpen();
      posSL     = posInfo.StopLoss();
      posTP     = posInfo.TakeProfit();
      double r  = MathAbs(posEntry-posSL);
      posTP1    = (posDir==1)?posEntry+InpTP1_R*r:posEntry-InpTP1_R*r;
      bePartialDone=false;
     }
  }

//====================================================================
//  VISUEL
//====================================================================
void DrawZone(string name, double bottom, double top, color col)
  {
   datetime t1 = iTime(_Symbol, PERIOD_H4, 1);
   datetime t2 = t1 + PeriodSeconds(PERIOD_H4)*3; // la zone est étendue à droite (ray)
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,top,t2,bottom);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);
  }

void DeleteZone(string name){ if(ObjectFind(0,name)>=0) ObjectDelete(0,name); }

void DrawPanel()
  {
   string biasTxt = (bias==1)?"HAUSSIER":(bias==-1)?"BAISSIER":"NEUTRE";
   string h4Txt;
   if(bias==1)  h4Txt = h4BullValid ? (h4BullTapped?"H4 tapé":"H4 en attente") : "aucune";
   else if(bias==-1) h4Txt = h4BearValid ? (h4BearTapped?"H4 tapé":"H4 en attente") : "aucune";
   else h4Txt="-";
   double eq = DealingEquilibrium();
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   string pd = (eq<=0)?"-":(price<eq?"DISCOUNT":"PREMIUM");
   string kz = InKillzone()?"OUVERTE":"fermée";
   string state = SelectOurPosition()?"EN POSITION":(pendingTicket!=0?"ordre en attente":"flat");

   string s = "== ICT IRL->ERL FVG EA ==\n";
   s += "Symbole   : "+_Symbol+"  ("+EnumToString(PERIOD_H4)+" -> M15)\n";
   s += "Trading   : "+(InpTradingEnabled?"ON":"OFF")+"\n";
   s += "Biais     : "+biasTxt+"\n";
   s += "Zone H4   : "+h4Txt+"\n";
   s += "50%       : "+pd+"\n";
   s += "Killzone  : "+kz+"\n";
   s += "État      : "+state+"\n";
   s += "Risque    : "+DoubleToString(InpRiskPercent,1)+"%  RR 1:"+DoubleToString(InpRR,1)+"\n";
   Comment(s);
  }
//+------------------------------------------------------------------+
