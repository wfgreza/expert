//+------------------------------------------------------------------+
//|                                              ModularAll.mq4      |
//|                        Copyright 2024, Your Name                 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name"
#property link      "https://www.mql5.com"
#property version   "1.01"
#property strict
#property show_inputs

#include "CommonFunctions.mqh"
#include "SRStrategy.mqh"
#include "ScalpStrategy.mqh"
#include "MeasuredStrategy.mqh"

// Input parameters
input ENUM_LINE_STYLE verticalLineStyle = STYLE_DOT; // V-Line Style
input color ScalpVLineColor = clrRed;   // Scalp V-Line Color
input color MeasuredVLineColor = clrGold; // Measured V-Line Color
input color SRVLineColor = clrGreen;  // S/R V-Line Color
input int Line_Extension = 20;         // Number of candles to extend the S/R lines
input double tradingStartTime = 8.0;   // Start Time (decimal hours, e.g., 8.5 = 08:30)
input double tradingEndTime = 23.0;    // End Time (decimal hours, e.g., 23.0 = 23:00)
input int emaPeriod = 60;              // Period for EMA
input color dotColorAbove = clrGreen;  // Arrow Up Color
input color dotColorBelow = clrRed;    // Arrow Down Color
input color lineColor = clrYellow;     // EMA Color
input double firstTradeRiskPercent = 1.0; // 1st Trade Risk %
input int maxAdditionalTrades = 4;     // Max number of additional trades after first trade
input int slOffset = 1;                   // SL offset
input double maxDailyLossPercent = 5.0;   // Maximum daily loss as a percentage of account balance (0 = no restriction)
input double maxDailyGainPercent = 5.0;   // Maximum daily gain as a percentage of account balance (0 = no restriction)
input string rrrValues = "1,2,3,4,5";  // RRR values (comma-separated)
input string ScalpSetTimeArray = "10:00,14:00,16:30"; // Scalp Set Time Array
input string MeasuredSetTimeArray = "10:00,14:00,16:30"; // Measured Set Time Array
input string SRSetTimeArray = "10:00,14:00,16:30"; // S/R Set Time Array
input int MagicNumber = 12345;         // Magic Number for this EA

