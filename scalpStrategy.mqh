#ifndef SCALP_STRATEGY_MQH
#define SCALP_STRATEGY_MQH

#property strict

// Scalp Strategy specific variables
datetime lastScalpActionTime = 0;
bool scalpOrderOpened = false;
double scalpCandleLength = 0;
bool scalpCandleBullish = false;
double scalpOrderOpenPrice = 0;

//+------------------------------------------------------------------+
//| Scalp Strategy Main Function                                     |
//+------------------------------------------------------------------+
void ExecuteScalpStrategy()
{
    Print("Executing Scalp Strategy at ", TimeToString(TimeCurrent()));
    HandleScalpStrategy();
}

//+------------------------------------------------------------------+
//| Handle Scalp Strategy                                            |
//+------------------------------------------------------------------+
void HandleScalpStrategy()
{
    if (!IsWithinTradingHours() || !IsEATradeAllowed())
    {
        Print("Trading not allowed. Scalp strategy not active.");
        return;
    }

    datetime currentTime = TimeCurrent();

    // Check if we've already opened an order for this set time
    if (scalpOrderOpened && currentTime - lastScalpActionTime < PeriodSeconds(PERIOD_M1))
    {
        return;
    }

    // Reset the order opened flag if it's a new set time
    if (currentTime - lastScalpActionTime >= PeriodSeconds(PERIOD_M1))
    {
        scalpOrderOpened = false;
    }

    if (!scalpOrderOpened)
    {
        int candleIndex = 1; // Use the previous completed candle
        scalpCandleLength = MeasureScalpCandleLength(candleIndex);
        scalpCandleBullish = IsScalpCandleBullish(candleIndex);
        
        Print("--- Scalp Strategy Execution ---");
        Print("Measurement Candle High: ", High[candleIndex]);
        Print("Measurement Candle Low: ", Low[candleIndex]);
        Print("Measurement Candle Close: ", Close[candleIndex]);
        Print("Measured Candle Length: ", scalpCandleLength);
        Print("Is Bullish: ", scalpCandleBullish);
        
        int orderType = scalpCandleBullish ? OP_BUY : OP_SELL;
        bool orderPlaced = OpenScalpMarketOrder(orderType);
        
        if (orderPlaced)
        {
            scalpOrderOpened = true;
            lastScalpActionTime = currentTime;
        }
        else
        {
            Print("Failed to place Scalp order. Will try again on next tick.");
        }
    }
}

//+------------------------------------------------------------------+
//| Open Scalp Market Order                                          |
//+------------------------------------------------------------------+
bool OpenScalpMarketOrder(int type)
{
    if (!IsEATradeAllowed())
    {
        Print("Trading not allowed. Scalp market order not opened.");
        return false;
    }

    double entryPrice = (type == OP_BUY) ? Ask : Bid;
    double stopLoss = CalculateScalpStopLoss(type, entryPrice);
    double takeProfit = CalculateScalpTakeProfit(type, entryPrice, currentTradeNumber, stopLoss);
    double lotSize = CalculateScalpLotSize(MathAbs(entryPrice - stopLoss));
    
    string orderComment = "Scalp_Trade_" + IntegerToString(totalOrdersOpened);

    bool orderPlaced = TryOrderSend(type, lotSize, entryPrice, stopLoss, takeProfit, orderComment);
    
    if (orderPlaced)
    {
        totalOrdersOpened++;
        lastTradeTime = TimeCurrent();
        lastOrderType = type;
        scalpOrderOpenPrice = NormalizeDouble(entryPrice, Digits);
        LogCurrentState("Scalp Trade Opened");
        Print("Scalp trade opened, Total Orders: ", totalOrdersOpened);
        return true;
    }
    else
    {
        Print("Failed to open Scalp trade: Type ", type, ", Lots ", lotSize, ", Entry ", entryPrice, ", SL ", stopLoss, ", TP ", takeProfit);
        return false;
    }
}

//+------------------------------------------------------------------+
//| Calculate Scalp Stop Loss                                        |
//+------------------------------------------------------------------+
double CalculateScalpStopLoss(int type, double entryPrice)
{
    Print("--- CalculateScalpStopLoss Start ---");
    Print("Type: ", type, ", EntryPrice: ", entryPrice);

    double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;
    double offset = slOffset * Point;
    
    // Calculate the measured SL distance
    double measuredSLDistance = scalpCandleLength;
    measuredSLDistance += spread + offset;
    Print("Measured SL Distance (including spread and offset): ", measuredSLDistance / Point, " points");

    // Get the minimum SL distance from the broker
    double minSLDistance = GetScalpMinimumSLDistance();
    Print("Minimum SL Distance from broker: ", minSLDistance / Point, " points");

    // Use the maximum of the two
    double finalSLDistance = MathMax(measuredSLDistance, minSLDistance);
    Print("Final SL Distance: ", finalSLDistance / Point, " points");

    double sl;
    if (type == OP_BUY)
        sl = NormalizeDouble(entryPrice - finalSLDistance, Digits);
    else
        sl = NormalizeDouble(entryPrice + finalSLDistance, Digits);
    Print("SL calculation: ", sl);
    
    Print("SL Distance from entry: ", MathAbs(entryPrice - sl) / Point, " points");
    Print("--- CalculateScalpStopLoss End ---");
    
    return sl;
}

//+------------------------------------------------------------------+
//| Calculate Scalp Take Profit                                      |
//+------------------------------------------------------------------+
double CalculateScalpTakeProfit(int type, double entryPrice, int tradeNumber, double slPrice)
{
    double slDistance = MathAbs(entryPrice - slPrice);
    
    double rrr = 1.0; // Default RRR
    
    Print("--- CalculateScalpTakeProfit Start ---");
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
    if (type == OP_BUY)
        tp = NormalizeDouble(entryPrice + tpDistance, Digits);
    else
        tp = NormalizeDouble(entryPrice - tpDistance, Digits);
    
    Print("Calculated TP: ", tp);
    Print("--- CalculateScalpTakeProfit End ---");
    
    return tp;
}

//+------------------------------------------------------------------+
//| Calculate Scalp Lot Size                                         |
//+------------------------------------------------------------------+
double CalculateScalpLotSize (double SLDistance = 0)
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
        slDistance = MathMax(scalpCandleLength + slOffset * MarketInfo(Symbol(), MODE_POINT), GetScalpMinimumSLDistance ());
    } else {
        slDistance = MathMax(SLDistance, GetScalpMinimumSLDistance ());
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
//| Get Scalp Minimum SL Distance                                    |
//+------------------------------------------------------------------+
double GetScalpMinimumSLDistance()
{
    double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
    double freezeLevel = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
    return MathMax(minDistance, freezeLevel);
}

//+------------------------------------------------------------------+
//| Measure Scalp Candle Length                                      |
//+------------------------------------------------------------------+
double MeasureScalpCandleLength(int shift)
{
    return MathAbs(High[shift] - Low[shift]);
}

//+------------------------------------------------------------------+
//| Is Scalp Candle Bullish                                          |
//+------------------------------------------------------------------+
bool IsScalpCandleBullish(int shift)
{
    return Close[shift] > Open[shift];
}


#endif // SCALP_STRATEGY_MQH