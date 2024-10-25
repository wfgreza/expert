#ifndef COMMON_FUNCTIONS_MQH
#define COMMON_FUNCTIONS_MQH

#property strict

// Function declarations
bool IsWithinTradingHours();
bool IsNewDay();
void ResetDailyVariables();
void ParseRRRValues();
void HandleEndOfDay();
bool IsEATradeAllowed();
double CalculateAccountRisk();
void CloseAllTrades();
void LogCurrentState(string reason = "");
double CalculateUnrealizedPL();
string ErrorDescription(int error_code);
void DeletePendingOrders(string reason = "");
void ResetTradeVariables();
bool ParseTimeArray(string timeArrayStr, int& timeMinutes[]);
int TimeStringToMinutes(string timeStr);
string TimeMinutesToString(int totalMinutes);
void CheckMaxDailyLossAndGain();
bool SplitAndPlaceOrder(int type, double lots, double price, double sl, double tp, string comment);
bool PlaceSingleOrder(int type, double lots, double price, double sl, double tp, string comment);
int GenerateUniqueGroupId();
double GetGroupTotalLots(int groupId);
bool CloseGroupOrders(int groupId);
bool ModifyGroupOrders(int groupId, double sl, double tp);
bool TryOrderSend(int type, double lots, double price, double sl, double tp, string comment);

// Function implementations

bool IsWithinTradingHours()
{
    int currentMinutes = TimeHour(TimeCurrent()) * 60 + TimeMinute(TimeCurrent());
    int startMinutes = (int)(tradingStartTime * 60);
    int endMinutes = (int)(tradingEndTime * 60);
    return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

bool IsNewDay()
{
    datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    if (today > currentTradingDay)
    {
        currentTradingDay = today;
        Print("New trading day started. Resetting daily variables.");
        return true;
    }
    return false;
}

void CheckMaxDailyLossAndGain()
{
    if (maxDailyLossPercent == 0 && maxDailyGainPercent == 0)
        return;

    double currentBalance = AccountBalance();
    double unrealizedPL = CalculateUnrealizedPL();
    currentDailyLoss = startingDailyBalance - (currentBalance + unrealizedPL);
    currentDailyGain = (currentBalance + unrealizedPL) - startingDailyBalance;
    
    double maxLossAmount = startingDailyBalance * (maxDailyLossPercent / 100.0);
    double maxGainAmount = startingDailyBalance * (maxDailyGainPercent / 100.0);
    
    if (currentDailyLoss >= maxLossAmount || (maxDailyGainPercent > 0 && currentDailyGain >= maxGainAmount))
    {
        Print("Maximum daily loss/gain reached. Closing all positions and stopping trading for the day.");
        CloseAllTrades();
        stopTradingForDay = true;
        LogCurrentState("Max Daily Loss/Gain Hit");
    }
}

void ResetDailyVariables()
{
    startingDailyBalance = AccountBalance();
    currentDailyLoss = 0;
    currentDailyGain = 0;
    stopTradingForDay = false;
    totalOrdersOpened = 0;
    endOfDayRoutineExecuted = false;
    Print("Daily variables reset.");
    LogCurrentState("Daily Reset");
}

void ParseRRRValues()
{
    string rrrStringArray[];
    int rrrCount = StringSplit(rrrValues, ',', rrrStringArray);
    
    if (rrrCount == 0)
    {
        Print("Error: No valid RRR values found. Using default RRR of 1.0");
        ArrayResize(rrrArray, 1);
        rrrArray[0] = 1.0;
        return;
    }
    
    ArrayResize(rrrArray, rrrCount);
    
    for (int i = 0; i < ArraySize(rrrArray); i++)
    {
        rrrArray[i] = StringToDouble(rrrStringArray[i]);
        if (rrrArray[i] <= 0)
        {
            Print("Warning: Invalid RRR value at index ", i, ". Using default value of 1.0");
            rrrArray[i] = 1.0;
        }
    }
    
    Print("RRR values parsed: ", rrrValues);
}

void HandleEndOfDay()
{
    datetime currentTime = TimeCurrent();

    if (TimeHour(currentTime) == 23 && TimeMinute(currentTime) == 0 && !endOfDayRoutineExecuted)
    {
        Print("Executing end of day routine at ", TimeToString(currentTime));
        CloseAllTrades();
        ResetDailyVariables();
        endOfDayRoutineExecuted = true;
    }
}

bool IsEATradeAllowed()
{
    if (!IsWithinTradingHours())
    {
        Print("Outside of trading hours. No trading allowed.");
        return false;
    }

    if (stopTradingForDay)
    {
        Print("Trading stopped for the day due to reaching max daily loss or gain.");
        return false;
    }

    if (!IsTradeAllowed())
    {
        Print("Trading not allowed by MT4 (check AutoTrading button).");
        return false;
    }

    return true;
}

double CalculateAccountRisk()
{
    double balance = AccountBalance();
    double equity = AccountEquity();
    return (balance - equity) / balance * 100;
}

void CloseAllTrades()
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            {
                bool result = false;
                int attempts = 3;
                
                while (attempts > 0)
                {
                    if (OrderType() <= OP_SELL)
                        result = OrderClose(OrderTicket(), OrderLots(), OrderType() == OP_BUY ? MarketInfo(Symbol(), MODE_BID) : MarketInfo(Symbol(), MODE_ASK), 3);
                    else
                        result = OrderDelete(OrderTicket());
                    
                    if (result)
                        break;
                    else
                    {
                        Print("Failed to close/delete order ", OrderTicket(), ". Error: ", GetLastError());
                        attempts--;
                        Sleep(1000);
                    }
                }
                
                if (!result)
                    Print("Failed to close/delete order ", OrderTicket(), " after multiple attempts");
            }
        }
    }
    
    ResetTradeVariables();
    LogCurrentState("All Trades Closed");
}