// Global variables
double globalEMAValue = 0;
string spreadLabelName = "CurrentSpread";
string remainingTimeObjName = "RemainingCandleTime";
datetime currentTradingDay = 0;
datetime lastVLineTime = 0;
bool tradingStarted = false;
bool isInitialized = false;
int totalOrdersOpened = 0;
double startingDailyBalance = 0;
double currentDailyLoss = 0;
double currentDailyGain = 0;
bool stopTradingForDay = false;
bool stopTradingForDayGain = false;
bool endOfDayRoutineExecuted = false;
int pendingOrdersCount = 0;
int currentTradeNumber = 0;
double rrrArray[];
bool tradesClosedForDay = false;
int tradeTickets[];
int lastOrderType = -1;
int lastOrderTicket = 0;
int lastOpenOrderTicket = 0;
int lastOpenOrderNumber = 0;
datetime lastTradeTime = 0;
int scalpSetTimeMinutes[];
int measuredSetTimeMinutes[];
int srSetTimeMinutes[];
bool isFirstDot = true;
double emaValuePrev = 0;
datetime timePrev = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if (!ParseSetTimes())
    {
        Print("Failed to parse set times. Check your input parameters.");
        return INIT_PARAMETERS_INCORRECT;
    }

    Print("SR Set Times:");
    for(int i=0; i<ArraySize(srSetTimeMinutes); i++)
    {
        Print(TimeMinutesToString(srSetTimeMinutes[i]));
    }

    Print("Scalp Set Times:");
    for(int i=0; i<ArraySize(scalpSetTimeMinutes); i++)
    {
        Print(TimeMinutesToString(scalpSetTimeMinutes[i]));
    }

    Print("Measured Set Times:");
    for(int i=0; i<ArraySize(measuredSetTimeMinutes); i++)
    {
        Print(TimeMinutesToString(measuredSetTimeMinutes[i]));
    }

    currentTradingDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    lastVLineTime = TimeCurrent() - 86400;
    ParseRRRValues();
    ResetDailyVariables();
    
    if (ArraySize(rrrArray) == 0)
    {
        Print("Error: Failed to initialize RRR values. Please check your input parameters.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (maxDailyLossPercent == 0)
        Print("Maximum daily loss restriction is disabled.");
    else
        Print("Maximum daily loss restriction set to ", maxDailyLossPercent, "% of account balance.");
    
    if (maxDailyGainPercent == 0)
        Print("Maximum daily gain restriction is disabled.");
    else
        Print("Maximum daily gain restriction set to ", maxDailyGainPercent, "% of account balance.");
    
    Print("Maximum additional trades set to ", maxAdditionalTrades);
    
    CreateSpreadLabel();

    isInitialized = true;
    Print("EA initialized. Ready to start trading.");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectDelete(0, spreadLabelName);
    ObjectDelete(0, remainingTimeObjName);
    Print("Expert Advisor deinitialized. Reason code: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    UpdateSpreadLabel();
UpdateRemainingTimeLabel();
    
    datetime currentTime = TimeCurrent();
    
    static datetime lastCandleTime = 0;
    datetime currentCandleTime = iTime(Symbol(), Period(), 0);
    
    // Check if a new candle has formed
    if (currentCandleTime != lastCandleTime)
    {
        lastCandleTime = currentCandleTime;
        UpdateFirstPendingOrder();
    }

    // Check if we've reached the start time
    if (!tradingStarted && TimeHour(currentTime) >= (int)tradingStartTime)
    {
        tradingStarted = true;
        Print("Trading day started at ", TimeToString(currentTime));
    }

    HandleEndOfDay();
    
    if (IsNewDay())
    {
        ResetDailyVariables();
        DeletePendingOrders();
    }

    DrawVerticalLines();
    
    if (IsWithinTradingHours())
    {
        CheckMaxDailyLossAndGain();

        if (isInitialized && tradingStarted && !stopTradingForDay)
        {
            Measured_OnTick();
            CheckAndExecuteStrategies();
        }
    }
    
    DrawEMADotsAndLines();
    UpdateRemainingTimeLabel();
}

//+------------------------------------------------------------------+
//| Check and execute strategies                                     |
//+------------------------------------------------------------------+
void CheckAndExecuteStrategies()
{
    datetime currentTime = TimeCurrent();
    int currentMinutes = (int)TimeHour(currentTime) * 60 + (int)TimeMinute(currentTime);

    // Check SR Strategy
    for (int i = 0; i < ArraySize(srSetTimeMinutes); i++)
    {
        if (currentMinutes == srSetTimeMinutes[i])
        {
            if (IsEATradeAllowed())
            {
                Print("Executing SR Strategy at ", TimeToString(currentTime));
                ExecuteSRStrategy();
            }
            break;
        }
    }

    // Check Scalp Strategy
    for (int i = 0; i < ArraySize(scalpSetTimeMinutes); i++)
    {
        if (currentMinutes == scalpSetTimeMinutes[i])
        {
            if (IsEATradeAllowed())
            {
                Print("Executing Scalp Strategy at ", TimeToString(currentTime));
                ExecuteScalpStrategy();
            }
            break;
        }
    }

    // Check Measured Strategy
    for (int i = 0; i < ArraySize(measuredSetTimeMinutes); i++)
    {
        if (currentMinutes == measuredSetTimeMinutes[i])
        {
            if (IsEATradeAllowed())
            {
                Print("Executing Measured Strategy at ", TimeToString(currentTime));
                Measured_ExecuteStrategy();
            }
            break;
        }
    }

    // Check for ongoing SR strategy actions
    if (AreSRLinesActive())
    {
        HandleOpenSRStrategy();
    }
}

//+------------------------------------------------------------------+
//| Draw vertical lines for all strategies                           |
//+------------------------------------------------------------------+
void DrawVerticalLines()
{
    DrawStrategyLines(srSetTimeMinutes, SRVLineColor, "SR");
    DrawStrategyLines(scalpSetTimeMinutes, ScalpVLineColor, "Scalp");
    DrawStrategyLines(measuredSetTimeMinutes, MeasuredVLineColor, "Measured");
}

void DrawStrategyLines(const int& setTimeMinutes[], color strategyLineColor, string strategyName)
{
    datetime currentTime = TimeCurrent();
    datetime currentDate = StringToTime(TimeToString(currentTime, TIME_DATE));

    for (int i = 0; i < ArraySize(setTimeMinutes); i++)
    {
        datetime lineTime = currentDate + setTimeMinutes[i] * 60;
        if (currentTime >= lineTime && lastVLineTime < lineTime)
        {
            string lineName = strategyName + "_VLine_" + TimeToString(lineTime, TIME_DATE|TIME_MINUTES);
            if (ObjectCreate(0, lineName, OBJ_VLINE, 0, lineTime, 0))
            {
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, strategyLineColor);
                ObjectSetInteger(0, lineName, OBJPROP_STYLE, verticalLineStyle);
                ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
                lastVLineTime = lineTime;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Draw EMA dots and lines                                          |
//+------------------------------------------------------------------+
void DrawEMADotsAndLines()
{
    if (!IsWithinTradingHours()) return;

    static datetime lastCandleTime = 0;
    datetime currentCandleTime = iTime(NULL, 0, 0);

    // Delete previous dot if it's a new candle
    if (currentCandleTime != lastCandleTime)
    {
        string prevDotName = "EMA_Dot_" + TimeToString(lastCandleTime, TIME_DATE|TIME_MINUTES);
        ObjectDelete(0, prevDotName);
        lastCandleTime = currentCandleTime;
    }

    double emaValue = iMA(NULL, 0, emaPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
    globalEMAValue = emaValue;  // Update global EMA value

    double dotPrice;
    color dotColor;

    if (Close[0] > emaValue)
    {
        dotPrice = emaValue - (Point * 10);
        dotColor = dotColorAbove;
    }
    else
    {
        dotPrice = emaValue + MarketInfo(Symbol(), MODE_SPREAD) * Point;
        dotColor = dotColorBelow;
    }

    string dotName = "EMA_Dot_" + TimeToString(Time[0], TIME_DATE|TIME_MINUTES);
    ObjectDelete(dotName);

    if (ObjectCreate(dotName, OBJ_ARROW, 0, Time[0], dotPrice))
    {
        ObjectSetInteger(0, dotName, OBJPROP_COLOR, dotColor);
        ObjectSetInteger(0, dotName, OBJPROP_ARROWCODE, Close[0] > emaValue ? 233 : 234);
    }

    if (!isFirstDot)
    {
        string lineName = "EMA_Line";
        ObjectDelete(lineName);

        if (ObjectCreate(lineName, OBJ_TREND, 0, timePrev, emaValuePrev, Time[0], emaValue))
        {
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
            ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
        }
    }
    else
    {
        isFirstDot = false;
    }

    emaValuePrev = emaValue;
    timePrev = Time[0];
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create Spread Label                                              |
//+------------------------------------------------------------------+
void CreateSpreadLabel()
{
    ObjectCreate(0, spreadLabelName, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, spreadLabelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, spreadLabelName, OBJPROP_XDISTANCE, 58);
    ObjectSetInteger(0, spreadLabelName, OBJPROP_YDISTANCE, 15);
    ObjectSetString(0, spreadLabelName, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, spreadLabelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, spreadLabelName, OBJPROP_COLOR, clrLimeGreen);
    ObjectSetString(0, spreadLabelName, OBJPROP_TEXT, "Initializing...");
    ChartRedraw(0); // Force a redraw of the chart
}

//+------------------------------------------------------------------+
//| Update Spread Label                                              |
//+------------------------------------------------------------------+
void UpdateSpreadLabel()
{
    int currentSpread = (int)MarketInfo(Symbol(), MODE_SPREAD);
    ObjectSetString(0, spreadLabelName, OBJPROP_TEXT, "Spread: " + IntegerToString(currentSpread));
    ChartRedraw(0); // Force a redraw of the chart
}

//+------------------------------------------------------------------+
//| Update Remaining Time Label                                      |
//+------------------------------------------------------------------+
void UpdateRemainingTimeLabel()
{
    datetime currentTime = TimeCurrent();
    
    // Update every tick to ensure accurate time display
    datetime nextCandleTime = iTime(NULL, 0, 0) + PeriodSeconds(Period());
    int remainingSeconds = (int)(nextCandleTime - currentTime);
    
    string remainingTime = "  ---" + IntegerToString(remainingSeconds / 60, 2, '0') + ":" 
                                 + IntegerToString(remainingSeconds % 60, 2, '0');
    
    if (ObjectFind(0, remainingTimeObjName) == -1)
    {
        ObjectCreate(0, remainingTimeObjName, OBJ_TEXT, 0, currentTime, Bid);
        ObjectSetInteger(0, remainingTimeObjName, OBJPROP_COLOR, clrChocolate);
        ObjectSetInteger(0, remainingTimeObjName, OBJPROP_FONTSIZE, 11);
        ObjectSetString(0, remainingTimeObjName, OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, remainingTimeObjName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
    }
    
    ObjectSetString(0, remainingTimeObjName, OBJPROP_TEXT, remainingTime);
    ObjectSetInteger(0, remainingTimeObjName, OBJPROP_TIME, iTime(NULL, 0, 0));
    ObjectSetDouble(0, remainingTimeObjName, OBJPROP_PRICE, Bid);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Parse Set Times                                                  |
//+------------------------------------------------------------------+
bool ParseSetTimes()
{
    bool success = true;
    success &= ParseTimeArray(SRSetTimeArray, srSetTimeMinutes);
    success &= ParseTimeArray(ScalpSetTimeArray, scalpSetTimeMinutes);
    success &= ParseTimeArray(MeasuredSetTimeArray, measuredSetTimeMinutes);
    return success;
}

//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
{
    double profit = TesterStatistics(0);
    double trades = TesterStatistics(10);
    double profitFactor = TesterStatistics(8);
    double expectedPayoff = TesterStatistics(13);
    double drawdown = TesterStatistics(2);
    
    if(drawdown > 0 && trades > 0)
        return (profit - drawdown) * profitFactor * expectedPayoff / trades;
    else
        return 0;
}