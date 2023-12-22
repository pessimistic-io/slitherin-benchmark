// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { IERC20 } from "./IERC20.sol";

interface IFractBaseStrategy {
    function enterPosition(IERC20 token, uint256 amount, uint256 minAmount) external;
    function exitPosition(IERC20 token, uint256 amount, uint256 minAmount) external;
    function claimRewards() external;
    function withdraw(IERC20, uint256) external;
    function deposit(IERC20, uint256) external;
}
