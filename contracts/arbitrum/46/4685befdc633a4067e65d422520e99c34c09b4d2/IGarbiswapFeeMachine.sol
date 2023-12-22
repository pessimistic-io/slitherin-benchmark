// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "./IERC20.sol";

interface IGarbiswapFeeMachine {
    function processTradeFee(IERC20 token, address trader) external;
}
