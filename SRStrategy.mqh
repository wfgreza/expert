#ifndef SR_STRATEGY_MQH
#define SR_STRATEGY_MQH

#property strict

// Add this global variable at the top of the file
bool srLinesActive = false;

// SR Strategy specific variables
double resistanceLevel = 0;
double supportLevel = 0;
datetime lastSRLineTime = 0;
bool openSRMeasurementTaken = false;
bool openSROrderOpened = false;
double openSRCandleLength = 0;
bool openSRCandleBullish = false;
double openSROrderOpenPrice = 0;

// Function declarations
void DeleteExistingPendingOrders();

//+------------------------------------------------------------------+
//| SR Strategy Main Functions                                       |
//+------------------------------------------------------------------+
void ExecuteSRStrategy()
{
    Print("Executing SR Strategy from MQH at ", TimeToString(TimeCurrent()));
    DrawSupportResistance();
    CheckExpiredLines();
    HandleOpenSRStrategy();
}

//+------------------------------------------------------------------+
//| Draw Support Resistance                                          |
//+------------------------------------------------------------------+
void DrawSupportResistance()
{
    datetime currentTime = TimeCurrent();
    datetime currentDate = StringToTime(TimeToString(currentTime, TIME_DATE));

    Print("Drawing Support Resistance at ", TimeToString(currentTime));

    for (int i = 0; i < ArraySize(srSetTimeMinutes); i++)
    {
        datetime lineTime = currentDate + srSetTimeMinutes[i] * 60;

        if (currentTime >= lineTime && currentTime < lineTime + 60) // Within the first minute after set time
        {
            Print("Drawing S/R lines for set time: ", TimeToString(lineTime));
            
            int candleIndex = iBarShift(NULL, 0, lineTime, false) + 1;
            double prevHigh = iHigh(NULL, 0, candleIndex);
            double prevLow = iLow(NULL, 0, candleIndex);

            resistanceLevel = prevHigh;
            supportLevel = prevLow;

            datetime startTime = iTime(NULL, 0, candleIndex);
            datetime endTime = startTime + (PeriodSeconds() * Line_Extension);

            string resistanceLineName = "ResistanceLine_" + TimeToString(lineTime, TIME_DATE|TIME_MINUTES);
            string supportLineName = "SupportLine_" + TimeToString(lineTime, TIME_DATE|TIME_MINUTES);

            ObjectCreate(0, resistanceLineName, OBJ_TREND, 0, startTime, prevHigh, endTime, prevHigh);
            ObjectSetInteger(0, resistanceLineName, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, resistanceLineName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, resistanceLineName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, resistanceLineName, OBJPROP_RAY_RIGHT, 0);

            ObjectCreate(0, supportLineName, OBJ_TREND, 0, startTime, prevLow, endTime, prevLow);
            ObjectSetInteger(0, supportLineName, OBJPROP_COLOR, clrBlue);
            ObjectSetInteger(0, supportLineName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, supportLineName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, supportLineName, OBJPROP_RAY_RIGHT, 0);

            lastSRLineTime = currentTime;
            srLinesActive = true;
            Print("S/R lines drawn and activated. Resistance: ", resistanceLevel, ", Support: ", supportLevel);
        }
    }
}

//+------------------------------------------------------------------+
//| Check Expired Lines                                              |
//+------------------------------------------------------------------+
void CheckExpiredLines()
{
    datetime currentTime = TimeCurrent();

    int totalObjects = ObjectsTotal(0, 0, -1);
    for (int i = totalObjects - 1; i >= 0; i--)
    {
        string objectName = ObjectName(0, i);
        if (StringFind(objectName, "ResistanceLine_", 0) >= 0 || StringFind(objectName, "SupportLine_", 0) >= 0)
        {
            datetime lineEndTime = (datetime)ObjectGet(objectName, OBJPROP_TIME2);
            
            if (currentTime > lineEndTime)
            {
                if (ObjectDelete(0, objectName))
                {
                    Print("Expired S/R line deleted: ", objectName, ", End time: ", TimeToString(lineEndTime));
                    if (StringFind(objectName, "ResistanceLine_", 0) >= 0)
                        resistanceLevel = 0;
                    else if (StringFind(objectName, "SupportLine_", 0) >= 0)
                        supportLevel = 0;
                }
                else
                {
                    Print("Failed to delete expired S/R line: ", objectName, ", Error: ", GetLastError());
                }
            }
        }
    }

    // Reset strategy variables if both lines are deleted
    if (resistanceLevel == 0 && supportLevel == 0)
    {
        openSRMeasurementTaken = false;
        openSROrderOpened = false;
        srLinesActive = false;
        Print("S/R lines deactivated");
    }
}

