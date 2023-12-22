// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IBadgeManager {
    function getBadgeMultiplier(address _depositorAddress) external view returns (uint256);
}
