//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdminableUpgradeable.sol";
import "./IMasterOfInflation.sol";
import "./IPoolConfigProvider.sol";

abstract contract MasterOfInflationState is Initializable, IMasterOfInflation, AdminableUpgradeable {

    event PoolCreated(uint64 poolId, address poolCollection);
    event PoolAdminChanged(uint64 poolId, address oldAdmin, address newAdmin);
    event PoolRateChanged(uint64 poolId, uint256 oldItemRate, uint256 newItemRate);
    event PoolAccessChanged(uint64 poolId, address accessor, bool canAccess);
    event PoolConfigProviderChanged(uint64 poolId, address oldProvider, address newProvider);
    event PoolSModifierChanged(uint64 poolId, uint256 oldModifier, uint256 newModifier);
    event PoolDisabled(uint64 poolId);
    event PoolItemMintableChanged(uint64 poolId, uint256 itemId, bool mintable);

    event ItemMintedFromPool(uint64 poolId, address user, uint256 itemId, uint64 amount);

    uint64 public poolId;

    mapping(uint64 => PoolInfo) public poolIdToInfo;
    mapping(uint64 => mapping(uint256 => bool)) public poolIdToItemIdToMintable;

    function __MasterOfInflationState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        poolId = 1;
    }
}

struct PoolInfo {
    // Slot 1 (168/256)
    // Indicates if this pool is enabled.
    bool isEnabled;
    // The owner of the pool. Typically EOA. Allowed to disable or change the rate.
    address poolAdmin;
    uint88 emptySpace1;

    // Slot 2
    // The time this pool was created.
    uint128 startTime;
    // The time the pool last changed.
    uint128 timeRateLastChanged;

    // Slot 3
    // The rate at which the pool is gaining items. The rate is in `ether` aka 10^18.
    uint256 itemRatePerSecond;

    // Slot 4
    // The number of items that are in the pool at the time of the last rate change. This is to preserve any accumulated items at the old rate.
    // Number is in `ether`.
    uint256 totalItemsAtLastRateChange;

    // Slot 5
    // The total number of items claimed from this pool. In `ether`.
    uint256 itemsClaimed;

    // Slot 6
    // Contains a mapping of address to whether the address can access/draw from this pool
    mapping(address => bool) addressToAccess;

    // Slot 7
    // A modifier that can be applied to the formula per pool.
    uint256 sModifier;

    // Slot 8 (160/256)
    // The 1155 collection that this pool gives items for.
    address poolCollection;
    uint96 emptySpace2;

    // Slot 9 (160/256)
    // The provider of the config. When dealing with dynamic rates, the N in the formula is defined
    // by the config provider.
    address poolConfigProvider;
    uint96 emptySpace3;
}
