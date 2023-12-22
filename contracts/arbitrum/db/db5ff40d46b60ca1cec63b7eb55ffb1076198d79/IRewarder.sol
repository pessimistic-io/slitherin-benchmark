// SPDX-License-Identifier: MIT

pragma solidity >0.6.0;

interface IRewarder {
    function rewardToken() external returns(address);
}



        //covert r0,r1 to t0  //route r0 to t0, route r1 to t0
        //handle single asset liquidity
        //(reward0, reward1, tok0,tok1)
        //(reward0== tok0/tok1, reward1 == token0/token1)    
        //S1
        //r0/r1 = t0/t1
        //convert r1 to r0 //route r0 to r1
        //handle single asset liquidity

        //S2
        //
        //r0 & r1 = t0 & t1;
        //r0>r1  convert r0: r1 //route r0 to r1
        //handle single asset liquidity

        
        // if(sushiBal>0){
        //     IUniswapV2Router02(router).swapExactTokensForTokens(
        //         sushiBal,
        //         0,
        //         route0,
        //         address(this),
        //         block.timestamp
        //     );   
        // }
        // if(rewardBal>0) {
        //     IUniswapV2Router02(router).swapExactTokensForTokens(
        //         rewardBal,
        //         0,
        //         route1,
        //         address(this),
        //         block.timestamp
        //     );
        // }

        // (uint112 res0,, ) = IUniswapV2Pair(asset).getReserves();

        // uint256 amountToSwap = _calculateSwapInAmount(res0,IERC20(lpToken0).balanceOf(address(this)));
        // address [] memory path = new address[](2);
        // path[0] = IUniswapV2Pair(asset).token0();
        // path[1] = IUniswapV2Pair(asset).token1();
        // IUniswapV2Router02(router).swapExactTokensForTokens(
        //     amountToSwap,
        //     0,
        //     path,
        //     address(this),
        //     block.timestamp
        // );
        // uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        // uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        // IERC20(lpToken0).approve(router, lp0Bal);
        // IERC20(lpToken1).approve(router, lp1Bal);
        // (, ,lpAmount) = IUniswapV2Router02(router).addLiquidity(
        //     lpToken0,
        //     lpToken1,
        //     lp0Bal,
        //     lp1Bal,
        //     1,
        //     1,
        //     address(this),
        //     block.timestamp
        // );
