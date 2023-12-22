// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {UserConfiguration} from "./UserConfiguration.sol";
import {ReserveConfiguration} from "./ReserveConfiguration.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {ILendingPoolAddressesProvider} from "./ILendingPoolAddressesProvider.sol";
import {DataTypes} from "./DataTypes.sol";
import {IAssetMappings} from "./IAssetMappings.sol";

contract LendingPoolStorage {
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    ILendingPoolAddressesProvider internal _addressesProvider;
    IAssetMappings internal _assetMappings;

    // user address -> trancheId -> user configuration
    mapping(address => mapping(uint64 => DataTypes.UserData)) internal _usersConfig;

    // asset address -> trancheId number -> reserve data
    mapping(address => mapping(uint64 => DataTypes.ReserveData)) internal _reserves;

    // the list of the available reserves, structured as a mapping for gas savings reasons
    // trancheId -> to array of available reserves
    mapping(uint64 => mapping(uint256 => address)) internal _reservesList;

    // trancheId -> tranche params
    mapping(uint64 => DataTypes.TrancheParams) public trancheParams;

    //true if all tranches in the protocol is paused
    bool internal _everythingPaused;
}

