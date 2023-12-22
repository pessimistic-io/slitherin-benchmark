/* solhint-disable */
// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import "./IUniswapV2Router02.sol";

// CUSTOM FEE:
// Interface to add get amounts in/out with custom fee amount
interface IUniswapV2Router02CustomFee is IUniswapV2Router02 {
	function getAmountOutWithFee(uint amountIn, uint reserveIn, uint reserveOut, uint fee)
        external
        view
        returns (uint amountOut);

    function getAmountInWithFee(uint amountOut, uint reserveIn, uint reserveOut, uint fee)
        external
        view
        returns (uint amountIn);

    function getAmountsOutWithFee(uint amountIn, address[] calldata path)
        external
        view
        returns (uint[] memory amounts);

    function getAmountsInWithFee(uint amountOut, address[] calldata path)
        external
        view
        returns (uint[] memory amounts);
}
/* solhint-disable */
