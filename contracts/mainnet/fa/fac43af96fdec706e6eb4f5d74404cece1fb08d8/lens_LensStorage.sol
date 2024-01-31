// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./IPriceOracleGetter.sol";
import "./ILendingPool.sol";
import "./IAToken.sol";
import "./interfaces_IMorpho.sol";

import "./aave_ReserveConfiguration.sol";
import "./PercentageMath.sol";
import "./WadRayMath.sol";
import "./math_Math.sol";
import "./aave_DataTypes.sol";
import "./libraries_InterestRatesModel.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage {
    /// STORAGE ///

    uint16 public constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 5_000; // 50% in basis points.
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // Health factor below which the positions can be liquidated.

    IMorpho public immutable morpho;
    ILendingPoolAddressesProvider public immutable addressesProvider;
    ILendingPool public immutable pool;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @param _morpho The address of the main Morpho contract.
    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
        pool = ILendingPool(morpho.pool());
        addressesProvider = ILendingPoolAddressesProvider(morpho.addressesProvider());
    }
}

