// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ILockBox.sol";

interface IRewardHandler is ILockBox {
    function addRewards(address, address, uint256) external;
    function updateRewards(address, address) external;
    function transferNondistributableRewardsTo(address, address) external;
    function claimRewardsOfAccount(address, address) external;
    function claimRewards(address) external;
    function getAvailableRewards(address, address)
        external
        view
        returns(uint256);
    function getDistToken(address) external view returns(address);
}

