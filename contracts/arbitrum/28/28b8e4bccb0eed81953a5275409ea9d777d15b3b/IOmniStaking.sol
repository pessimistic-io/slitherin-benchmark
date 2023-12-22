// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IOmniStaking {
    function stakedAmounts(address _user) external view returns (uint256);
}

