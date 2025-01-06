import requests
import json

# first data pull

tickers = ["AAPL", "ADBE", "BA", "DIS", "GOOG", "INTC", "META", "MSFT", "NVDA", "TSLA", "WMT"]

def firstDataPull(tickers):
    for ticker in tickers:
        url = "https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol="+ticker+"&outputsize=full&apikey=NG9C9EVPVYBMQT0C8"
    
        # request data
        request = requests.get(url)
        requestDictionary = json.loads(request.text)
        # print(requestDictionary)
        
        fileLines = []
        
        # access the needed information
        file = open("/home/ubuntu/environment/FinalProject/"+ticker+".csv", "w")
        for date in requestDictionary["Time Series (Daily)"].keys():
            fileLines.append(date + ", " + requestDictionary["Time Series (Daily)"][date]["4. close"] + "\n")
            
        # write data to file
        fileLines = fileLines[::-1]
        file.writelines(fileLines)
        file.close()
    
# firstDataPull(tickers) # don't run this again after first pull

def appendData(tickers):
    for ticker in tickers:
        url = "https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol="+ticker+"&outputsize=full&apikey=NG9C9EVPVYBMQT0C8"
    
        # request data
        request = requests.get(url)
        requestDictionary = json.loads(request.text)
        # print(requestDictionary)
        
        
        # different from initial data pull
        # read in csv file
        csvFile = open("/home/ubuntu/environment/FinalProject/"+ticker+".csv", "r")
        csvLines = csvFile.readlines()
        csvFile.close()
        
        # .split on comma
        latestDate = csvLines[-1].split(",")[0]
        
        # get new set of data
        newLines = []
        for date in requestDictionary["Time Series (Daily)"].keys():
            # compare latest date to new data
            if date == latestDate:
                break
            else:
                newLines.append(date + ", " + requestDictionary["Time Series (Daily)"][date]["4. close"] + "\n")
        
            
        # write data to file
        newLines = newLines[::-1]
        file = open("/home/ubuntu/environment/FinalProject/"+ticker+".csv", "a")
        file.writelines(newLines)
        file.close()


appendData(tickers)


# 1 - Mean Reversion
def meanReversion(prices):
    print("Mean Reversion:")
    i           = 0
    buy         = 0 
    firstBuy    = 0
    mrProfit    = 0
    x           = 6
    
    # start 5 day moving average on the 6th day
    for price in prices:
        if i > 4:
        # five day moving average
            average = (prices[i-1] + prices[i-2] + prices[i-3] + prices[i-4] + prices[i-5]) / 5
            
        # compare five day moving average to current day
            # buy if price is less than the average * 0.98
            if price < average * 0.98 and buy == 0: 
                buy = price
                # keep track of the first buy
                if firstBuy == 0:
                    firstBuy = price
                # output buy price
                print("Buying at: ", round(buy, 2))
                if x == len(prices):
                    print("You should buy this stock today.")
            # sell if price is greater than the average * 1.02
            elif price > average * 1.02 and buy != 0:
                sell = price
                profit = sell - buy
                # increase total profit
                mrProfit += sell - buy
                # set buy back to 0
                buy = 0
                # output sell price and profit 
                print("Selling at: ", round(sell, 2))
                print("Trade profit: ", round(profit,2))
                if x == len(prices):
                    print("You should sell this stock today.")
            # if you do not buy or sell do nothing
            else:
                pass
            
        i += 1
            
            # output final profit, first buy, and final profit percentage
    print("--------------------------------------------------------")
    mrProfit = round(mrProfit, 2)
    print("Total profit:", round(mrProfit, 2))
    print("Fist buy:", round(firstBuy, 2))
    # calculate final profit percentage by (total profit / first buy) * 100
    finalProfitPercentage = round(((mrProfit / firstBuy) * 100), 2)
    print("% Return: " + str(finalProfitPercentage) + "%")
    print("--------------------------------------------------------")
    mrReturns = (mrProfit / firstBuy)
                
    
    return mrProfit, mrReturns

# 2 - 5 Day Simple Moving Average
def simpleMovingAverage(prices):
    print("Simple Moving Average:")
    # setup variables
    i           = 0
    buy         = 0 
    firstBuy    = 0
    saProfit    = 0
    x           = 6
    
    # start 5 day moving average on the 6th day
    for price in prices:
        if i > 4:
    # five day moving average
            average = (prices[i-1] + prices[i-2] + prices[i-3] + prices[i-4] + prices[i-5]) / 5
        
    # compare five day moving average to current day
        # buy if price is less than the average
            # print("length:", len(prices))
            if price > average and buy == 0: 
                buy = price
            # keep track of the first buy
                if firstBuy == 0:
                    firstBuy = price
            # output buy price
                print("Buying at: ", round(buy, 2))
                if x == len(prices):
                    print("You should buy this stock today.")
        # sell if price is greater than the average
            elif price < average and buy != 0:
                sell = price
                profit = sell - buy
            # increase total profit
                saProfit += sell - buy
            # set buy back to 0
                buy = 0
            # output sell price and profit 
                print("Selling at: ", round(sell, 2))
                print("Trade profit: ", round(profit,2))
                if x == len(prices):
                    print("You should sell this stock today.")
        # if you do not buy or sell do nothing
            else:
                pass
            x += 1
        i += 1
    
    # output final profit, first buy, and final profit percentage
    print("--------------------------------------------------------")
    saProfit = round(saProfit, 2)
    print("Total profit:", round(saProfit, 2))
    print("Fist buy:", round(firstBuy, 2))
    # calculate final profit percentage by (total profit / first buy) * 100
    finalProfitPercentage = round(((saProfit / firstBuy) * 100), 2)
    print("% Return: " + str(finalProfitPercentage) + "%")
    print("--------------------------------------------------------")
    saReturns = (saProfit / firstBuy)
    
    return saProfit, saReturns
    
