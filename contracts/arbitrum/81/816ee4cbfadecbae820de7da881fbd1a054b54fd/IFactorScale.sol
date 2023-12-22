// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./VeBalanceLib.sol";

interface IFactorScale {

    event AddVault(uint64 indexed chainId, address indexed vault);

    event RemoveVault(uint64 indexed chainId, address indexed vault);

    event Vote(address indexed user, address indexed vault, uint64 weight, VeBalance vote);

    event VaultVoteChange(address indexed vault, VeBalance vote);

    event SetFctrPerSec(uint256 newFctrPerSec);

    event BroadcastResults(
        uint64 indexed chainId,
        uint128 indexed wTime,
        uint128 totalFctrPerSec
    );

    function applyVaultSlopeChanges(address vault) external;

    function getWeekData(uint128 wTime, address[] calldata vaults)
        external
        view
        returns (
            bool isEpochFinalized,
            uint128 totalVotes,
            uint128[] memory vaultVotes
        );

    function getVaultTotalVoteAt(address vault, uint128 wTime) external view returns (uint128);

    function finalizeEpoch() external;

    function getBroadcastResultFee(uint64 chainId) external view returns (uint256);

    function broadcastResults(uint64 chainId) external payable;

    function isVaultActive(address vault) external view returns (bool);
}

