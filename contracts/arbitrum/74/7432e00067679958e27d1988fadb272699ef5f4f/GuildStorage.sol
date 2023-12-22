// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import {DataTypes} from "./DataTypes.sol";
import {IERC20} from "./contracts_IERC20.sol";
import {IAssetToken} from "./IAssetToken.sol";
import {ILiabilityToken} from "./ILiabilityToken.sol";

/**
 * @title GuildStorage
 * @author Tazz Labs
 * @notice Contract used as storage of the Guild contract.
 * @dev It defines the storage layout of the Guild contract.
 */
contract GuildStorage {
    // Perpetual debt data, including refinance information
    DataTypes.PerpetualDebtData internal _perpetualDebt;

    // Map of collaterals and their data (underlyingAddressOfCollateral => collateralData)
    mapping(address => DataTypes.CollateralData) internal _collaterals;

    // List of collaterals as a map (collateralId => collateral).
    // It is structured as a mapping for gas savings reasons, using the collateral id as index
    mapping(uint256 => address) internal _collateralsList;

    // Maximum number of active collateral types.
    uint16 internal _collateralsCount;

    // Whether the guild is locked
    bool unlocked;
}

