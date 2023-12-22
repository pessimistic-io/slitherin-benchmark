// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

interface IHelper {

    function getPriceOfGLP() external view returns (uint256);

    function getPriceOfRewardToken() external view returns (uint256);

    function getRewardToken() external view returns (address);

    function getTotalClaimableFees(address) external view returns (uint256);
}
