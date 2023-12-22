// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./IUpgradeableBase.sol";
import "./ICurveGauge.sol";
import "./ICanMint.sol";

interface IRECurveMintedRewards is IUpgradeableBase
{
    event RewardRate(uint256 perDay, uint256 perDayPerDollar);

    error NotRewardManager();
    error MaxDollarsExceeded();
    error MaxDollarsTooHigh();

    function isRECurveMintedRewards() external view returns (bool);
    function gauge() external view returns (ICurveGauge);
    function lastRewardTimestamp() external view returns (uint256);
    function rewardToken() external view returns (ICanMint);
    function perDay() external view returns (uint256);
    function perDayPerDollar() external view returns (uint256);
    function isRewardManager(address user) external view returns (bool);
    
    function sendRewards(uint256 maxDollars) external;
    function sendAndSetRewardRate(uint256 perDay, uint256 perDayPerDollar, uint256 maxDollars) external;
    function setRewardManager(address manager, bool enabled) external;
}
