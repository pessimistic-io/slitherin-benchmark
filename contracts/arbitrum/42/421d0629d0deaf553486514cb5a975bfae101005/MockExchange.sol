// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./IERC20Decimals.sol";

contract MockExchange {
    constructor() {}

    function getAmountsOut(uint256 _amount, address[] memory _path) external view returns(uint256[] memory amountsOut) {
        amountsOut = new uint256[](_path.length);

        uint256 decimalDiff = IERC20Decimals(_path[0]).decimals() -
            IERC20Decimals(_path[1]).decimals();

        uint256 amountOut = _amount / 10**decimalDiff;

        amountsOut[0] = _amount;
        amountsOut[1] = amountOut;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        require(block.timestamp <= deadline);

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // path[0] is native token with 18 decimals
        // path[1] is MockUSDC with 6 decimals
        uint256 decimalDiff = IERC20Decimals(path[0]).decimals() -
            IERC20Decimals(path[1]).decimals();

        // E.g. amountIn = 1e18
        //      amountOut = 1e6
        amountOut = amountIn / 10**decimalDiff;

        IERC20(path[1]).transfer(to, amountOut);
    }
}

