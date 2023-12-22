// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ITokenStrategy.sol";
import "./ERC20.sol";

interface ILpTokenStrategy is ITokenStrategy  {
    function inputToken() external view returns (IERC20);
}


