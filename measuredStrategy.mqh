#ifndef MEASURED_STRATEGY_MQH
#define MEASURED_STRATEGY_MQH

#property strict

// Measured Strategy specific variables
datetime Measured_lastSetTime = 0;
bool Measured_isWaitingForMeasurement = false;
bool Measured_orderOpened = false;
double Measured_candleLength = 0;
bool Measured_candleBullish = false;
double Measured_orderOpenPrice = 0;

//+------------------------------------------------------------------+
//| Measured Strategy Main Function                                  |
//+------------------------------------------------------------------+
void Measured_ExecuteStrategy()
{
    Print("Executing Measured Strategy at ", TimeToString(TimeCurrent()));
    Measured_HandleStrategy();
}


//+------------------------------------------------------------------+
//| Handle Measured Strategy                                         |
//+------------------------------------------------------------------+
void Measured_HandleStrategy()
{
    if (!IsWithinTradingHours() || !IsEATradeAllowed())
    {
        Print("Trading not allowed. Measured strategy not active.");
        return;
    }

    datetime currentTime = TimeCurrent();

    if (Measured_IsSetTime(currentTime))
    {
        Measured_isWaitingForMeasurement = true;
        Measured_lastSetTime = currentTime;
        Measured_orderOpened = false;  // Reset this variable at each new set time
        Print("Measured Strategy: Set time reached at ", TimeToString(currentTime), ". Waiting for next candle to close.");
        return;
    }

    if (Measured_isWaitingForMeasurement && currentTime >= Measured_lastSetTime + PeriodSeconds(PERIOD_CURRENT))
    {
        Measured_MeasureCandle();
        Measured_isWaitingForMeasurement = false;
        
        if (!Measured_orderOpened)
        {
            int candleIndex = 1; // Use the previous completed candle
            bool isAboveEMA = Close[candleIndex] > iMA(NULL, 0, emaPeriod, 0, MODE_EMA, PRICE_CLOSE, candleIndex);

            Print("--- Measured Strategy Execution ---");
            Print("Measurement Candle Time: ", TimeToString(iTime(NULL, 0, candleIndex)));
            Print("Measurement Candle Open: ", Open[candleIndex]);
            Print("Measurement Candle High: ", High[candleIndex]);
            Print("Measurement Candle Low: ", Low[candleIndex]);
            Print("Measurement Candle Close: ", Close[candleIndex]);
            Print("Measured Candle Length: ", Measured_candleLength);
            Print("Is Bullish: ", Measured_candleBullish);
            Print("Is Above EMA: ", isAboveEMA);

            bool orderPlaced = false;
            
            if (Measured_candleBullish && isAboveEMA)
            {
                Print("Measured Strategy: Attempting to open BUY market order");
                orderPlaced = Measured_OpenMarketOrder(OP_BUY);
            }
            else if (!Measured_candleBullish && !isAboveEMA)
            {
                Print("Measured Strategy: Attempting to open SELL market order");
                orderPlaced = Measured_OpenMarketOrder(OP_SELL);
            }
            else if (Measured_candleBullish && !isAboveEMA)
            {
                Print("Measured Strategy: Attempting to set SELLSTOP pending order");
                orderPlaced = Measured_SetPendingOrder(OP_SELLSTOP, Low[candleIndex]);
            }
            else if (!Measured_candleBullish && isAboveEMA)
            {
                Print("Measured Strategy: Attempting to set BUYSTOP pending order");
                orderPlaced = Measured_SetPendingOrder(OP_BUYSTOP, High[candleIndex]);
            }
            
            if (orderPlaced)
            {
                Print("Measured Strategy: Order successfully placed");
                Measured_orderOpened = true;
            }
            else
            {
                Print("Measured Strategy: Failed to place order after measurement. Will try again on next set time.");
            }
        }
        else
        {
            Print("Measured Strategy: Order already opened for this measurement. Waiting for next set time.");
        }
    }
}

//+------------------------------------------------------------------+
//| Measured Strategy OnTick                                         |
//+------------------------------------------------------------------+
void Measured_OnTick()
{
    if (IsWithinTradingHours() && IsEATradeAllowed())
    {
        Measured_HandleStrategy();
    }
}

