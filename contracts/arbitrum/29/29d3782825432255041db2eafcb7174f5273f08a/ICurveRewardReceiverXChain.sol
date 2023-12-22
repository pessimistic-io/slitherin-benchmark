// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICurveRewardReceiverXChain {
    function claimExtraRewards(address, address, address) external;

    function init(address _registry) external;
}
