// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";

interface ILiquidityStakingRewards {

    // Views
    function liquidityTokenId() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    // Mutative

    function increaseLiquidityStake(INonfungiblePositionManager.IncreaseLiquidityParams calldata params) external payable;

    function decreaseLiquidityStake(uint128 liquidityAmount, uint256 amount0Min, uint256 amount1Min) external;

    function claimReward() external;

    //function exit() external;

    function notifyRewardAmount(uint256 reward, uint256 rewardsDuration_) external;

}

