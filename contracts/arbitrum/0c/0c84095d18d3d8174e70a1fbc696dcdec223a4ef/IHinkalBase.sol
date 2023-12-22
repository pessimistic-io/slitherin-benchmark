// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IRelayStore.sol";

interface IHinkalBase {
    event Register(address ethereumAddress, bytes shieldedAddressHash);

    event NewCommitment(uint256 commitment, uint256 index, bytes encryptedOutput);
    event Nullified(uint256 nullifier);
    event NewTransaction(uint256 timestamp, address erc20TokenAddress, int256 publicAmount);


    struct SwapData {
        uint256 rootHashHinkal;
        uint256 inSwapAmount;
        uint256 outSwapAmount;
        address inErc20TokenAddress;
        address outErc20TokenAddress;
        uint24 fee;
        address relay;
        uint256 relayFee;
        uint256[2] outCommitments;
        uint256 rootHashAccessToken;
    }

    function isNullifierSpent(uint256 nullifierHash) external view returns (bool);

    function relayPercentage() external view returns (uint8);

    function relayPercentageSwap() external view returns (uint8);

    function getRelayList() external view returns (RelayEntry[] memory);

    function register(bytes calldata shieldedAddressHash) external;
}