void LogCurrentState(string reason = "")
{
    if (reason != "")
    {
        Print("State Update (", reason, "): Time=", TimeToString(TimeCurrent()), 
              ", TotalOrdersOpened=", totalOrdersOpened,
              ", Current Daily Loss=", NormalizeDouble(currentDailyLoss, 2),
              ", Current Daily Gain=", NormalizeDouble(currentDailyGain, 2));
    }
}


double CalculateUnrealizedPL()
{
    double unrealizedPL = 0;
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            {
                unrealizedPL += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }
    }
    return unrealizedPL;
}

string ErrorDescription(int error_code)
{
    string error_string;
    switch(error_code)
    {
        case ERR_NO_ERROR:                 error_string="No error"; break;
        case ERR_NO_RESULT:                error_string="No error returned, but the result is unknown"; break;
        case ERR_COMMON_ERROR:             error_string="Common error"; break;
        case ERR_INVALID_TRADE_PARAMETERS: error_string="Invalid trade parameters"; break;
        case ERR_SERVER_BUSY:              error_string="Trade server is busy"; break;
        case ERR_OLD_VERSION:              error_string="Old version of the client terminal"; break;
        case ERR_NO_CONNECTION:            error_string="No connection with trade server"; break;
        case ERR_NOT_ENOUGH_RIGHTS:        error_string="Not enough rights"; break;
        case ERR_TOO_FREQUENT_REQUESTS:    error_string="Too frequent requests"; break;
        case ERR_MALFUNCTIONAL_TRADE:      error_string="Malfunctional trade operation"; break;
        case ERR_ACCOUNT_DISABLED:         error_string="Account disabled"; break;
        case ERR_INVALID_ACCOUNT:          error_string="Invalid account"; break;
        case ERR_TRADE_TIMEOUT:            error_string="Trade timeout"; break;
        case ERR_INVALID_PRICE:            error_string="Invalid price"; break;
        case ERR_INVALID_STOPS:            error_string="Invalid stops"; break;
        case ERR_INVALID_TRADE_VOLUME:     error_string="Invalid trade volume"; break;
        case ERR_MARKET_CLOSED:            error_string="Market is closed"; break;
        case ERR_TRADE_DISABLED:           error_string="Trade is disabled"; break;
        case ERR_NOT_ENOUGH_MONEY:         error_string="Not enough money"; break;
        case ERR_PRICE_CHANGED:            error_string="Price changed"; break;
        case ERR_OFF_QUOTES:               error_string="Off quotes"; break;
        case ERR_BROKER_BUSY:              error_string="Broker is busy"; break;
        case ERR_REQUOTE:                  error_string="Requote"; break;
        case ERR_ORDER_LOCKED:             error_string="Order is locked"; break;
        case ERR_LONG_POSITIONS_ONLY_ALLOWED: error_string="Long positions only allowed"; break;
        case ERR_TOO_MANY_REQUESTS:        error_string="Too many requests"; break;
        default:                           error_string="Unknown error"; 
    }
    return error_string;
}