# 3 - Ten Day Simple Moving Average
def TenDayMovingAverage(prices):
    print("10 Day Moving Average:")
    # setup variables
    i           = 0
    buy         = 0 
    firstBuy    = 0
    TenProfit   = 0
    x           = 11

    # start 5 day moving average on the 6th day
    for price in prices:
        if i > 9:
    # five day moving average
            average = (prices[i-1] + prices[i-2] + prices[i-3] + prices[i-4] + prices[i-5] + prices[i-6] + prices[i-7] + prices[i-8] + prices[i-9] + prices[i-10]) / 10

    # compare five day moving average to current day
        # buy if price is less than the average
            if price > average and buy == 0: 
                buy = price
            # keep track of the first buy
                if firstBuy == 0:
                    firstBuy = price
            # output buy price
                print("Buying at: ", round(buy, 2))
                if x == len(prices):
                    print("You should buy this stock today.")
        # sell if price is greater than the average
            elif price < average and buy != 0:
                sell = price
                profit = sell - buy
            # increase total profit
                TenProfit += sell - buy
            # set buy back to 0
                buy = 0
            # output sell price and profit 
                print("Selling at: ", round(sell, 2))
                print("Trade profit: ", round(profit,2))
                if x == len(prices):
                    print("You should sell this stock today.")
            x += 1
        # if you do not buy or sell do nothing
        else:
            pass
            
        i += 1
    
    # output final profit, first buy, and final profit percentage
    print("--------------------------------------------------------")
    TenProfit = round(TenProfit, 2)
    print("Total profit:", round(TenProfit, 2))
    print("Fist buy:", round(firstBuy, 2))
    # calculate final profit percentage by (total profit / first buy) * 100
    finalProfitPercentage = round(((TenProfit / firstBuy) * 100), 2)
    print("% Return: " + str(finalProfitPercentage) + "%")
    print("--------------------------------------------------------")
    TenReturns = (TenProfit / firstBuy)
    
    return TenProfit, TenReturns
    
# save results
def saveResults(dictionary):
    # put dictionary information in a json file
    json.dump(dictionary, open("/home/ubuntu/environment/Homework#5/results.json", "w"), indent=4)
    return

tickers = ["AAPL", "GOOG", "ADBE", "AMZN", "CRSP", "DIS", "MSFT", "PEP", "WFC", "WMT"]

# set up dictionary
results = {}

# set up variable to keep track of the highest profit
highestProfit = 0

# loop through each ticker
for ticker in tickers:
    # open each file in read mode
    file = open("/home/ubuntu/environment/Homework#5/" + ticker + ".txt", "r")
    # seperate prices into list elements
    prices = [float(line) for line in file.readlines()]
    roundedPrices = []
    for price in prices:
        price = round(price, 2)
        roundedPrices.append(price)
    # print out the simple moving average returns and the mean reversion returns for each ticker
    print(ticker)
    saProfit, saReturns = simpleMovingAverage(prices)
    mrProfit, mrReturns = meanReversion(prices)
    TenProfit, TenReturns = TenDayMovingAverage(prices)
    
    # save prices, mr profit, mr returns, sa profit, sa returns, Ten Profit, and Ten Returns to the results dictionary
    results[ticker + " prices"] = roundedPrices
    results[ticker + " sa Profit"] = saProfit
    results[ticker + " sa Returns"] = saReturns
    results[ticker + " mr Profit"] = mrProfit
    results[ticker + " mr Returns"] = mrReturns
    results[ticker + " 10 Day Profit"] = TenProfit
    results[ticker + " 10 Day Returns"] = TenReturns
    
    # best stock and strategy with highest profit
    # compare profit to last highest profit and save if higher
    if saProfit > highestProfit:
        # save the price
        highestProfit = saProfit
        # save the ticker
        highestProfitTicker = ticker
        # save the strategy
        bestStrategy = "simple moving average strategy"
    # compare profit to last highest profit and save if higher
    if mrProfit > highestProfit:
        highestProfit = mrProfit
        highestProfitTicker = ticker
        bestStrategy = "mean reversion strategy"
    # compare profit to last highest profit and save if higher
    if TenProfit > highestProfit:
        highestProfit = TenProfit
        highestProfitTicker = ticker
        bestStrategy = "ten day moving average strategy"
    # put results into the json file
    saveResults(results)
    
# print the highest profit, which stock it was, and what strategy it was
print("The most profit made was the " + highestProfitTicker + " stock with the " + bestStrategy +". It made $" + str(highestProfit) + ".")

# save the highest profit, which stock it was, and what strategy it was
results["The most profit made was the " + highestProfitTicker + " stock with the " + bestStrategy +". It made $" + str(highestProfit) + "."] = highestProfit

saveResults(results)