// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./DojoHouse.sol";

/**
 *  Dojobar is forked form SushiBar
 *  This contract handles swapping to and from xDoji, DegenDojo's staking token.
 */
contract DojoBar is ERC20("DojoBar", "xDOJO") {
    IERC20 public immutable dojo;
    IUniswapV2Router02 public router;

    constructor(address _dojo, address _router) public {
        dojo = IERC20(_dojo);
        router = IUniswapV2Router02(_router);
    }

    /**
     * Enter the bar. Pay some DOJOs. Earn some shares.
     * Locks Dojo and mints xDojo
     */
    function enter(uint256 amount) public returns (uint256 what) {
        //only allow EOA to enter
        require(msg.sender == tx.origin);
        // Gets the amount of Dojo locked in the contract
        uint256 totalDojo = dojo.balanceOf(address(this));
        // Gets the amount of xDojo in existence
        uint256 totalShares = totalSupply();
        // If no xDojo exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalDojo == 0) {
            what = amount;
            _mint(msg.sender, amount);
        }
        // Calculate and mint the amount of xDojo the Dojo is worth. The ratio will change overtime, as xDojo is burned/minted and Dojo deposited + gained from fees / withdrawn.
        else {
            what = (amount * totalShares) / totalDojo;
            _mint(msg.sender, what);
        }
        // Lock the Dojo in the contract
        dojo.transferFrom(msg.sender, address(this), amount);
    }

    // Leave the bar. Claim back your Dojo.
    // Unlocks the staked + gained Dojo and burns xDOJO
    function leave(uint256 share) public returns (uint256 what) {
        // Gets the amount of xDojo in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Dojo the xDojo is worth
        uint256 what = (share * (dojo.balanceOf(address(this)))) / totalShares;
        _burn(msg.sender, share);
        dojo.transfer(msg.sender, what);
    }

    /**
     * Get the current ratio of Dojo:xDojo
     */
    function getRatio() public view returns (uint256) {
        return dojo.balanceOf(address(this)) / totalSupply();
    }

    /**
     * Public function to unwrap the DLP tokens issued to the Dojo bar, and convert it to DOJO
     */
    function collectFees() public {
        //use uniswapv2
        uint256 amountOut = 0;
        uint256 deadline = block.timestamp + 30;
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(dojo);
        router.swapExactETHForTokens{value: address(this).balance}(
            0,
            path,
            address(this),
            deadline
        );
    }

    receive() external payable {}
}
