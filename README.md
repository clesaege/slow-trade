# Slow Trade
Slow Trade is a mix between an AMM (automated market maker) and an auction designed for trading prediction market outcome tokens.
It works as an AMM but instead of orders being settled instantly, it creates 1h auction where traders can overbid the current bid.
This solves the revelation loss (selling tokens at prices far below their real price when the outcome of a market become known) for liquidity providers.

## Team members
- @clesaege: clement@lesaege.com
- Moe Pwint Phyu: moepwintponepone@gmail.com

## Track
- Zilliqa#2
- Taiko#1
- Maker Spark (Use sDAI as underlying tokens, currently it's made such that xDAI which is gonna use sDAI can be the underlying token, if they don't we can modify to use sDAI as underlying which is particularly relevent to be capital efficient)
- Neon EVM
- Mantle#1

## Problem overview
See below.

## Future plans
- Allow multiple LPs
- Allow splitting of auctions
- Add minimal increment
- Make production parameters (currently auctions are just 1 min long for testing)
- Make an interface
- Allow concentrated liquidity

## Tech stack
- EVM
- Solidity
- Bonded Curves

## What was done during the hackathon
- Invented bounded linear AMM.
- Derived all the equations for this AMM (buy/sell/add liquidity/remove liquidity).
- Smart contracts
  - Implement a 0-1 bounded linear AMM (supports only a unique LP).
  - Implement a AMM + auction composite exchange.


# Problem
When providing liquidity, a liquidity provider is selling an asset at a particular price and buying the same asset at a slightly lower price. If the price remains mainly stable, the liquidity provider will make profit out of the difference of those prices (spread), but if the price moves in a single direction, the liquidity provider will end up with more of the less valuable asset. This is called « Impermanent loss », as if the price goes back to its origin, the liquidity provider will recoup this loss.
For example let’s say that that there is a market « Will Russia stop the invasion of Ukraine in 2023 ?». A liquidity provider use the strategy of making an order for 1 unit of « Yes » on both sides with a 0.1 step.
Now let’s look at two scenarios:
- Russia doesn’t announce a stop of the invasion. As we advance through the year 2023 it becomes less and less likely that the invasion will stop in 2023 (simply because there are less and less days remaining in 2023). The price which started around 0.5, drops little by little, 0.4, 0.3, 0.2, 0.1 up to reaching 0 on the 31 of December. Here many traders may have taken the orders and each would have made a small profit, but on the liquidity provider side, the result is quite bad, it paid 1.5$ to buy shares of « Yes » which will not be redeemable.
- Russia announces that it will stop the invasion. Immediately, a trader notices the news and take all the sell orders, paying 3$ for 4 shares of « Yes ». When the market resolves, he redeems those shares for 4$, netting 1$ of profit but creating a 1$ loss for the liquidity provider (who sold the 4 shares for 3$ despite those finally redeeming for 4$). We will call this loss the *« revelation loss »*.
  
We can see that when the market moves, liquidity providers lose money, it may be compensated by the profit made by the spread (our first example would have required 20 extra trades, 10 in each direction, to compensate for the impermanent loss). An approach which has been taken (by Omen) was to keep some of the profit from the spread. But it only goes so far as the issue is particularly problematic in prediction markets, as unlike other markets (crypto, stocks, commodities), shares of predictions always go to either 1 or 0.

# Solution
A way to greatly reduce liquidity providing risks is to use a hybrid approach between an AMM and an auction system.

The system would work as follows:
* Liquidity providers provide liquidity like they do in a classic AMM.
* Traders can't buy directly from the AMM but can place orders. When a trader places an order on the exchange, a simple short term auction starts (this can be around 1h). The auction starts at the price given by the AMM, with the initial bid being made by the trader who started the auction. Anyone can overbid with the current highest bidder. When this happens, the highest bidder order is cancelled and his tokens immediately refunded. When the auction ends the winner has its order executed.


### Practical implementation

We can see this as a system with 2 components: an AMM and an auction system.

Liquidity providers interact with the AMM contract while traders interact with the auction contract. The AMM only allows the auction contract to trade with it.

PUT FIGURE

When a trader makes an order, trading a underlying token (ex: stablecoin, sDAI) for an outcome token (ex: Biden token), it sends tokens A to the auction contract. This auction contract then makes a trade with the AMM such that the price given by the AMM is immediately updated.

The auction contract now owns the outcome tokens being bought and auctions them. The auction starts with the original trader being the current winner and the bid price being the  uprice paid by the original trader. If no one overbids the original trader, those outcome tokens are simply given to the original trader and the system would have functioned as a classic AMM (except the small settlement delay).

