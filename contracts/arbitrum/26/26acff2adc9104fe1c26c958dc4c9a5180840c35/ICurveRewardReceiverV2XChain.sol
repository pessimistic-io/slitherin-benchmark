// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICurveRewardReceiverV2XChain {
    function claimExtraRewards() external;

    function claimExtraRewards(address _curveGauge, address _sdGauge, address _user) external;

    function init(address _registry, address _curveGauge, address _sdGauge, address _locker) external;

    function notifyReward(address _token, uint256 _amount) external;
}
