// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IFbaDaoMasterChef {
    function getReleasedReward() external view returns (uint256);
}