Now, if another trader overbids, the auction contract reimburses the underlying tokens to the current winner and keeps the difference (new_bid - previous_winner). The auction timer is reset. This can happen multiple times.

When bidding, it is possible to make only a partial bid (this is particularly relevant if the order is large). When this happens, the auction is split into two auctions (the original one, minus the part which was overbid and the new one which consists of the amount overbid). 

At the end of the bidding period, the winner gets the outcome tokens. If there has been some overbidding, the auction contract will have some extra underlying tokens. Those are sent to the AMM contract and added to the rewards of the liquidity providers.

**Chosen Curve**: Since the price of outcome token shares are bounded between 0 and 1, we chose a bounder linear AMM (where the price increases linearly from 0 to 1) in order to concentrate all the liquidity within the possible price range.

**Minimum increment**: In order to prevent a situation where different bidders would simply overbid each other incrementing only of a base unit (ex: 1 Wei), there is a minimum bid increment (for example 0.1%).

**Minimum order size**: In order to prevent malicious traders from starting auctions so small that the gas cost would be prohibitive compared to value auctioned, there is a minimum size (ex: 1DAI) for orders.

**Selling orders**: Selling outcome tokens works in a similar manner, excepts bids are not made in the amount of outcome tokens for some money tokens but in the amount of underlying tokens to receive from the outcome tokens. Traders participate in a descending auction bidding to accept the lowest amount of underlying from their outcome tokens. If a bid lower than the initial one, the remaining underlying tokens are sent back to the AMM as rewards for liquidity providers. Therefore liquidity providers rewards are always in the form of underlying tokens.

### Reasoning

The goal of this system is to prevent liquidity providers from losing huge sums of money when the result of a market becomes known while still allowing traders to have their orders executed in a reasonable timeframe.

Contrary to a classic auction system where the most common result of an order is not to be fulfilled, here traders can trade knowing most of their orders will be fulfilled within the short auction timeframe (1h). As they expect their orders to be fulfilled, they are more likely to make those orders compared to a pure auction system.

Here we chose to use a modified (to allow partial bid) English auction, instead of other types of auctions such as sealed bid Vickery auction, for the following reasons:



* **Simplicity**: This auction is the easiest to understand for traders. As we’ve already increased complexity by adding an auction step to an AMM, we want to keep the extra complexity at a minimum, specifically since the auction step will be irrelevant for most trades.
* **Capital efficiency**: By simply taking the highest bid, we can directly reimburse bids which are overbid. This gives back capital to traders as soon as possible for them to be able to use it in other orders (potentially increasing their bid on the same auction). Using a bounded linear AMM allows for all the liquidity of the market to be potentially usable.
* **Speed**: By not using sealed bids, we save ourselves from the extra delay introduced by commit and reveal schemes.
* **Auction marketability**: By having public bids, external observers can immediately spot assets currently undervalued by the highest bid (this is particularly relevant for when the result of a market is known and tokens of the winning outcome have their highest bid lower than 1) to bid on them.
* **Compatible incentives**: When the result is known, there are 2 possible strategies: The first one is just to bid the increment and hope that no one else will overbid. This can be highly profitable but only would only work if no one else is watching. The second strategy is to bid such that the value after the next increment is 1 (so 0.999 with a 0.1% increment), this way no one has an incentive to overbid you and you still get to get a 0.1% profit. In comparison, in a Vickery system, once a trader bids 1, there is no incentive for other traders (beside liquidity providers themselves) to overbid him and he can get assets at the previous price which can be significantly lower.

The rewards for liquidity providers are never in the form of outcome tokens but always in the form of underlying tokens. Indeed, when the result becomes known, it is possible to get outcome tokens of the losing options at a zero cost (mint complete sets and keep the winning outcome tokens which will redeem for the underlying, leaving you with free outcome tokens of losing outcomes). If rewards were in outcome tokens, it wouldn’t prevent liquidity providers from losing money (as getting more worthless tokens thanks to the auction mechanism wouldn’t help).

For traders, the system acts as a classic AMM with a 1h delay for most orders (bids where the price increased less than the increment during the bidding period).

For liquidity providers, the system acts like a classic AMM, except in periods of high price moves (such as when the result becomes known) where it switches to an auction system such that they receive extra compared to the simple AMM functioning. When a result becomes known, as long as there are multiple traders noticing the opportunity, the final price of the auction will be very close to 1 (0.999 with a 0.1% increment). This solves the resolution loss problem for all markets having a sufficient amount of eyes on them.




