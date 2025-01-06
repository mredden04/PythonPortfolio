# bring in needed libraries
import requests
import json
import time
import os
import csv
from datetime import datetime, timedelta
from itertools import permutations
from itertools import combinations


import networkx as nx
from networkx.classes.function import path_weight

import matplotlib.pyplot as plt

import alpaca_trade_api as tradeapi
from alpaca.trading.client import TradingClient
from alpaca.trading.requests import MarketOrderRequest
from alpaca.trading.enums import OrderSide, TimeInForce

# API credentials
api_key = 'PK5YUWWM27BRMCPMKM5N'
secret_key = 'yiuiKyWP4DnRa1vQ9gO83EYOf4wRurnHoGRFfkjd'
base_url = 'https://paper-api.alpaca.markets'

api = tradeapi.REST(api_key, secret_key, base_url, api_version='v2')

account = api.get_account()
print(account)

# give the path for the results.json file
results_file_path = 'vscode_projects\data5500_hw\FinalProject\\results.json'

# bring in cryptocurrencies
currencies = [['bitcoin-cash', 'bch'], ['litecoin', 'ltc'], ['ethereum', 'eth'], ['shiba-inu', 'shib'], ['chainlink', 'link'], ['avalanche', 'avax'], ['dogecoin', 'doge'], ['polkadot', 'dot'], ['aave', 'aave'], ['basic-attention-token', 'bat'], ['curve-dao-token', 'crv'], ['uniswap', 'uni'], ['maker', 'mkr']]

g = nx.DiGraph()
edges = []

# get the currency exchange rates
url1 = 'https://api.coingecko.com/api/v3/simple/price?ids='
url2 = ','
url3 = '&vs_currencies='
url4 = ','

print("Bringing in data...")

# get every permutation of the 13 cyptocurrencies
for c1, c2 in permutations(currencies,2):
    url = url1 + c1[0] + url2 + c2[0] + url3 + c1[1] + url4 + c2[1]

    try:
        # pull the information and put it in a dictionary
        req = requests.get(url)
        dct1 = json.loads(req.text)
        rate = dct1[c1[0]][c2[1]]
        edges.append((c1[1], c2[1], rate))

        # save the exchange rates in the data folder
        current_time = datetime.now().strftime('%Y-%m-%d-%H-%M')
        curr_dir = os.path.dirname(__file__) # get the current directory of this file
        data_dir = os.path.join(curr_dir, 'Data')
        csv_file_path = f'{data_dir}\\{c1[1]}_{c2[1]}_{current_time}.txt'
        try:
            with open(csv_file_path, 'w') as csv_file:
                csv_writer = csv.writer(csv_file)
                csv_writer.writerow([c1[1], c2[1], rate])
        except Exception as e:
            print(f'Error writing to file {csv_file_path}: {e}')
        # add in a sleep to avoid the pull rate limit
        time.sleep(12)
    except:
        # if there is no information, go to the next permutation
        time.sleep(12)
        pass

# add the edges to the graph
g.add_weighted_edges_from(edges)

print("Finished bringing in data.")

# save a graph visual
curr_dir = os.path.dirname(__file__) # get the current directory of this file
graph_visual_fil = curr_dir + "/" + "cryptocurrencies_graph_visual.png"

pos=nx.circular_layout(g) # pos = nx.nx_agraph.graphviz_layout(G)
nx.draw_networkx(g,pos)
labels = nx.get_edge_attributes(g,'weight')
nx.draw_networkx_edge_labels(g,pos,edge_labels=labels)

plt.savefig(graph_visual_fil)

# print out the nodes
# print(g.nodes)

# travere the graph
for c1, c2 in permutations(g.nodes, 2):
    # make variables to keep track of the least and greatest path
    least_path_factor = 999999999
    least_path = ""
    greatest_path_factor = 0
    greatest_path = ""

    #print("Paths from", c1, "to", c2, "-----------------------------------------")
    
    # use all simple paths to find the paths between the cryptocurrencies
    for path in nx.all_simple_paths(g, source=c1, target=c2):
        path_weight = 1
        reverse_path_weight = 1
        path_factor = 0

        for i in range(len(path) - 1):
            # calculate the path weight by multipling the edges together
            path_weight *= g[path[i]][path[i+1]]['weight']
            try:
                # calculate the reverse path weight
                reverse_path_weight *= g[path[i+1]][path[i]]['weight']
            except:
                # if no reverse path exists, print "no reverse path"
                # print("No reverse path")
                pass

        reverse_path = path[::-1]
        # if there is no reverse path, set the reverse path weight to 0
        if reverse_path_weight == 1:
            reverse_path_weight = 0
        # calculate the path factor by multiplying the path weight and reverse path weight together
        path_factor = path_weight * reverse_path_weight

        # check if the path weights are the least or greatest, if so save them
        if path_factor < least_path_factor:
            least_path_factor = path_factor
            least_path = path
        if path_factor > greatest_path_factor:
            greatest_path_factor = path_factor
            greatest_path = path
        
    # print the least and greatest path for each permutation
    # if least_path_factor != 999999999:
        # print("The shortest path from", c1, "to", c2, "is", least_path, "and", least_path[::-1], "with a path weight factor of", least_path_factor)
    #if greatest_path_factor != 0:
        #print("The greatest path from", c1, "to", c2, "is", greatest_path, "and", greatest_path[::-1], "with a path weight factor of", greatest_path_factor)

    # put the path and reverse path together
    full_greatest_path = []
    for crypto in greatest_path:
        full_greatest_path.append(crypto)
    for crypto in greatest_path[::-1]:
        full_greatest_path.append(crypto)
    # print(full_greatest_path)

    # if path factor is greater than one and less than 1.1, submit an order
    if greatest_path_factor > 1 and greatest_path_factor < 1.1:
        print("Submitting orders for", full_greatest_path, 'as this path has an arbitrage of', greatest_path_factor)
        # save the order path and the path factor to a results.json file
        order = {'order path': full_greatest_path, 'arbitrage': greatest_path_factor}
        # save the current contexts in the results.json file
        with open(results_file_path, 'r') as results_file:
            try:
                data = json.load(results_file)
            except:
                results = []
        # append the latest order
        results.append(order)
        with open(results_file_path, 'w') as results_file:
            json.dump(results, results_file, indent=4)
        
        # submit the buy and sell orders for each cryptocurrency in the path
        crypto_count = 0
        while crypto_count < len(full_greatest_path) - 1:
            crypto = full_greatest_path[crypto_count]
            next_crypto = full_greatest_path[crypto_count+1]
            try: 
                api.submit_order(symbol=crypto.upper() + 'USD', qty=1, side='buy', type='market', time_in_force='gtc')
                #print("Buy for " + crypto.upper() + 'USD' + ' was successful.')
            except:
                print("Buy for " + crypto.upper() + 'USD' + ' failed.')
            try:
                api.submit_order(symbol=crypto.upper() + 'USD', qty=1, side='sell', type='market', time_in_force='gtc')
                #print("Sell for " + crypto.upper() + 'USD' + ' was successful.')
            except: 
                print("Sell for " + crypto.upper() + 'USD' + ' failed.')
            crypto_count += 1
    # if no arbitrage is found, go to the next greatest path
    else: 
        # print("No arbitrage found.")
        pass



