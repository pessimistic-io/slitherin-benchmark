// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IFairAuction {
    function getExpectedClaimAmount(address account) external view returns (uint256);
}
