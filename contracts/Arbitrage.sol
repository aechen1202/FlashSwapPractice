// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import "forge-std/console.sol"; 

// This is a practice contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    struct CallbackData {
        address pool;
        address tokenWETH;
        address tokenUSDC;
        uint256 amountUsdc;
        uint256 amountUsdcReturn;
    }
    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        // TODO
        CallbackData memory callbackData = abi.decode(data,(CallbackData));
        IERC20(callbackData.tokenWETH).transfer(callbackData.pool, amount0);
        IUniswapV2Pair(callbackData.pool).swap(0, callbackData.amountUsdc, address(this), new bytes(0));
        IERC20(callbackData.tokenUSDC).transfer(msg.sender, callbackData.amountUsdcReturn);
    }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // TODO

        uint112 reserveEth0;
        uint112 reserveUsdc0;
        (reserveEth0 ,reserveUsdc0 ,) = IUniswapV2Pair(priceLowerPool).getReserves();
        uint256 amountUsdc0 = _getAmountIn(borrowETH , reserveUsdc0, reserveEth0);
        
        uint112 reserveEth1;
        uint112 reserveUsdc1;
        (reserveEth1 ,reserveUsdc1 ,) = IUniswapV2Pair(priceHigherPool).getReserves();
        uint256 amountUsdc1 = _getAmountIn(borrowETH , reserveUsdc1, reserveEth1);
        
        
        if(amountUsdc0 < amountUsdc1){
            uint256 amountUsdcSwap = _getAmountOut(borrowETH , reserveEth1, reserveUsdc1);
            CallbackData memory callbackData = CallbackData(
                priceHigherPool
                ,IUniswapV2Pair(priceHigherPool).token0()
                ,IUniswapV2Pair(priceHigherPool).token1()
                ,amountUsdcSwap
                ,amountUsdc0
                );
            IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(callbackData));
        }
        else{
            uint256 amountUsdcSwap = _getAmountOut(borrowETH , reserveEth0, reserveUsdc0);
            CallbackData memory callbackData = CallbackData(
                priceLowerPool
                ,IUniswapV2Pair(priceHigherPool).token0()
                ,IUniswapV2Pair(priceHigherPool).token1()
                ,amountUsdcSwap
                ,amountUsdc1
                );
            IUniswapV2Pair(priceHigherPool).swap(borrowETH, 0, address(this),abi.encode(callbackData));
        }
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