void DeletePendingOrders(string reason = "")
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() > OP_SELL)
            {
                bool result = OrderDelete(OrderTicket());
                if (!result)
                {
                    Print("Failed to delete pending order: Ticket=", OrderTicket(), ", Error=", GetLastError());
                }
            }
        }
    }
}

void ResetTradeVariables()
{
    totalOrdersOpened = 0;
    // Reset other trade-related variables as needed
}

bool ParseTimeArray(string timeArrayStr, int& timeMinutes[])
{
    string timeStrings[];
    int count = StringSplit(timeArrayStr, ',', timeStrings);
    
    if (count == 0)
    {
        Print("Error: No set times provided for ", timeArrayStr);
        return false;
    }
    
    ArrayResize(timeMinutes, count);
    
    for (int i = 0; i < count; i++)
    {
        timeMinutes[i] = TimeStringToMinutes(timeStrings[i]);
        
        if (timeMinutes[i] == -1)
        {
            Print("Error: Invalid time format '", timeStrings[i], "'. Please use HH:MM format.");
            return false;
        }
    }
    
    ArraySort(timeMinutes);
    return true;
}

int TimeStringToMinutes(string timeStr)
{
    string parts[];
    if (StringSplit(timeStr, ':', parts) != 2)
        return -1;
    
    int hours = (int)StringToInteger(parts[0]);
    int minutes = (int)StringToInteger(parts[1]);
    
    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59)
        return -1;
    
    return hours * 60 + minutes;
}

string TimeMinutesToString(int totalMinutes)
{
    int hours = totalMinutes / 60;
    int minutes = totalMinutes % 60;
    return StringFormat("%02d:%02d", hours, minutes);
}

//+------------------------------------------------------------------+
//| Split Order                                                      |
//+------------------------------------------------------------------+
bool SplitAndPlaceOrder(int type, double lots, double price, double sl, double tp, string comment)
{
    double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
    int splitCount = MathCeil(lots / maxLot);
    double remainingLots = lots;
    int groupId = GenerateUniqueGroupId();
    bool allOrdersPlaced = true;

    for (int i = 0; i < splitCount; i++)
    {
        double currentLot = (i == splitCount - 1) ? remainingLots : maxLot;
        string splitComment = StringConcatenate(comment, " (", i+1, "/", splitCount, ") GroupID:", groupId);
        
        bool orderPlaced = PlaceSingleOrder(type, currentLot, price, sl, tp, splitComment);
        
        if (!orderPlaced)
        {
            Print("Failed to place split order ", i+1, " of ", splitCount);
            allOrdersPlaced = false;
            break;
        }
        
        remainingLots -= currentLot;
    }

    return allOrdersPlaced;
}

