// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

interface IHinkal {
    event ExternalActionRegistered(uint256 externalActionId, address externalActionAddress);

    event ExternalActionRemoved(uint256 externalActionId);

    struct ConstructorArgs {
        address poseidon4Address;
        address merkleTreeAddress;
        address accessTokenAddress;
        address erc20TokenRegistryAddress;
        address relayStoreAddress;
        address verifierFacadeAddress;
    }
}

