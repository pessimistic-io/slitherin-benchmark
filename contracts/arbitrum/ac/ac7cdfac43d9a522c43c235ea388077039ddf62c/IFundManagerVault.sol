// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFundManagerVault {
    struct FundManager {
        address fundManagerAddress;
        uint256 fundManagerProfitNumerator;
    }

    function getWbtcBalance() external view returns (uint256);

    function getAllFundManagers() external view returns (FundManager[4] memory);

    function setFundManagerByIndex(
        uint256 index,
        address fundManagerAddress,
        uint24 fundManagerProfitNumerator
    ) external;

    function allocate() external;
}