//+------------------------------------------------------------------+
//| Place Single Order                                               |
//+------------------------------------------------------------------+
bool PlaceSingleOrder(int type, double lots, double price, double sl, double tp, string comment)
{
    int ticket = OrderSend(Symbol(), type, lots, price, 3, sl, tp, comment, MagicNumber, 0, type == OP_BUY || type == OP_BUYSTOP ? Blue : Red);
    
    if (ticket > 0)
    {
        Print("Order placed successfully: Ticket ", ticket, ", Type: ", OrderTypeToString(type), 
              ", Lots: ", lots, ", Entry: ", price, ", SL: ", sl, ", TP: ", tp);
        return true;
    }
    else
    {
        int error = GetLastError();
        Print("OrderSend failed. Error: ", error, " - ", ErrorDescription(error));
        return false;
    }
}

//+------------------------------------------------------------------+
//| Generate Unique Group ID                                         |
//+------------------------------------------------------------------+
int GenerateUniqueGroupId()
{
    static int lastGroupId = 0;
    return ++lastGroupId;
}

//+------------------------------------------------------------------+
//| Get Group Total Lots                                             |
//+------------------------------------------------------------------+
double GetGroupTotalLots(int groupId)
{
    double totalLots = 0;
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            {
                string comment = OrderComment();
                if (StringFind(comment, "GroupID:" + IntegerToString(groupId)) >= 0)
                {
                    totalLots += OrderLots();
                }
            }
        }
    }
    return totalLots;
}

//+------------------------------------------------------------------+
//| Close Group Orders                                               |
//+------------------------------------------------------------------+
bool CloseGroupOrders(int groupId)
{
    bool allClosed = true;
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            {
                string comment = OrderComment();
                if (StringFind(comment, "GroupID:" + IntegerToString(groupId)) >= 0)
                {
                    bool closed = OrderClose(OrderTicket(), OrderLots(), OrderType() == OP_BUY ? Bid : Ask, 3);
                    if (!closed)
                    {
                        Print("Failed to close order ", OrderTicket(), ". Error: ", GetLastError());
                        allClosed = false;
                    }
                }
            }
        }
    }
    return allClosed;
}

//+------------------------------------------------------------------+
//| Modify Group Orders                                              |
//+------------------------------------------------------------------+
bool ModifyGroupOrders(int groupId, double sl, double tp)
{
    bool allModified = true;
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            {
                string comment = OrderComment();
                if (StringFind(comment, "GroupID:" + IntegerToString(groupId)) >= 0)
                {
                    bool modified = OrderModify(OrderTicket(), OrderOpenPrice(), sl, tp, 0);
                    if (!modified)
                    {
                        Print("Failed to modify order ", OrderTicket(), ". Error: ", GetLastError());
                        allModified = false;
                    }
                }
            }
        }
    }
    return allModified;
}

