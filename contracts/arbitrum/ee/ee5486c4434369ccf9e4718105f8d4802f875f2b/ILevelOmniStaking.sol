// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILevelOmniStaking {
    function stakedAmounts(address _user) external view returns (uint256);
}

