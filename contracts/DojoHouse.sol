// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * DojoHouse represents pooled liquidity from users to act as the house
 */

contract DojoHouse is ERC20("DojoLiquidity", "DLP") {
    address payable public immutable bar;
    address public immutable dojo;
    address payable public immutable treasury;
    uint256 public totalVolume;
    uint256 private tradeNonce;

    constructor(
        address payable _bar,
        address _dojo,
        address payable _treasury
    ) public {
        bar = _bar;
        dojo = _dojo;
        treasury = _treasury;
        tradeNonce = 0;
    }

    /**
     * Enter the DojoHouse
     * - receive DLP tokens based on the current WETH-Supply ratio
     * - accure gains/losses from house edge over time
     */
    function enter() external payable returns (uint256 what) {
        //check to prevent flash loans from entering
        require(msg.sender == tx.origin, "EOA only");
        //mint at 1:1 if contract is currently empty
        if (totalSupply() == 0 || address(this).balance == msg.value) {
            //issue DLP to user
            what = msg.value;
            _mint(msg.sender, what);
        } else {
            //otherwise, mint at the current
            what =
                (msg.value * totalSupply()) /
                (address(this).balance - msg.value);
            //issue DLP to user
            _mint(msg.sender, what);
        }
    }

    /**
     * Leave the DojoHouse
     * - claim back your ETH and burn your DLP
     */
    function leave(uint256 _share) external returns (uint256 what) {
        uint256 totalShares = totalSupply();
        uint256 totalWeth = address(this).balance;
        //calcuate how much WETH is to be withdrawn
        what = (_share * totalWeth) / totalShares;
        //burn the shares
        _burn(msg.sender, _share);
        address payable owner = payable(msg.sender);
        owner.transfer(what);
    }

    /**
     * Spin the wheel and receive an random amount of ETH
     * Wheel of fortune odds are:
     * For whitebelt = 50% 0.5x, 25% 1.25x, 13% 1.4x, 8% 1.65x, 4% 2x
     * For bluebelt  = 67% 0.5x, 22% 1.5x , 7%  2x  , 3% 3.4x , 1% 5x
     * For blackbelt = 67% 0x,   22% 1.75x, 7%  3.3x, 3% 8x   , 1% 10x
     * House edge is always 4.3-4.4% with a portion going as follows:
     *  -1% fee given to Treasury
     *  -1% fee given to DojoBar
     */
    function spinTrade(
        uint256 _belt,
        uint256 _random,
        address payable _to
    ) external payable returns (uint256, uint256) {
        //function only to be called by DegenDojo
        require(address(msg.sender) == dojo, "DOJO only");
        //the base rate if lose
        uint256 base = 50;
        //initiate each multiplier for white belt to be safe
        uint256 multiplier1 = 125;
        uint256 multiplier2 = 140;
        uint256 multiplier3 = 165;
        uint256 multiplier4 = 200;
        //initate breakpoints that are for belt 2, 3
        uint256 breakpoint1 = 67;
        uint256 breakpoint2 = 89;
        uint256 breakpoint3 = 96;
        uint256 breakpoint4 = 99;
        //spin trades have multiple multipliers
        if (_belt == 1) {
            //for white belt
            breakpoint1 = 50;
            breakpoint2 = 75;
            breakpoint3 = 88;
            breakpoint4 = 96;
        } else if (_belt == 2) {
            //blue belt
            multiplier1 = 150;
            multiplier2 = 200;
            multiplier3 = 340;
            multiplier4 = 500;
        } else {
            //black belt
            base = 0;
            multiplier1 = 175;
            multiplier2 = 330;
            multiplier3 = 800;
            multiplier4 = 1000;
        }
        //rehash the random number. hashed to tradeNonce
        uint256 rehashRandom = uint256(
            keccak256(abi.encode(_random, tradeNonce))
        );
        //increment tradeNonse
        tradeNonce++;
        uint256 remainder = rehashRandom % 100;
        //first set the payout to amount if loss
        uint256 payout = ((base * msg.value) / 100);
        if (remainder < breakpoint1) {
            //for belt 1, 50%, for belt2,3, 67%
            //no need to change payout
        } else if (remainder < breakpoint2) {
            //for belt 1, 25%, for belt2,3, 22%
            payout = (multiplier1 * msg.value) / 100;
        } else if (remainder < breakpoint3) {
            //for belt 1, 13%, for belt2,3, 7%
            payout = (multiplier2 * msg.value) / 100;
        } else if (remainder < breakpoint4) {
            //for belt1, 8%, for belt2,3 3%
            payout = (multiplier3 * msg.value) / 100;
        } else {
            //for belt1, 4%, for belt2,3 1%
            payout = (multiplier4 * msg.value) / 100;
        }
        //send 1% fees to treasury and bar
        treasury.transfer(msg.value / 100);
        bar.transfer(msg.value / 100);
        //transfer the payout
        if (payout != 0) {
            _to.transfer(payout);
        }
        //update total volume
        totalVolume += msg.value;
        //return payout
        return (payout, remainder);
    }

    /**
     * Spin the wheel and receive an random amount of WETH
     * If they lose, nothing is returned
     * If they win, depending on type, user will get back either 2x,3x,5.05x
     * House edge is always 4-4.05% with a portion going as follows:
     *  -1% fee given to Treasury
     *  -1% fee given to DojoBar
     */
    function allOrNothingTrade(
        uint256 _belt,
        uint256 _random,
        address payable _to
    ) external payable returns (uint256, uint256) {
        //function only to be called by DegenDojo
        require(msg.sender == dojo, "DOJO Only");
        //initiate breakpoints to white belt
        uint256 multiplier = 200;
        uint256 breakpoint = 52;
        //check belt level if blue or black and change the payout/odds
        if (_belt == 5) {
            multiplier = 300;
            breakpoint = 68;
        } else if (_belt == 6) {
            multiplier = 505;
            breakpoint = 81;
        }
        //send 1% fees to treasury and bar
        treasury.transfer(msg.value / 100);
        bar.transfer(msg.value / 100);
        //initiate payout to a loss
        uint256 payout = 0;
        //rehash the random number
        uint256 rehashRandom = uint256(
            keccak256(abi.encode(_random, tradeNonce))
        );
        //increment tradeNonce
        tradeNonce++;
        //get the remainder
        uint256 remainder = rehashRandom % 100;
        if (remainder >= breakpoint) {
            //set payout to win if greater than breakpoint
            payout = (multiplier * msg.value) / 100;
        }
        if (payout != 0) {
            _to.transfer(payout);
        }
        //update total volume
        totalVolume += msg.value;
        return (payout, remainder);
    }

    /**
     * Get the DLP value of ETH:DLP
     */
    function getValue() external view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        } else {
            return (address(this).balance * (10**18)) / totalSupply();
        }
    }
}