//+------------------------------------------------------------------+
//| Try Order Send                                                   |
//+------------------------------------------------------------------+
bool TryOrderSend(int type, double lots, double price, double sl, double tp, string comment)
{
    int maxAttempts = 1000;
    double initialPrice = price;
    double initialSL = sl;
    double initialTP = tp;
    double initialSLDistance = MathAbs(price - sl);
    double initialTPDistance = MathAbs(price - tp);
    bool isPendingOrder = (type == OP_BUYSTOP || type == OP_SELLSTOP);
    
    double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
    double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
    double initialRiskAmount = AccountEquity() * firstTradeRiskPercent / 100;
    
    for (int attempts = 0; attempts < maxAttempts; attempts++)
    {
        if (!isPendingOrder)
        {
            if (type == OP_BUY)
                price = Ask;
            else if (type == OP_SELL)
                price = Bid;
        }
        else
        {
            if (type == OP_BUYSTOP)
                price = NormalizeDouble(initialPrice + attempts * Point, Digits);
            else if (type == OP_SELLSTOP)
                price = NormalizeDouble(initialPrice - attempts * Point, Digits);
        }

        if (type == OP_BUY || type == OP_BUYSTOP)
            sl = NormalizeDouble(price - (initialSLDistance + attempts * Point), Digits);
        else if (type == OP_SELL || type == OP_SELLSTOP)
            sl = NormalizeDouble(price + (initialSLDistance + attempts * Point), Digits);

        // Recalculate lot size based on the new SL distance
        double newSLDistance = MathAbs(price - sl);
        lots = NormalizeDouble(initialRiskAmount / ((newSLDistance / tickSize) * tickValue), 2);

        // Adjust TP proportionally to maintain the original RRR
        double tpDistance = initialTPDistance * (newSLDistance / initialSLDistance);
        if (type == OP_BUY || type == OP_BUYSTOP)
            tp = NormalizeDouble(price + tpDistance, Digits);
        else if (type == OP_SELL || type == OP_SELLSTOP)
            tp = NormalizeDouble(price - tpDistance, Digits);

        bool orderPlaced = SplitAndPlaceOrder(type, lots, price, sl, tp, comment);
        
        if (orderPlaced)
        {
            double potentialLoss = (lots * newSLDistance / tickSize) * tickValue;
            double potentialGain = (lots * tpDistance / tickSize) * tickValue;
            double actualRRR = tpDistance / newSLDistance;
            Print("Orders sent successfully: Type: ", OrderTypeToString(type), 
                  ", Total Lots: ", lots,
                  ", Entry: ", price, ", SL: ", sl, ", TP: ", tp,
                  ", SL distance: ", newSLDistance / Point, " points",
                  ", TP distance: ", tpDistance / Point, " points",
                  ", Potential Loss: $", NormalizeDouble(potentialLoss, 2),
                  ", Potential Gain: $", NormalizeDouble(potentialGain, 2),
                  ", Actual RRR: ", NormalizeDouble(actualRRR, 2));
            return true;
        }
        
        int error = GetLastError();
        if (error == ERR_INVALID_STOPS)
        {
            if (attempts % 10 == 0 || attempts == 0)
            {
                double potentialLoss = (lots * newSLDistance / tickSize) * tickValue;
                double potentialGain = (lots * tpDistance / tickSize) * tickValue;
                double actualRRR = tpDistance / newSLDistance;
                Print("Attempt ", attempts + 1, ": Type: ", OrderTypeToString(type), 
                      ", Entry: ", price, ", SL: ", sl, ", TP: ", tp,
                      ", SL distance: ", newSLDistance / Point, " points",
                      ", TP distance: ", tpDistance / Point, " points",
                      ", Lots: ", lots,
                      ", Potential Loss: $", NormalizeDouble(potentialLoss, 2),
                      ", Potential Gain: $", NormalizeDouble(potentialGain, 2),
                      ", Actual RRR: ", NormalizeDouble(actualRRR, 2));
            }
        }
        else
        {
            Print("Order placement failed. Error: ", error, " - ", ErrorDescription(error), ". Attempt ", attempts + 1);
            Sleep(1000);
        }
        
        if (MathAbs((price - sl) - initialSLDistance) / Point >= 1000)
        {
            Print("Reached maximum SL adjustment of 1000 points. Unable to place order.");
            return false;
        }
    }
    
    Print("Failed to send order after ", maxAttempts, " attempts");
    return false;
}

//+------------------------------------------------------------------+
//| Convert order type to string                                     |
//+------------------------------------------------------------------+
string OrderTypeToString(int type)
{
    switch(type)
    {
        case OP_BUY: return "Buy";
        case OP_SELL: return "Sell";
        case OP_BUYLIMIT: return "Buy Limit";
        case OP_SELLLIMIT: return "Sell Limit";
        case OP_BUYSTOP: return "Buy Stop";
        case OP_SELLSTOP: return "Sell Stop";
        default: return "Unknown";
    }
}

#endif // COMMON_FUNCTIONS_MQH