bool AreSRLinesActive()
{
    return srLinesActive;
}

//+------------------------------------------------------------------+
//| Handle Open SR Strategy                                          |
//+------------------------------------------------------------------+
void HandleOpenSRStrategy()
{
    Print("--- HandleOpenSRStrategy called at ", TimeToString(TimeCurrent()), " ---");

    if (!IsWithinTradingHours())
    {
        Print("Not within trading hours. Exiting HandleOpenSRStrategy.");
        return;
    }

    if (!IsEATradeAllowed())
    {
        Print("EA trading not allowed. Exiting HandleOpenSRStrategy.");
        return;
    }

    datetime currentTime = TimeCurrent();

    // Check if S/R lines have expired
    if (currentTime - lastSRLineTime > PeriodSeconds(PERIOD_M1) * Line_Extension)
    {
        //Print("S/R lines have expired. Deleting lines and resetting variables.");
        DeleteSRLines();
        openSRMeasurementTaken = false;
        openSROrderOpened = false;
        return;
    }

    Print("Current price: ", DoubleToString(Close[0], Digits), ", Resistance: ", DoubleToString(resistanceLevel, Digits), ", Support: ", DoubleToString(supportLevel, Digits));

    // Check for breakout
    bool breakoutOccurred = false;
    int breakoutType = 0; // 1 for bullish, -1 for bearish

    if (Close[1] > resistanceLevel)
    {
        breakoutOccurred = true;
        breakoutType = 1;
        
    }
    else if (Close[1] < supportLevel)
    {
        breakoutOccurred = true;
        breakoutType = -1;
        
    }

    if (breakoutOccurred && !openSRMeasurementTaken)
    {
        openSRCandleLength = MeasureCandleLength(1);
        openSRCandleBullish = IsBullishCandle(1);
        openSRMeasurementTaken = true;
        
        double breakoutCandleHigh = High[1];
        double breakoutCandleLow = Low[1];
        
        Print("--- Breakout Detected ---");
        Print("Breakout Candle High: ", DoubleToString(breakoutCandleHigh, Digits));
        Print("Breakout Candle Low: ", DoubleToString(breakoutCandleLow, Digits));
        Print("Breakout Candle Close: ", DoubleToString(Close[1], Digits));
        Print("Measured Candle Length: ", DoubleToString(openSRCandleLength, Digits));
        Print("Is Bullish: ", openSRCandleBullish);
        Print("Resistance Level: ", DoubleToString(resistanceLevel, Digits));
        Print("Support Level: ", DoubleToString(supportLevel, Digits));
        Print("Breakout Type: ", breakoutType == 1 ? "Bullish" : "Bearish");
        
        double emaValue = iMA(NULL, 0, emaPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
        bool isAboveEMA = Close[1] > emaValue;
        
        Print("EMA Value: ", DoubleToString(emaValue, Digits));
        Print("Is Above EMA: ", isAboveEMA);
        
        bool orderPlaced = false;
        
        if (breakoutType == 1) // Bullish breakout
        {
            if (isAboveEMA)
            {
                Print("Attempting to open BUY market order");
                orderPlaced = OpenMarketOrder(OP_BUY, true);
            }
            else
            {
                Print("Attempting to set SELLSTOP pending order");
                orderPlaced = SetPendingOrder(OP_SELLSTOP, true, breakoutCandleLow);
            }
        }
        else // Bearish breakout
        {
            if (isAboveEMA)
            {
                Print("Attempting to set BUYSTOP pending order");
                orderPlaced = SetPendingOrder(OP_BUYSTOP, true, breakoutCandleHigh);
            }
            else
            {
                Print("Attempting to open SELL market order");
                orderPlaced = OpenMarketOrder(OP_SELL, true);
            }
        }
        
        if (orderPlaced)
        {
            Print("Order successfully placed");
            openSROrderOpened = true;
            DeleteSRLines();
        }
        else
        {
            Print("Failed to place order after breakout. Will try again on next tick.");
        }
    }
    else if (breakoutOccurred)
    {
        Print("Breakout occurred but openSROrderOpened is true. No new order placed.");
    }
    else
    {
        Print("No breakout occurred or conditions not met for order placement.");
    }

    Print("--- End of HandleOpenSRStrategy ---");
}

//+------------------------------------------------------------------+
//| Delete SR Lines                                                  |
//+------------------------------------------------------------------+
void DeleteSRLines()
{
    int totalObjects = ObjectsTotal(0, 0, OBJ_TREND);
    for (int i = totalObjects - 1; i >= 0; i--)
    {
        string objectName = ObjectName(0, i, 0, OBJ_TREND);
        if (StringFind(objectName, "ResistanceLine_", 0) >= 0 || StringFind(objectName, "SupportLine_", 0) >= 0)
        {
            ObjectDelete(0, objectName);
            Print("S/R line deleted: ", objectName);
        }
    }
}

//+------------------------------------------------------------------+
//| Delete Existing Pending Orders                                   |
//+------------------------------------------------------------------+
void DeleteExistingPendingOrders()
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() > OP_SELL)
            {
                string comment = OrderComment();
                // Extract GroupID from comment if it exists
                int groupIdPos = StringFind(comment, "GroupID:");
                if (groupIdPos >= 0)
                {
                    string groupIdStr = StringSubstr(comment, groupIdPos + 8);
                    for (int j = OrdersTotal() - 1; j >= 0; j--)
                    {
                        if (OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
                        {
                            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() > OP_SELL)
                            {
                                if (StringFind(OrderComment(), "GroupID:" + groupIdStr) >= 0)
                                {
                                    bool deleteResult = OrderDelete(OrderTicket());
                                    if (!deleteResult)
                                    {
                                        Print("Failed to delete pending order: Ticket=", OrderTicket(), ", Error=", GetLastError());
                                    }
                                    else
                                    {
                                        Print("Successfully deleted pending order: Ticket=", OrderTicket());
                                    }
                                }
                            }
                        }
                    }
                    break; // Exit after handling one group
                }
                else
                {
                    // Handle non-grouped pending orders
                    bool deleteResult = OrderDelete(OrderTicket());
                    if (!deleteResult)
                    {
                        Print("Failed to delete pending order: Ticket=", OrderTicket(), ", Error=", GetLastError());
                    }
                    else
                    {
                        Print("Successfully deleted pending order: Ticket=", OrderTicket());
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open Market Order                                                |
//+------------------------------------------------------------------+
bool OpenMarketOrder(int type, bool isSRStrategy)
{
    if (!IsEATradeAllowed())
    {
        Print("Trading not allowed. Market order not opened.");
        return false;
    }

    double lotSize = CalculateLotSize();
    double entryPrice = (type == OP_BUY) ? Ask : Bid;
    double stopLoss = CalculateStopLoss(type, entryPrice, isSRStrategy);
    double takeProfit = CalculateTakeProfit(type, entryPrice, currentTradeNumber, stopLoss);
    
    string orderComment = "SR_Trade_" + IntegerToString(totalOrdersOpened);

    bool orderPlaced = TryOrderSend(type, lotSize, entryPrice, stopLoss, takeProfit, orderComment);
    
    if (orderPlaced)
    {
        totalOrdersOpened++;
        lastTradeTime = TimeCurrent();
        lastOrderType = type;
        if (isSRStrategy)
            openSROrderOpenPrice = NormalizeDouble(entryPrice, Digits);
        LogCurrentState("Trade Opened");
        Print("Trade opened, Total Orders: ", totalOrdersOpened);
        return true;
    }
    else
    {
        Print("Failed to open trade: Type ", type, ", Lots ", lotSize, ", Entry ", entryPrice, ", SL ", stopLoss, ", TP ", takeProfit);
        return false;
    }
}

//+------------------------------------------------------------------+
//| Set Pending Order                                                |
//+------------------------------------------------------------------+
bool SetPendingOrder(int type, bool isSRStrategy, double breakoutLevel)
{
    if (!IsEATradeAllowed())
    {
        Print("Trading not allowed. Pending order not set.");
        return false;
    }

    double price;
    double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;
    double offset = slOffset * Point;

    if (type == OP_BUYSTOP)
        price = NormalizeDouble(breakoutLevel + spread + offset, Digits);
    else if (type == OP_SELLSTOP)
        price = NormalizeDouble(breakoutLevel - offset, Digits);
    else
    {
        Print("Invalid order type for SetPendingOrder");
        return false;
    }

    double lotSize = CalculateLotSize();
    double sl = CalculateStopLoss(type, price, isSRStrategy);
    double tp = CalculateTakeProfit(type, price, currentTradeNumber, sl);

    string orderComment = "SR_Trade_" + IntegerToString(totalOrdersOpened);

    bool orderPlaced = TryOrderSend(type, lotSize, price, sl, tp, orderComment);

    if (orderPlaced)
    {
        pendingOrdersCount++;
        totalOrdersOpened++;
        Print("Pending order set: Type ", type == OP_BUYSTOP ? "Buy Stop" : "Sell Stop", 
              ", Lots ", lotSize, ", Entry ", price, ", SL ", sl, ", TP ", tp, ", Total Orders: ", totalOrdersOpened);
        
        lastOrderType = type;
        LogCurrentState("Pending Order Set");
        return true;
    }
    else
    {
        Print("Failed to set pending order: Type ", type, ", Lots ", lotSize, ", Price ", price, ", SL ", sl, ", TP ", tp);
        return false;
    }
}

//+------------------------------------------------------------------+
//| Update First Pending Order                                       |
//+------------------------------------------------------------------+
void UpdateFirstPendingOrder()
{
    if (!IsFirstOrderPending())
        return;
    
    bool isNewCandleBullish = Close[1] > Open[1];
    bool isNewCandleBearish = Close[1] < Open[1];
    bool isDoji = Close[1] == Open[1];
    
    bool isAboveEMA = Close[1] > globalEMAValue;
    double currentHigh = High[1];
    double currentLow = Low[1];
    double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;
    double offset = slOffset * Point;
    
    if (isDoji)
    {
        Print("Doji candle detected. Waiting for the next candle before updating the order.");
        return;
    }
    
    DeleteExistingPendingOrders();
    
    int newOrderType;
    double entryPrice;
    
    if (isNewCandleBullish && isAboveEMA)
    {
        newOrderType = OP_BUY;
        entryPrice = Ask;
    }
    else if (isNewCandleBearish && isAboveEMA)
    {
        newOrderType = OP_BUYSTOP;
        entryPrice = currentHigh + offset + spread;
    }
    else if (isNewCandleBearish && !isAboveEMA)
    {
        newOrderType = OP_SELL;
        entryPrice = Bid;
    }
    else if (isNewCandleBullish && !isAboveEMA)
    {
        newOrderType = OP_SELLSTOP;
        entryPrice = currentLow - offset;
    }
    else
    {
        Print("Unexpected candle condition. No new order placed.");
        return;
    }
    
    double sl = CalculateStopLoss(newOrderType, entryPrice, true);
    double tp = CalculateTakeProfit(newOrderType, entryPrice, 0, sl);
    bool orderOpened = false;
    
    if (newOrderType == OP_BUY || newOrderType == OP_SELL)
    {
        if (OpenMarketOrder(newOrderType, true))
        {
            Print("Market order opened successfully");
            orderOpened = true;
            lastOpenOrderTicket = OrderTicket();
            lastOpenOrderNumber = currentTradeNumber;
            totalOrdersOpened++;
        }
        else
        {
            Print("Failed to open market order");
        }
    }
    else
    {
        if (SetPendingOrder(newOrderType, true, entryPrice))
        {
            Print("New pending order set successfully");
            orderOpened = true;
        }
        else
        {
            Print("Failed to set new pending order");
        }
    }
    
    if (orderOpened)
    {
        openSROrderOpened = true;
    }
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(int type, double entryPrice, bool isSRStrategy)
{
    Print("--- CalculateStopLoss Start ---");
    Print("Type: ", type, ", EntryPrice: ", entryPrice, ", isSRStrategy: ", isSRStrategy);

    double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;
    double offset = slOffset * Point;
    
    // Calculate the measured SL distance
    double measuredSLDistance = isSRStrategy ? openSRCandleLength : 0;
    measuredSLDistance += spread + offset;
    Print("Measured SL Distance (including spread and offset): ", measuredSLDistance / Point, " points");

    // Get the minimum SL distance from the broker
    double minSLDistance = GetMinimumSLDistance();
    Print("Minimum SL Distance from broker: ", minSLDistance / Point, " points");

    // Use the maximum of the two
    double finalSLDistance = MathMax(measuredSLDistance, minSLDistance);
    Print("Final SL Distance: ", finalSLDistance / Point, " points");

    double sl;
    if (type == OP_BUY || type == OP_BUYSTOP)
        sl = NormalizeDouble(entryPrice - finalSLDistance, Digits);
    else
        sl = NormalizeDouble(entryPrice + finalSLDistance, Digits);
    Print("SL calculation: ", sl);
    
    Print("SL Distance from entry: ", MathAbs(entryPrice - sl) / Point, " points");
    Print("--- CalculateStopLoss End ---");
    
    return sl;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(int type, double entryPrice, int tradeNumber, double slPrice)
{
    double slDistance = MathAbs(entryPrice - slPrice);
    
    double rrr = 1.0; // Default RRR
    
    Print("--- CalculateTakeProfit Start ---");
    Print("Trade Number: ", tradeNumber);
    Print("Entry Price: ", entryPrice);
    Print("SL Price: ", slPrice);
    Print("SL Distance: ", slDistance);
    
    if (ArraySize(rrrArray) > 0)
    {
        int index = MathMin(tradeNumber, ArraySize(rrrArray) - 1);
        Print("RRR Array Index: ", index);
        if (index >= 0 && index < ArraySize(rrrArray))
        {
            rrr = rrrArray[index];
            Print("RRR value from array: ", rrr);
            if (rrr <= 0)
            {
                Print("Warning: Invalid RRR value at index ", index, ". Using default RRR of 1.0");
                rrr = 1.0;
            }
        }
        else
        {
            Print("Warning: Index ", index, " out of range for rrrArray. Using default RRR of 1.0");
        }
    }
    else
    {
        Print("Warning: rrrArray is empty. Using default RRR of 1.0");
    }
    
    double tpDistance = slDistance * rrr;
    Print("TP Distance: ", tpDistance);
    
    double tp;
    if (type == OP_BUY || type == OP_BUYSTOP)
        tp = NormalizeDouble(entryPrice + tpDistance, Digits);
    else
        tp = NormalizeDouble(entryPrice - tpDistance, Digits);
    
    Print("Calculated TP: ", tp);
    Print("--- CalculateTakeProfit End ---");
    
    return tp;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double SLDistance = 0)
{
    double accountEquity = AccountEquity();
    double riskAmount = accountEquity * (firstTradeRiskPercent / 100);
    double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
    double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
    double minLot = MarketInfo(Symbol(), MODE_MINLOT);
    double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
    double leverage = AccountLeverage();
    
    double slDistance;
    if (SLDistance == 0) {
        slDistance = MathMax(openSRCandleLength + slOffset * MarketInfo(Symbol(), MODE_POINT), GetMinimumSLDistance());
    } else {
        slDistance = MathMax(SLDistance, GetMinimumSLDistance());
    }
    slDistance = slDistance / MarketInfo(Symbol(), MODE_POINT);
    
    double lotSize = NormalizeDouble(riskAmount / (slDistance * tickValue), 2);
    
    lotSize = MathMin(lotSize, accountEquity * leverage / (MarketInfo(Symbol(), MODE_MARGINREQUIRED) * 100));
    lotSize = MathMax(minLot, lotSize);
    lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;
    
    Print("Calculated lot size: ", lotSize, " (SL Distance: ", slDistance, " points, Potential Loss: $", NormalizeDouble(lotSize * slDistance * tickValue, 2), ")");
    return lotSize;
}

//+------------------------------------------------------------------+
//| Get Minimum SL Distance                                          |
//+------------------------------------------------------------------+
double GetMinimumSLDistance()
{
    double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
    double freezeLevel = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
    return MathMax(minDistance, freezeLevel);
}

//+------------------------------------------------------------------+
//| Measure Candle Length                                            |
//+------------------------------------------------------------------+
double MeasureCandleLength(int shift)
{
    return MathAbs(High[shift] - Low[shift]);
}

//+------------------------------------------------------------------+
//| Is Bullish Candle                                                |
//+------------------------------------------------------------------+
bool IsBullishCandle(int shift)
{
    return Close[shift] > Open[shift];
}

//+------------------------------------------------------------------+
//| Is First Order Pending                                           |
//+------------------------------------------------------------------+
bool IsFirstOrderPending()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            {
                return OrderType() > OP_SELL; // Returns true if it's a pending order
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get First Pending Order Ticket                                   |
//+------------------------------------------------------------------+
int GetFirstPendingOrderTicket()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() > OP_SELL)
            {
                return OrderTicket();
            }
        }
    }
    return 0;
}

#endif // SR_STRATEGY_MQH