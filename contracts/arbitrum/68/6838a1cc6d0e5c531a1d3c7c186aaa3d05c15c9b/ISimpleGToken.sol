// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISimpleGToken {
    function manager() external view returns (address);

    function gov() external view returns (address);

    function currentEpoch() external view returns (uint);

    function currentEpochStart() external view returns (uint);

    function currentEpochPositiveOpenPnl() external view returns (uint);

    function updateAccPnlPerTokenUsed(
        uint prevPositiveOpenPnl,
        uint newPositiveOpenPnl
    ) external returns (uint);

    function sendAssets(uint assets, address receiver) external;

    function receiveAssets(uint assets, address user) external;

    function distributeReward(uint assets) external;

    function currentBalanceUsdc() external view returns (uint);
}