//+------------------------------------------------------------------+
//| Check if it's a set time                                         |
//+------------------------------------------------------------------+
bool Measured_IsSetTime(datetime currentTime)
{
    int currentMinutes = (int)TimeHour(currentTime) * 60 + (int)TimeMinute(currentTime);
    
    for (int i = 0; i < ArraySize(measuredSetTimeMinutes); i++)
    {
        if (currentMinutes == measuredSetTimeMinutes[i])
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Measure Candle                                                   |
//+------------------------------------------------------------------+
void Measured_MeasureCandle()
{
    int candleIndex = 1; // Use the previous completed candle
    Measured_candleLength = Measured_CandleLength(candleIndex);
    Measured_candleBullish = Measured_IsBullishCandle(candleIndex);
    
    Print("Candle measured at ", TimeToString(TimeCurrent()));
    Print("Measured Candle Length: ", Measured_candleLength);
    Print("Is Bullish: ", Measured_candleBullish);
}

//+------------------------------------------------------------------+
//| Open Market Order                                                |
//+------------------------------------------------------------------+
bool Measured_OpenMarketOrder(int type)
{
    if (!IsEATradeAllowed())
    {
        Print("Trading not allowed. Market order not opened.");
        return false;
    }

    double lotSize = Measured_CalculateLotSize();
    double entryPrice = (type == OP_BUY) ? Ask : Bid;
    double stopLoss = Measured_CalculateStopLoss(type, entryPrice);
    double takeProfit = Measured_CalculateTakeProfit(type, entryPrice, currentTradeNumber, stopLoss);
    
    string orderComment = "Measured_Trade_" + IntegerToString(totalOrdersOpened);

    bool orderPlaced = TryOrderSend(type, lotSize, entryPrice, stopLoss, takeProfit, orderComment);
    
    if (orderPlaced)
    {
        totalOrdersOpened++;
        lastTradeTime = TimeCurrent();
        lastOrderType = type;
        Measured_orderOpenPrice = NormalizeDouble(entryPrice, Digits);
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
bool Measured_SetPendingOrder(int type, double breakoutLevel)
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
        Print("Invalid order type for Measured_SetPendingOrder");
        return false;
    }

    double lotSize = Measured_CalculateLotSize();
    double sl = Measured_CalculateStopLoss(type, price);
    double tp = Measured_CalculateTakeProfit(type, price, currentTradeNumber, sl);

    string orderComment = "Measured_Trade_" + IntegerToString(totalOrdersOpened);

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
//| Delete Existing Pending Orders                                   |
//+------------------------------------------------------------------+
void Measured_DeleteExistingPendingOrders()
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
//| Calculate Stop Loss                                              |
//+------------------------------------------------------------------+
double Measured_CalculateStopLoss(int type, double entryPrice)
{
    Print("--- Measured_CalculateStopLoss Start ---");
    Print("Type: ", type, ", EntryPrice: ", entryPrice);

    double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;
    double offset = slOffset * Point;
    
    // Calculate the measured SL distance
    double measuredSLDistance = Measured_candleLength;
    measuredSLDistance += spread + offset;
    Print("Measured SL Distance (including spread and offset): ", measuredSLDistance / Point, " points");

    // Get the minimum SL distance from the broker
    double minSLDistance = Measured_GetMinimumSLDistance();
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
    Print("--- Measured_CalculateStopLoss End ---");
    
    return sl;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                            |
//+------------------------------------------------------------------+
double Measured_CalculateTakeProfit(int type, double entryPrice, int tradeNumber, double slPrice)
{
    double slDistance = MathAbs(entryPrice - slPrice);
    
    double rrr = 1.0; // Default RRR
    
    Print("--- Measured_CalculateTakeProfit Start ---");
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
    Print("--- Measured_CalculateTakeProfit End ---");
    
    return tp;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double Measured_CalculateLotSize(double inputSLDistance = 0)
{
    double accountEquity = AccountEquity();
    double riskAmount = accountEquity * (firstTradeRiskPercent / 100);
    double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
    double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
    double minLot = MarketInfo(Symbol(), MODE_MINLOT);
    double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
    double leverage = AccountLeverage();
    
    double slDistance;
    if (inputSLDistance == 0) {
        slDistance = MathMax(Measured_candleLength + slOffset * MarketInfo(Symbol(), MODE_POINT), Measured_GetMinimumSLDistance());
    } else {
        slDistance = MathMax(inputSLDistance, Measured_GetMinimumSLDistance());
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
double Measured_GetMinimumSLDistance()
{
    double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
    double freezeLevel = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
    return MathMax(minDistance, freezeLevel);
}

//+------------------------------------------------------------------+
//| Measure Candle Length                                            |
//+------------------------------------------------------------------+
double Measured_CandleLength(int shift)
{
    return MathAbs(High[shift] - Low[shift]);
}

//+------------------------------------------------------------------+
//| Is Bullish Candle                                                |
//+------------------------------------------------------------------+
bool Measured_IsBullishCandle(int shift)
{
    return Close[shift] > Open[shift];
}

//+------------------------------------------------------------------+
//| Update First Pending Order                                       |
//+------------------------------------------------------------------+
void Measured_UpdateFirstPendingOrder()
{
    if (!Measured_IsFirstOrderPending())
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
    
    Measured_DeleteExistingPendingOrders();
    
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
    
    double sl = Measured_CalculateStopLoss(newOrderType, entryPrice);
    double tp = Measured_CalculateTakeProfit(newOrderType, entryPrice, 0, sl);
    bool orderOpened = false;
    
    if (newOrderType == OP_BUY || newOrderType == OP_SELL)
    {
        if (Measured_OpenMarketOrder(newOrderType))
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
        if (Measured_SetPendingOrder(newOrderType, entryPrice))
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
        Measured_orderOpened = true;
    }
}

//+------------------------------------------------------------------+
//| Is First Order Pending                                           |
//+------------------------------------------------------------------+
bool Measured_IsFirstOrderPending()
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
int Measured_GetFirstPendingOrderTicket()
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

#endif // MEASURED_STRATEGY_MQH