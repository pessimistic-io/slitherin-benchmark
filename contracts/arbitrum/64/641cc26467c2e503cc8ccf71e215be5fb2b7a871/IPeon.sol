// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IiToken.sol";
import "./IRewardDistributorV3.sol";
import "./IERC20.sol";

interface IPeon {
    function supply(IiToken iToken, IERC20 token, uint256 amount) external;
    function withdraw(IiToken iToken, IERC20 token, uint256 amount) external;
    function borrow(IiToken iToken, IERC20 token, uint256 amount) external;
    function repay(IiToken iToken, IERC20 token, uint256 amount) external;
    function claimReward(IRewardDistributorV3 rewardDistributor, IERC20 token) external returns (uint256);
    function getBalanceOfUnderlying(IiToken iToken) external returns (uint256);
    function getBorrowBalanceCurrent(IiToken iToken) external returns (uint256);
}
