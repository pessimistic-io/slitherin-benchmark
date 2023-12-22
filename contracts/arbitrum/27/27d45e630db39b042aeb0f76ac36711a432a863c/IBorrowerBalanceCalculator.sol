// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Pool.sol";

interface IBorrowerBalanceCalculator {

    function balanceInTermsOf(address token, address borrower) external view returns (int balance);
}
