// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./IUpgradeableBase.sol";
import "./ICurveGauge.sol";
import "./ISelfStakingERC20.sol";

interface IREWardSplitter is IUpgradeableBase
{
    error GaugeNotExcluded();
    
    function isREWardSplitter() external view returns (bool);
    function splitRewards(uint256 amount, ISelfStakingERC20 selfStakingERC20, ICurveGauge[] memory gauges) external view returns (uint256 selfStakingERC20Amount, uint256[] memory gaugeAmounts);

    function approve(IERC20 rewardToken, address[] memory targets) external;
    function addReward(uint256 amount, ISelfStakingERC20 selfStakingERC20, ICurveGauge[] memory gauges) external;
    function addRewardPermit(uint256 amount, ISelfStakingERC20 selfStakingERC20, ICurveGauge[] memory gauges, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    
    function addRewardToGauge(ICurveGauge gauge, IERC20 rewardToken, uint256 amount) external;
    function addRewardToGaugePermit(ICurveGauge gauge, IERC20Full rewardToken, uint256 amount, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    function multiAddReward(IERC20 rewardToken, ICurveGauge gauge, uint256 gaugeAmount, ISelfStakingERC20 selfStakingERC20, uint256 splitAmount) external;
    function multiAddRewardPermit(IERC20Full rewardToken, ICurveGauge gauge, uint256 gaugeAmount, ISelfStakingERC20 selfStakingERC20, uint256 splitAmount, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}
