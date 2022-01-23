// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DojoHouse.sol";

contract DegenDojo is ERC20, VRFConsumerBase, Ownable {
    AggregatorV3Interface internal ethUsdPriceFeed;
    AggregatorV3Interface internal linkUsdPriceFeed;
    DojoHouse public house;
    uint256 private fee;
    bytes32 private keyhash;
    uint256[] public jackpotPaid;
    uint256[] public jackpotWeight;
    uint256[] public jackpotOdds;
    uint256[] public jackpotPast;
    uint256 public rewardsPerBlock;
    uint256 private startBlock;
    uint256 public bounty;
    struct PendingTrade {
        bytes32 _requestID;
        uint256 _amount;
        uint8 _level;
    }
    mapping(bytes32 => uint256) private requestToRandom;
    mapping(address => PendingTrade) private AddressToPendingTrade;
    address[] private smallTrades;
    //used as timelock for changing house contract
    struct newHouse {
        uint256 changeBlock;
        address newHouse;
    }
    newHouse public nextHouse;
    //simple getter for winners list where [0] = biggest winner, [1] = most recent win
    struct Winner {
        address winner;
        uint256 amount;
    }
    Winner[2] public winners;
    //events
    event RequestedRandomness(bytes32 requestId);
    event ClaimTrade(uint256 payout, uint256 winnings, uint256 remainder);

    /**
     * Constructor
     */
    constructor(
        address _ETHpriceFeedAddress,
        address _LINKpriceFeedAddress,
        address _vrfCoordinator,
        address _link,
        uint256 _fee,
        bytes32 _keyhash,
        uint256 initialSupply,
        uint256 _rewards
    )
        public
        VRFConsumerBase(_vrfCoordinator, _link)
        ERC20("DegenDojo", "DOJO")
    {
        ethUsdPriceFeed = AggregatorV3Interface(_ETHpriceFeedAddress);
        linkUsdPriceFeed = AggregatorV3Interface(_LINKpriceFeedAddress);
        fee = _fee;
        keyhash = _keyhash;
        //initial mint will be used to supply liquidity to DEX
        _mint(msg.sender, initialSupply);
        //initiate jackpot[0-6] payouts to be 0
        //jackpotPaid represents the founder tokens
        jackpotPaid = new uint256[](9);
        //jackpotPast for when reward rates lowered, saves the current values of each jackpot
        jackpotPast = new uint256[](9);
        //set the weights for each jackpot
        jackpotWeight = new uint256[](9);
        jackpotWeight[0] = 45;
        jackpotWeight[1] = 20;
        jackpotWeight[2] = 10;
        jackpotWeight[3] = 5;
        jackpotWeight[4] = 4;
        jackpotWeight[5] = 3;
        jackpotWeight[6] = 2;
        jackpotWeight[7] = 1;
        jackpotWeight[8] = 10;
        //set the rewards per block
        rewardsPerBlock = _rewards;
        //set the odds of each jackpot (1 in x per ETH)
        //added 10**18 to end as unit taken in wei
        jackpotOdds = new uint256[](8);
        jackpotOdds[0] = (2**11) * (10**18);
        jackpotOdds[1] = (2**9) * (10**18);
        jackpotOdds[2] = (2**7) * (10**18);
        jackpotOdds[3] = (2**6) * (10**18);
        jackpotOdds[4] = (2**5) * (10**18);
        jackpotOdds[5] = (2**4) * (10**18);
        jackpotOdds[6] = (2**3) * (10**18);
        jackpotOdds[7] = (2**2) * (10**18);
        //set the startBlock with current blocktime
        startBlock = block.number;
    }

    /**
     * 1% fee on trades to be sent to owner for supplying LINK for VRF cordinator
     * Ensure that the 1% fee covers the LINK fee required per trade
     */
    function getMinimumTradeSize() public view returns (uint256) {
        //pull prices for ethusd and linkusd from chainlink oracles
        (, int256 ethPrice, , , ) = ethUsdPriceFeed.latestRoundData();
        (, int256 linkPrice, , , ) = linkUsdPriceFeed.latestRoundData();
        //set minimum price, such that 1% fee covers oracle gas cost (e.g. 0.2 LINK)
        uint256 minimumTradeSize = ((uint256(linkPrice) * fee) /
            uint256(ethPrice)) * 100;
        return minimumTradeSize;
    }

    /**
     * Get the maximum trade size
     * Trades cannot be greater than 1% of the house balance (w/ 10x max multiplier, 5% maximum loss from house at a time)
     */
    function getMaximumTradeSize() public view returns (uint256) {
        //CHANGE TO 100 ON REAL LAUNCH
        return address(house).balance / 20;
    }

    /**
     * Initiates a trade with weth to the DojoHouse
     * User passes in a "belt" for the odds of their trade
     * FOR SPIN TRADE:
     * 1 = whitebelt, 2 = blue belt, 3 = black belt
     * FOR ALL OR NOTHING TRADE:
     * 4 = whitebelt, 5 = blue belt, 6 = black belt
     */
    function initiateTrade(uint8 _belt) external payable {
        //ensure trade is between minimum and maximum
        require(
            msg.value > getMinimumTradeSize() &&
                msg.value < getMaximumTradeSize(),
            "Invalid trade amount!"
        );
        //ensure contract has enough link
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Please wait for LINK top up"
        );
        //ensure that they do not have a pending trade (SMALL OR BIG)
        require(
            AddressToPendingTrade[address(tx.origin)]._amount == 0,
            "You already have a trade in progress"
        );
        //add their trade to mapping
        bytes32 newRequest = requestRandomness(keyhash, fee);
        //add their pending trade to mapping of addresses (use tx.origin incase called by external router)
        AddressToPendingTrade[address(tx.origin)] = PendingTrade(
            newRequest,
            //add the bounty to their trade size
            msg.value + bounty,
            _belt
        );
        //reset the bounty
        bounty = 0;
        //iterate over each of the small trades, and update the request ID
        for (uint8 i = 0; i < smallTrades.length; i++) {
            AddressToPendingTrade[smallTrades[i]]._requestID = newRequest;
        }
        //delete the small trade wait list
        smallTrades = new address[](0);
        emit RequestedRandomness(newRequest);
    }

    /**
     * Initiates a trade smaller than the minimum trade size
     */
    function initiateSmallTrade(uint8 _belt) external payable {
        //require that they dont have a regular trade
        require(
            AddressToPendingTrade[address(tx.origin)]._amount == 0,
            "You already have a trade in progress"
        );
        //require that the trade size doens't exceed maximum
        require(msg.value < getMaximumTradeSize(), "Insufficent House Balance");
        //only a maximum of 50 small trades at a time to ensure gas limits by VRF
        require(smallTrades.length <= 50, "Small trade waitlist current full");
        //make sure its a non-zero trade
        require(msg.value > 0);
        //add their address to the small trades
        smallTrades.push(tx.origin);
        //add their address to pendingTrade with inital value to be "small trade"
        AddressToPendingTrade[address(tx.origin)] = PendingTrade(
            bytes32(""),
            (msg.value * 49) / 50,
            _belt
        );
        bounty += msg.value / 50;
    }

    /**
     * Checks if the user has a current trade pending
     */
    function checkPendingTrade(address _address) external view returns (bool) {
        if (AddressToPendingTrade[_address]._amount != 0) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * Checks if the user has a trade to claim
     */
    function checkClaimableTrade(address _address)
        external
        view
        returns (bool)
    {
        bytes32 requestID = AddressToPendingTrade[_address]._requestID;
        if (requestToRandom[requestID] != 0) {
            return true;
        }
        return false;
    }

    /**
     * Claim the payout from a trade
     */
    function claimTrade()
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        //requires that the caller has a requestID
        require(
            AddressToPendingTrade[address(tx.origin)]._amount != 0,
            "You have no trade in progress"
        );
        //require there is enough money in pool to pay out at least 10x
        require(
            address(house).balance / 11 >=
                AddressToPendingTrade[address(tx.origin)]._amount,
            "insufficent house balance"
        );
        //get their pending trade info (requestID, amount, level)
        bytes32 requestID = AddressToPendingTrade[address(tx.origin)]
            ._requestID;
        //require their requestID to have a random number != 0
        require(
            requestToRandom[requestID] != 0,
            "Your request ID has not been fulfilled yet"
        );
        uint256 size = AddressToPendingTrade[address(tx.origin)]._amount;
        uint8 belt = AddressToPendingTrade[address(tx.origin)]._level;
        //get their random number
        uint256 random = requestToRandom[requestID];
        //spin the dojo token jackpot
        uint256 winnings = _spinJackpot(random, size, address(tx.origin));
        //claim payout from House
        //if spin trade
        uint256 payout = 0;
        uint256 remainder;
        if (belt <= 3) {
            (payout, remainder) = house.spinTrade{value: size}(
                belt,
                random,
                //uses msg.sender here as it pays to router not origin
                payable(address(msg.sender))
            );
        } else {
            (payout, remainder) = house.allOrNothingTrade{value: size}(
                belt,
                random,
                payable(address(msg.sender))
            );
        }
        //remove the pending trade
        delete AddressToPendingTrade[address(tx.origin)];
        emit ClaimTrade(payout, winnings, remainder);
        return (payout, winnings, remainder);
    }

    /**
     * Function to be called by VRF coordinator
     */
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness)
        internal
        override
    {
        //set the random number to the request
        requestToRandom[_requestId] = _randomness;
    }

    /**
     * Initiate change in the house contract
     */
    function initiateSetHouse(address _house) public onlyOwner {
        //hosue can only be updated after 28,800 blocks (~1 day assuming 3s block)
        //NEED TO CHANGE CODE FOR TIME LOCK
        uint256 resetTime = block.number + 0;
        //uint256 resetTime = block.number + 28,800; <CHANGE POST TEST>
        nextHouse = newHouse(resetTime, _house);
    }

    /**
     * Change the house once time lock has passed
     */
    function setHouse() public onlyOwner {
        //require enough time has passed
        require(block.number >= nextHouse.changeBlock, "timelock not expired");
        house = DojoHouse(nextHouse.newHouse);
    }

    /**
     * Set the house contract after it has been created
     */
    function setKeyhash(bytes32 _keyhash) public onlyOwner {
        keyhash = _keyhash;
    }

    /**
     * Set the link fee paid to chainlink nodes
     */
    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    /**
     * View the current size of given jackpot number
     */
    function viewJackpots(
        uint8 number /// @title A title that should describe the contract/interface
    ) public view returns (uint256 size) {
        //Get the total possible mint for given jackpot
        uint256 total = ((block.number - startBlock) *
            rewardsPerBlock *
            jackpotWeight[number]) / 100;
        //Get the total claimed from the jackpot
        uint256 claimed = jackpotPaid[number];
        //Get the past jackpot amount
        uint256 past = jackpotPast[number];
        size = total + past - claimed;
    }

    /**
     * Only Owner to set the rewards per block for DOJO
     * Rewards can only be decrease (to prevent potenital rug attempt)
     */
    function setRewardsRate(uint256 rewardRate) public onlyOwner {
        //new rate must be lower than old
        require(
            rewardRate < rewardsPerBlock,
            "new rate must be lower than previous"
        );
        //add each current jackpot to jackpot past
        for (uint8 i = 0; i < 9; i++) {
            jackpotPast[i] += viewJackpots(i);
        }
        //reset the start time
        startBlock = block.number;
        //set new rewards rate
        rewardsPerBlock = rewardRate;
    }

    /**
     * Getter function for current pending trade levell
     */
    function getPendingLevel(address user) public view returns (uint8) {
        return AddressToPendingTrade[user]._level;
    }

    /**
     * Getter function for current pending trade amount
     */
    function getPendingAmount(address user) public view returns (uint256) {
        return AddressToPendingTrade[user]._amount;
    }

    /**
     * Only owner to claim founder treasury tokens
     */
    function claim() external onlyOwner {
        _mint(owner(), viewJackpots(8));
        jackpotPaid[8] += viewJackpots(8);
    }

    /**
     * Max function copied from OpenZeppelin to restrict odds on jackpots
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? b : a;
    }

    /**
     * Internal. A player gets a chance at winning each jackpot
     * If they are successful, they will mint DOJO tokens based on 50% of the size of the current jackpot
     */
    function _spinJackpot(
        uint256 _random,
        uint256 _size,
        address _player
    ) private returns (uint256) {
        uint256 winnings = 0;
        uint256 splitRandom;
        //iterate over each jackpot (not including jackpot[8])
        for (uint8 i = 0; i < 8; i++) {
            //rehash to split random number
            splitRandom = uint256(keccak256(abi.encode(_random, i)));
            //get the odd of hitting, capped at 1 in 2
            uint256 odds = max(2, jackpotOdds[i] / _size);
            if (splitRandom % odds == 1) {
                //jackpot[i] hit, add 50% of this jackpot to their winnings
                winnings += (viewJackpots(i) / 2);
                //update total paid by that jackpot
                jackpotPaid[i] += (viewJackpots(i) / 2);
            }
        }
        //check that there are winnings to claim
        if (winnings != 0) {
            //if so, mint that many tokens to the player
            _mint(_player, winnings);
        }
        //check if they are the biggest winner and update
        if (winnings > winners[0].amount) {
            winners[0] = Winner(tx.origin, winnings);
        }
        //update the recent winner
        if (winnings > 0) {
            winners[1] = Winner(tx.origin, winnings);
        }
        return winnings;
    }
}
