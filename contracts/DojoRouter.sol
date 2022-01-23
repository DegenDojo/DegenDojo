// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

//NEED TO CHANGE TO PANCAKE LIB
import "./libraries/PancakeLibrary.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IWETH.sol";
import "./DegenDojo.sol";

contract DojoRouter {
    address public immutable factory;
    DegenDojo private immutable dojo;
    address private immutable WETH;
    event ClaimTokenTrade(
        uint256 tokenPayout,
        uint256 winnings,
        uint256 remainder
    );

    constructor(
        address _dojo,
        address _factory,
        address _weth
    ) {
        dojo = DegenDojo(_dojo);
        factory = _factory;
        WETH = _weth;
    }

    /**
     * fork from uniswap router
     */
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    /**
     * Inititaes a trade to swap ETH for a given amount of tokens
     * Uses uniswapV2 router for the trades
     */
    function swapETHforTokens(uint256 belt) external payable {
        if (msg.value > dojo.getMinimumTradeSize()) {
            dojo.initiateTrade{value: msg.value}(belt);
        } else {
            dojo.initiateSmallTrade{value: msg.value}(belt);
        }
    }

    /**
     * Claims a swap from ETH to given token, first collect payout from the house
     * Then find pool and swap
     * NOTE: minOut input if for 1 BNB. Trade size is unknown, so we do slippage check on a 1 BNB trade
     * If slippage too high, sender can always simply claim back ETH instead from DegenDojo
     */
    function claimETHTrade(
        uint256 minOut,
        uint256 deadline,
        address tokenOut
    ) external ensure(deadline) {
        //first claim back the eth
        (uint256 payout, uint256 winnings, uint256 remainder) = dojo
            .claimTrade();
        //no need to swap if no payout
        if (payout == 0) {
            return;
        }
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = tokenOut;
        //Slippage check first
        uint256[] memory slippageAmounts = PancakeLibrary.getAmountsOut(
            factory,
            10**18,
            path
        );
        require(
            slippageAmounts[slippageAmounts.length - 1] >= minOut,
            "Insufficent output"
        );
        //now regular check for amounts with payout amount
        uint256[] memory amounts = PancakeLibrary.getAmountsOut(
            factory,
            payout,
            path
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(
                PancakeLibrary.pairFor(factory, path[0], path[1]),
                amounts[0]
            )
        );
        _swap(amounts, path, msg.sender);
        emit ClaimTokenTrade(amounts[amounts.length - 1], winnings, remainder);
    }

    //copied and tweaked from uniswap router
    function swapTokensForETH(
        uint256 amountIn,
        address tokenIn,
        uint256 belt,
        uint256 minOut,
        uint256 deadline
    ) external ensure(deadline) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = WETH;

        uint256[] memory amounts = PancakeLibrary.getAmountsOut(
            factory,
            amountIn,
            path
        );
        //make sure of slippage
        require(amounts[amounts.length - 1] >= minOut, "Insufficient outout");
        //add back require for amountOutMin
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            PancakeLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        if (amounts[amounts.length - 1] > dojo.getMinimumTradeSize()) {
            dojo.initiateTrade{value: amounts[amounts.length - 1]}(belt);
        } else {
            dojo.initiateSmallTrade{value: amounts[amounts.length - 1]}(belt);
        }
        //trade can be claimed straight from house contract
    }

    //copied directly from uniswap router
    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) private {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = PancakeLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? PancakeLibrary.pairFor(factory, output, path[i + 2])
                : _to;
            IPancakePair(PancakeLibrary.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    receive() external payable {}

    function getAmountOut(
        uint256 amountIn,
        address tokenOut,
        address tokenIn
    ) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint256[] memory amounts = PancakeLibrary.getAmountsOut(
            factory,
            amountIn,
            path
        );
        return amounts[1];
    }
}
