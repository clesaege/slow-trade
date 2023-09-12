// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "SimpleERC20.sol";


uint constant SCALE = 1E18; // Scaling factor.
uint constant auctionTime = 1 minutes; // Time without bids for an auction to be finalized.

contract Linear {

    uint public outcomeMax; // Maximum amount of outcome tokens to be sold.
    uint public outcome; // Amount of outcome tokens sold.
    uint public underlying; // Underlying collected as part of the AMM.
    uint public bonusUnderlying; // Underlying collected due to auction surplus.
    address payable public owner; // Controller of the pool.
    ERC20 public outcomeToken; // The outcome token traded.

    struct Auction {
        uint outcome; // Amount of outcome tokens.
        uint price; // Total price for those tokens.
        uint lastTime; // Time of the last bid.
        address payable winner; // The current winner of the auction.
    }

    Auction[] public buyAuctions;  
    Auction[] public sellAuctions;    


    /// @dev Initialize the pool. Need to compute ofchain the amounts required.
    /// @param _outcome The amount of virtual outcome tokens sold.
    /// @param _outcomeToken The outcome token to be traded.
    constructor(uint _outcome, uint _outcomeMax, ERC20 _outcomeToken) payable {
        require(_outcome <= _outcomeMax); // Can't have sold more than the max.
        underlying = (_outcome * _outcome) / (2 * _outcomeMax);
        require(underlying == msg.value); // Check that the amount of underlying tokens provided is correct.

        outcomeMax = _outcomeMax;
        outcome = _outcome;
        owner = payable(msg.sender);
        outcomeToken = _outcomeToken;
        outcomeToken.transferFrom(msg.sender, address(this), _outcomeMax - _outcome);
    }

    /// @dev Add liquidity.
    function addLiquidity() public payable {
        require(msg.sender == owner);
        uint newUnderlying = underlying + msg.value;
        uint newOutcomeMax = (outcomeMax * newUnderlying) / underlying;
        uint newOutcome = (outcome * newUnderlying) / underlying;
        uint outcomeIn =  (newOutcomeMax - newOutcome) - (outcomeMax - outcome);

        underlying = newUnderlying;
        outcomeMax = newOutcomeMax;
        outcome = newOutcome;
        require(outcomeToken.transferFrom(msg.sender,address(this),outcomeIn));
    }

    /// @dev Remove liquidity. Note that if you remove everything, it would destroy the pool.
    /// @param _keep proportion to keep in SCALE.
    function removeLiquidity(uint _keep) public payable {
        require(msg.sender == owner);
        require(_keep <= SCALE); // Can't keep more than what is already there.
        uint newUnderlying = (underlying * _keep) / SCALE;
        uint newOutcomeMax = (outcomeMax * _keep) / SCALE;
        uint newOutcome = (outcome * _keep) / SCALE;
        uint outcomeOut = outcome - newOutcome;

        require(outcomeToken.transfer(owner, outcomeOut)); // Sent the outcome tokens removed.
        owner.transfer(underlying - newUnderlying); // Send the underlying removed.
        underlying = newUnderlying;
        outcome = newOutcome;
        outcomeMax = newOutcomeMax;
    }

    /// @dev Collect the bonus (tokens we got from overbiding in auctions)
    function collect() public {
        uint underlyingOut = bonusUnderlying;
        bonusUnderlying = 0;
        owner.transfer(underlyingOut);
    }

    /// @dev Buy outcome tokens.
    /// @param _outcomeOut Amount of outcome tokens to buy.
    function buy(uint _outcomeOut) public payable {
        require(outcome + _outcomeOut <= outcomeMax); // Can't buy more than the max available.
        uint cost = (_outcomeOut * (outcome + _outcomeOut/2)) / outcomeMax;
        require(msg.value == cost);
        underlying += msg.value;
        outcome += _outcomeOut;

        buyAuctions.push(Auction({ // Create an auction.
            outcome: _outcomeOut,
            price: cost,
            lastTime: block.timestamp,
            winner: payable(msg.sender)
        }));
    }

    /// @dev Bid in a buying auction.
    /// @param _auctionID The id of the buy auction.
    function buyBid(uint _auctionID) public payable {
        Auction storage auction = buyAuctions[_auctionID];
        require(block.timestamp - auction.lastTime < auctionTime); // Make sure the auction is not over.
        bonusUnderlying = msg.value - auction.price; // Add the extra payment as bonus. Reverts if value is lower than current.
        auction.winner.send(auction.price); // Reimburse the previous winner.
        auction.winner = payable(msg.sender);
        auction.price = msg.value;
        auction.lastTime = block.timestamp;
    }

    /// @dev Settle a buying auction.
    /// @param _auctionID The id of the buy auction.
    function buySettle(uint _auctionID) public {
        Auction storage auction = buyAuctions[_auctionID];
        require(block.timestamp - auction.lastTime >= auctionTime); // Make sure the auction is over.
        
        uint outcomeOut = auction.outcome;
        auction.outcome = 0;
        require(outcomeToken.transfer(auction.winner, outcomeOut));
    }


    /// @dev Sell outcome tokens.
    /// @param _outcomeIn Amount of tokens to sell.
    function sell(uint _outcomeIn) public {
        require(outcomeToken.transferFrom(msg.sender, address(this), _outcomeIn));

        outcome -= _outcomeIn; // Note that it would revert if trying to sell more than possible.
        uint toReceive = (_outcomeIn * (outcome + _outcomeIn/2) ) / outcomeMax;
        underlying -= toReceive;
        sellAuctions.push(Auction({ // Create a descending auction.
            outcome: _outcomeIn,
            price: toReceive,
            lastTime: block.timestamp,
            winner: payable(msg.sender)
        }));
    }

    /// @dev Bid in a selling auction.
    /// @param _auctionID The id of the sell auction.
    /// @param _price The price to accept. It should be lower than the current price.
    function sellBid(uint _auctionID, uint _price) public {
        Auction storage auction = sellAuctions[_auctionID];
        require(block.timestamp - auction.lastTime < auctionTime); // Make sure the auction is not over.
        bonusUnderlying = auction.price - _price; // Add the amount saved as bonus. Reverts if value is higher than current.
        require(outcomeToken.transferFrom(msg.sender, auction.winner, auction.outcome)); // Send the outcome tokens of the current winner to the previous one.
        auction.winner = payable(msg.sender);
        auction.price = _price;
        auction.lastTime = block.timestamp;
    }

    /// @dev Settle a selling auction.
    /// @param _auctionID The id of the buy auction.
    function sellSettle(uint _auctionID) public {
        Auction storage auction = sellAuctions[_auctionID];
        require(block.timestamp - auction.lastTime >= auctionTime); // Make sure the auction is over.
        
        uint underlyingOut = auction.price;
        auction.price = 0;
        auction.winner.transfer(underlyingOut); // Pay the winner.
    }


    ////// Helpers ////////
    function requiredAmountBuy(uint _outcomeOut) public view returns (uint underlyingIn) {
        require(outcome + _outcomeOut <= outcomeMax); // Can't buy more than the max available.
        underlyingIn = (_outcomeOut * (outcome + _outcomeOut/2)) / outcomeMax;
    }

    function sellPrice(uint _outcomeIn) view public returns(uint toReceive) {
        uint _outcome = outcome - _outcomeIn;
        toReceive = (_outcomeIn * (_outcome + _outcomeIn/2) ) / outcomeMax;
    }

    function requiredOutcomeForAdd(uint _underlyingToAdd) view public returns(uint outcomeIn) {
        uint newUnderlying = underlying + _underlyingToAdd;
        uint newOutcomeMax = (outcomeMax * newUnderlying) / underlying;
        uint newOutcome = (outcome * newUnderlying) / underlying;
        outcomeIn =  (newOutcomeMax - newOutcome) - (outcomeMax - outcome);
    }

}


contract Helper {
    function requiredAmountInit(uint _outcome, uint _outcomeMax) public pure returns (uint underlying, uint outcome) {
        require(_outcome <= _outcomeMax); // Can't have sold more than the max.
        underlying = (_outcome * _outcome ) / (2 * _outcomeMax);
        outcome = _outcomeMax - _outcome;
    }
}
