// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Errors} from "./Errors.sol";
import {DataTypes} from "./DataTypes.sol";

//bit 0-15: LTV
//bit 16-31: Liq. threshold
//bit 32-47: Liq. bonus
//bit 48-55: Decimals
//bit 56: collateral is active
//bit 57-115: reserved
//bit 116-151: supply cap in whole tokens, supplyCap == 0 => no cap
//bit 152-167: liquidation protocol fee
//bit 168-255: reserved

/**
 * @title CollateralConfiguration library
 * @author Amorphous, inspired by AAVE v3
 * @notice Handles the collateral configuration (not storage optimized)
 */
library CollateralConfiguration {
    uint256 internal constant LTV_MASK =                       0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000; // prettier-ignore
    uint256 internal constant LIQUIDATION_THRESHOLD_MASK =     0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF; // prettier-ignore
    uint256 internal constant LIQUIDATION_BONUS_MASK =         0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFF; // prettier-ignore
    uint256 internal constant DECIMALS_MASK =                  0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF; // prettier-ignore
    uint256 internal constant ACTIVE_MASK =                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF; // prettier-ignore
    uint256 internal constant FROZEN_MASK =                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF; // prettier-ignore
    uint256 internal constant PAUSED_MASK =                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 internal constant USER_SUPPLY_CAP_MASK =           0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 internal constant SUPPLY_CAP_MASK =                0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 internal constant LIQUIDATION_PROTOCOL_FEE_MASK =  0xFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore

    /// @dev For the LTV, the start bit is 0 (up to 15), hence no bitshifting is needed
    uint256 internal constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
    uint256 internal constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;
    uint256 internal constant COLLATERAL_DECIMALS_START_BIT_POSITION = 48;
    uint256 internal constant IS_ACTIVE_START_BIT_POSITION = 56;
    uint256 internal constant IS_FROZEN_START_BIT_POSITION = 57;
    uint256 internal constant IS_PAUSED_START_BIT_POSITION = 60;

    uint256 internal constant USER_SUPPLY_CAP_START_BIT_POSITION = 80;
    uint256 internal constant SUPPLY_CAP_START_BIT_POSITION = 116;
    uint256 internal constant LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION = 152;

    uint256 internal constant MAX_VALID_LTV = 65535;
    uint256 internal constant MAX_VALID_LIQUIDATION_THRESHOLD = 65535;
    uint256 internal constant MAX_VALID_LIQUIDATION_BONUS = 65535;
    uint256 internal constant MAX_VALID_DECIMALS = 255;
    uint256 internal constant MAX_VALID_USER_SUPPLY_CAP = 68719476735;
    uint256 internal constant MAX_VALID_SUPPLY_CAP = 68719476735;
    uint256 internal constant MAX_VALID_LIQUIDATION_PROTOCOL_FEE = 65535;

    uint16 public constant MAX_COLLATERALS_COUNT = 128;

    /**
     * @notice Sets the Loan to Value of the collateral
     * @param self The collateral configuration
     * @param ltv The new ltv
     **/
    function setLtv(DataTypes.CollateralConfigurationMap memory self, uint256 ltv) internal pure {
        require(ltv <= MAX_VALID_LTV, Errors.INVALID_LTV);

        self.data = (self.data & LTV_MASK) | ltv;
    }

    /**
     * @notice Gets the Loan to Value of the collateral
     * @param self The collateral configuration
     * @return The loan to value
     **/
    function getLtv(DataTypes.CollateralConfigurationMap memory self) internal pure returns (uint256) {
        return self.data & ~LTV_MASK;
    }

    /**
     * @notice Sets the liquidation threshold of the collateral
     * @param self The collateral configuration
     * @param threshold The new liquidation threshold
     **/
    function setLiquidationThreshold(DataTypes.CollateralConfigurationMap memory self, uint256 threshold)
        internal
        pure
    {
        require(threshold <= MAX_VALID_LIQUIDATION_THRESHOLD, Errors.INVALID_LIQ_THRESHOLD);

        self.data = (self.data & LIQUIDATION_THRESHOLD_MASK) | (threshold << LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    /**
     * @notice Gets the liquidation threshold of the collateral
     * @param self The collateral configuration
     * @return The liquidation threshold
     **/
    function getLiquidationThreshold(DataTypes.CollateralConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }

    /**
     * @notice Sets the liquidation bonus of the collateral
     * @param self The collateral configuration
     * @param bonus The new liquidation bonus
     **/
    function setLiquidationBonus(DataTypes.CollateralConfigurationMap memory self, uint256 bonus) internal pure {
        require(bonus <= MAX_VALID_LIQUIDATION_BONUS, Errors.INVALID_LIQ_BONUS);

        self.data = (self.data & LIQUIDATION_BONUS_MASK) | (bonus << LIQUIDATION_BONUS_START_BIT_POSITION);
    }

    /**
     * @notice Gets the liquidation bonus of the collateral
     * @param self The collateral configuration
     * @return The liquidation bonus
     **/
    function getLiquidationBonus(DataTypes.CollateralConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION;
    }

    /**
     * @notice Sets the decimals of the underlying asset of the collateral
     * @param self The collateral configuration
     * @param decimals The decimals
     **/
    function setDecimals(DataTypes.CollateralConfigurationMap memory self, uint256 decimals) internal pure {
        require(decimals <= MAX_VALID_DECIMALS, Errors.INVALID_DECIMALS);

        self.data = (self.data & DECIMALS_MASK) | (decimals << COLLATERAL_DECIMALS_START_BIT_POSITION);
    }

    /**
     * @notice Gets the decimals of the underlying asset of the collateral
     * @param self The collateral configuration
     * @return The decimals of the asset
     **/
    function getDecimals(DataTypes.CollateralConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~DECIMALS_MASK) >> COLLATERAL_DECIMALS_START_BIT_POSITION;
    }

    /**
     * @notice Sets the active state of the collateral
     * @param self The collateral configuration
     * @param active The active state
     **/
    function setActive(DataTypes.CollateralConfigurationMap memory self, bool active) internal pure {
        self.data = (self.data & ACTIVE_MASK) | (uint256(active ? 1 : 0) << IS_ACTIVE_START_BIT_POSITION);
    }

    /**
     * @notice Gets the active state of the collateral
     * @param self The collateral configuration
     * @return The active state
     **/
    function getActive(DataTypes.CollateralConfigurationMap memory self) internal pure returns (bool) {
        return (self.data & ~ACTIVE_MASK) != 0;
    }

    /**
     * @notice Sets the frozen state of the reserve
     * @param self The reserve configuration
     * @param frozen The frozen state
     **/
    function setFrozen(DataTypes.CollateralConfigurationMap memory self, bool frozen) internal pure {
        self.data = (self.data & FROZEN_MASK) | (uint256(frozen ? 1 : 0) << IS_FROZEN_START_BIT_POSITION);
    }

    /**
     * @notice Gets the frozen state of the reserve
     * @param self The reserve configuration
     * @return The frozen state
     **/
    function getFrozen(DataTypes.CollateralConfigurationMap memory self) internal pure returns (bool) {
        return (self.data & ~FROZEN_MASK) != 0;
    }

    /**
     * @notice Sets the paused state of the reserve
     * @param self The reserve configuration
     * @param paused The paused state
     **/
    function setPaused(DataTypes.CollateralConfigurationMap memory self, bool paused) internal pure {
        self.data = (self.data & PAUSED_MASK) | (uint256(paused ? 1 : 0) << IS_PAUSED_START_BIT_POSITION);
    }

    /**
     * @notice Gets the paused state of the reserve
     * @param self The reserve configuration
     * @return The paused state
     **/
    function getPaused(DataTypes.CollateralConfigurationMap memory self) internal pure returns (bool) {
        return (self.data & ~PAUSED_MASK) != 0;
    }

    /**
     * @notice Sets the supply cap of the collateral
     * @param self The collateral configuration
     * @param supplyCap The supply cap
     * @dev supplyCap at guild level encoded with 0 decimal places (e.g, 1 -> 1 token in collateral's own unit)
     **/
    function setSupplyCap(DataTypes.CollateralConfigurationMap memory self, uint256 supplyCap) internal pure {
        require(supplyCap <= MAX_VALID_SUPPLY_CAP, Errors.INVALID_SUPPLY_CAP);

        self.data = (self.data & SUPPLY_CAP_MASK) | (supplyCap << SUPPLY_CAP_START_BIT_POSITION);
    }

    /**
     * @notice Gets the supply cap of the collateral
     * @param self The collateral configuration
     * @return The supply cap
     * @dev supplyCap at guild level encoded with 0 decimal places (e.g, 1 -> 1 token in collateral's own unit)
     **/
    function getSupplyCap(DataTypes.CollateralConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION;
    }

    /**
     * @notice Sets the user supply cap of the collateral (wallet level)
     * @param self The collateral configuration
     * @param supplyCap The supply cap
     * @dev supplyCap at user level encoded with 2 decimal places (e.g, 100 -> 1 token in collateral's own unit)
     **/
    function setUserSupplyCap(DataTypes.CollateralConfigurationMap memory self, uint256 supplyCap) internal pure {
        require(supplyCap <= MAX_VALID_USER_SUPPLY_CAP, Errors.INVALID_SUPPLY_CAP);

        self.data = (self.data & USER_SUPPLY_CAP_MASK) | (supplyCap << USER_SUPPLY_CAP_START_BIT_POSITION);
    }

    /**
     * @notice Gets the user supply cap of the collateral (wallet level)
     * @param self The collateral configuration
     * @return The supply cap
     * @dev supplyCap at user level encoded with 2 decimal places (e.g, 100 -> 1 token in collateral's own unit)
     **/
    function getUserSupplyCap(DataTypes.CollateralConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~USER_SUPPLY_CAP_MASK) >> USER_SUPPLY_CAP_START_BIT_POSITION;
    }

    /**
     * @notice Sets the liquidation protocol fee of the collateral
     * @param self The collateral configuration
     * @param liquidationProtocolFee The liquidation protocol fee
     **/
    function setLiquidationProtocolFee(DataTypes.CollateralConfigurationMap memory self, uint256 liquidationProtocolFee)
        internal
        pure
    {
        require(liquidationProtocolFee <= MAX_VALID_LIQUIDATION_PROTOCOL_FEE, Errors.INVALID_LIQUIDATION_PROTOCOL_FEE);

        self.data =
            (self.data & LIQUIDATION_PROTOCOL_FEE_MASK) |
            (liquidationProtocolFee << LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION);
    }

    /**
     * @dev Gets the liquidation protocol fee
     * @param self The collateral configuration
     * @return The liquidation protocol fee
     **/
    function getLiquidationProtocolFee(DataTypes.CollateralConfigurationMap memory self)
        internal
        pure
        returns (uint256)
    {
        return (self.data & ~LIQUIDATION_PROTOCOL_FEE_MASK) >> LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION;
    }

    /**
     * @notice Gets the configuration flags of the collateral
     * @param self The collateral configuration
     * @return The state flag representing active
     * @return The state flag representing frozen
     * @return The state flag representing paused
     **/
    function getFlags(DataTypes.CollateralConfigurationMap memory self)
        internal
        pure
        returns (
            bool,
            bool,
            bool
        )
    {
        uint256 dataLocal = self.data;

        return ((dataLocal & ~ACTIVE_MASK) != 0, (dataLocal & ~FROZEN_MASK) != 0, (dataLocal & ~PAUSED_MASK) != 0);
    }

    /**
     * @notice Gets the configuration parameters of the collateral from storage
     * @param self The collateral configuration
     * @return The state param representing ltv
     * @return The state param representing liquidation threshold
     * @return The state param representing liquidation bonus
     * @return The state param representing collateral decimals
     **/
    function getParams(DataTypes.CollateralConfigurationMap memory self)
        internal
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 dataLocal = self.data;

        return (
            dataLocal & ~LTV_MASK,
            (dataLocal & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION,
            (dataLocal & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION,
            (dataLocal & ~DECIMALS_MASK) >> COLLATERAL_DECIMALS_START_BIT_POSITION
        );
    }

    /**
     * @notice Gets the caps parameters of the collateral from storage
     * @param self The collateral configuration
     * @return The state param representing supply cap.
     * @return The state param representing user supply cap.
     **/
    function getCaps(DataTypes.CollateralConfigurationMap memory self) internal pure returns (uint256, uint256) {
        uint256 dataLocal = self.data;

        return (
            (dataLocal & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION,
            (dataLocal & ~USER_SUPPLY_CAP_MASK) >> USER_SUPPLY_CAP_START_BIT_POSITION
        );
    }
}

