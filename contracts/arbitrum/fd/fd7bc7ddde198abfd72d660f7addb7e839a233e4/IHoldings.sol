// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

interface IHoldings {
    function getShareHoldings(address account) external view returns (uint256);

    function hasEnoughHoldings(
        address account,
        uint256 amount
    ) external view returns (bool);

    function updateHolderInList(address account) external;

    function removeEmptyHolderFromList(address account) external;
}

