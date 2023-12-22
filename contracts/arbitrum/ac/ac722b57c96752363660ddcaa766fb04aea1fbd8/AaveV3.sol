// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {IAToken} from "./IAToken.sol";
import {IPoolAddressesProviderRegistry} from "./IPoolAddressesProviderRegistry.sol";
import "./ILendingProvider.sol";

// Struct representing the storage of the AaveV3 adapter
struct AaveV3AdapterStorage {
    // The adapter's address
    ILendingProvider aaveV3Adapter;
    // The referral code to use which grants YC some fees cut from aave
    uint16 YIELDCHAIN_REFFERAL_CODE;
    // Map vault addresses => AToken => Principal balance
    mapping(address => mapping(IAToken => uint256)) principalDeposits;
    // Map client IDs to corresponding PoolAddressesProviderRegistry
    mapping(bytes32 => IPoolAddressesProviderRegistry) clients;
    bytes32[] clientsIds;
}

library AaveV3AdapterStorageLib {
    // Storage slot hash
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.adapters.lending.clients.aavev3");

    // Retreive the storage struct
    function retreive() internal pure returns (AaveV3AdapterStorage storage s) {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }
}

