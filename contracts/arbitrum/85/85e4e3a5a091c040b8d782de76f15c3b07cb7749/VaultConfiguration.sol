// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from "./DataTypes.sol";
import "./console.sol";

/**
 * @title Vault confniguration library
 * @author Strateg
 * @notice Implements the bitmap logic to handle the vault configuration
 */
library VaultConfiguration {
    error INVALID_MIDDLEWARE_STRATEGY();
    error INVALID_LIMIT_MODE();
    error INVALID_TIMELOCK_DURATION();
    error INVALID_CREATOR_FEE();
    error INVALID_HARVEST_FEE();
    error INVALID_BUFFER_SIZE();
    error INVALID_BUFFER_DERIVATION();
    error INVALID_STRATEGY_BLOCKS_LENGTH();
    error INVALID_HARVEST_BLOCKS_LENGTH();
    error INVALID_LAST_HARVEST_INDEX();

    uint256 internal constant MIN_CREATOR_FEE = 100;
    uint256 internal constant MIN_HARVEST_FEE = 50;
    uint256 internal constant MAX_CREATOR_FEE = 2500;
    uint256 internal constant MAX_HARVEST_FEE = 500;

    uint256 internal constant MIDDLEWARE_STRATEGY_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00;
    uint256 internal constant LIMIT_MODE_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FF;
    uint256 internal constant TIMELOCK_DURATION_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFF;
    uint256 internal constant CREATOR_FEE_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFF;
    uint256 internal constant HARVEST_FEE_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFF;
    uint256 internal constant BUFFER_SIZE_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant BUFFER_DERIVATION_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant STRATEGY_BLOCKS_LENGTH_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant HARVEST_BLOCKS_LENGTH_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant LAST_HARVEST_INDEX_MASK =
        0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant TIMELOCK_ENABLED_MASK = 0xFFFFFFFFFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /// @dev For the MIDDLEWARE_STRATEGY, the start bit is 0 (up to 7), hence no bitshifting is needed
    uint256 internal constant MIDDLEWARE_STRATEGY_START_BIT_POSITION = 0;
    uint256 internal constant LIMIT_MODE_START_BIT_POSITION = 8;
    uint256 internal constant TIMELOCK_DURATION_START_BIT_POSITION = 16;
    uint256 internal constant CREATOR_FEE_START_BIT_POSITION = 48;
    uint256 internal constant HARVEST_FEE_START_BIT_POSITION = 64;
    uint256 internal constant BUFFER_SIZE_START_BIT_POSITION = 80;
    uint256 internal constant BUFFER_DERIVATION_START_BIT_POSITION = 96;
    uint256 internal constant STRATEGY_BLOCKS_LENGTH_START_BIT_POSITION = 112;
    uint256 internal constant HARVEST_BLOCKS_LENGTH_START_BIT_POSITION = 120;
    uint256 internal constant LAST_HARVEST_INDEX_START_BIT_POSITION = 128;
    uint256 internal constant TIMELOCK_ENABLED_START_BIT_POSITION = 192;

    uint256 internal constant MAX_VALID_MIDDLEWARE_STRATEGY = 255;
    uint256 internal constant MAX_VALID_LIMIT_MODE = 255;
    uint256 internal constant MAX_VALID_TIMELOCK_DURATION = 4294967295;
    uint256 internal constant MAX_VALID_CREATOR_FEE = 65535;
    uint256 internal constant MAX_VALID_HARVEST_FEE = 65535;
    uint256 internal constant MAX_VALID_BUFFER_SIZE = 65535;
    uint256 internal constant MAX_VALID_BUFFER_DERIVATION = 65535;
    uint256 internal constant MAX_VALID_STRATEGY_BLOCKS_LENGTH = 255;
    uint256 internal constant MAX_VALID_HARVEST_BLOCKS_LENGTH = 255;
    uint256 internal constant MAX_VALID_LAST_HARVEST_INDEX = 18446744073709551615;

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param middlewareStrategy The new ltv
     */
    function setMiddlewareStrategy(DataTypes.VaultConfigurationMap memory self, uint256 middlewareStrategy)
        internal
        pure
    {
        if (middlewareStrategy > MAX_VALID_MIDDLEWARE_STRATEGY) {
            revert INVALID_MIDDLEWARE_STRATEGY();
        }
        self.data = (self.data & MIDDLEWARE_STRATEGY_MASK) | middlewareStrategy;
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getMiddlewareStrategy(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return self.data & ~MIDDLEWARE_STRATEGY_MASK;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param limitMode The new ltv
     */
    function setLimitMode(DataTypes.VaultConfigurationMap memory self, uint256 limitMode) internal pure {
        if (limitMode > MAX_VALID_LIMIT_MODE) revert INVALID_LIMIT_MODE();

        self.data = (self.data & LIMIT_MODE_MASK) | (limitMode << LIMIT_MODE_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getLimitMode(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~LIMIT_MODE_MASK) >> LIMIT_MODE_START_BIT_POSITION;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param timelockDuration The new ltv
     */
    function setTimelockDuration(DataTypes.VaultConfigurationMap memory self, uint256 timelockDuration) internal pure {
        if (timelockDuration > MAX_VALID_TIMELOCK_DURATION) {
            revert INVALID_TIMELOCK_DURATION();
        }

        self.data = (self.data & TIMELOCK_DURATION_MASK) | (timelockDuration << TIMELOCK_DURATION_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getTimelockDuration(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~TIMELOCK_DURATION_MASK) >> TIMELOCK_DURATION_START_BIT_POSITION;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param creatorFee The new ltv
     */
    function setCreatorFee(DataTypes.VaultConfigurationMap memory self, uint256 creatorFee) internal pure {
        if (creatorFee > MAX_VALID_CREATOR_FEE || creatorFee < MIN_CREATOR_FEE || creatorFee > MAX_CREATOR_FEE) {
            revert INVALID_CREATOR_FEE();
        }

        self.data = (self.data & CREATOR_FEE_MASK) | (creatorFee << CREATOR_FEE_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getCreatorFee(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~CREATOR_FEE_MASK) >> CREATOR_FEE_START_BIT_POSITION;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param harvestFee The new ltv
     */
    function setHarvestFee(DataTypes.VaultConfigurationMap memory self, uint256 harvestFee) internal pure {
        if (harvestFee > MAX_VALID_HARVEST_FEE || harvestFee < MIN_HARVEST_FEE || harvestFee > MAX_HARVEST_FEE) {
            revert INVALID_HARVEST_FEE();
        }

        self.data = (self.data & HARVEST_FEE_MASK) | (harvestFee << HARVEST_FEE_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getHarvestFee(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~HARVEST_FEE_MASK) >> HARVEST_FEE_START_BIT_POSITION;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param bufferSize The new ltv
     */
    function setBufferSize(DataTypes.VaultConfigurationMap memory self, uint256 bufferSize) internal pure {
        if (bufferSize > MAX_VALID_BUFFER_SIZE) revert INVALID_BUFFER_SIZE();

        self.data = (self.data & BUFFER_SIZE_MASK) | (bufferSize << BUFFER_SIZE_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getBufferSize(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~BUFFER_SIZE_MASK) >> BUFFER_SIZE_START_BIT_POSITION;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param bufferDerivation The new ltv
     */
    function setBufferDerivation(DataTypes.VaultConfigurationMap memory self, uint256 bufferDerivation) internal pure {
        if (bufferDerivation > MAX_VALID_BUFFER_DERIVATION) {
            revert INVALID_BUFFER_DERIVATION();
        }

        self.data = (self.data & BUFFER_DERIVATION_MASK) | (bufferDerivation << BUFFER_DERIVATION_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getBufferDerivation(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~BUFFER_DERIVATION_MASK) >> BUFFER_DERIVATION_START_BIT_POSITION;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param strategyBlockLength The new ltv
     */
    function setStrategyBlocksLength(DataTypes.VaultConfigurationMap memory self, uint256 strategyBlockLength)
        internal
        pure
    {
        if (strategyBlockLength > MAX_VALID_STRATEGY_BLOCKS_LENGTH) {
            revert INVALID_STRATEGY_BLOCKS_LENGTH();
        }

        self.data = (self.data & STRATEGY_BLOCKS_LENGTH_MASK)
            | (strategyBlockLength << STRATEGY_BLOCKS_LENGTH_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getStrategyBlocksLength(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~STRATEGY_BLOCKS_LENGTH_MASK) >> STRATEGY_BLOCKS_LENGTH_START_BIT_POSITION;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param harvestBlockLength The new ltv
     */
    function setHarvestBlocksLength(DataTypes.VaultConfigurationMap memory self, uint256 harvestBlockLength)
        internal
        pure
    {
        if (harvestBlockLength > MAX_VALID_HARVEST_BLOCKS_LENGTH) {
            revert INVALID_HARVEST_BLOCKS_LENGTH();
        }

        self.data =
            (self.data & HARVEST_BLOCKS_LENGTH_MASK) | (harvestBlockLength << HARVEST_BLOCKS_LENGTH_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getHarvestBlocksLength(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~HARVEST_BLOCKS_LENGTH_MASK) >> HARVEST_BLOCKS_LENGTH_START_BIT_POSITION;
    }

    /**
     * @notice Sets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @param lastHarvestIndex The new ltv
     */
    function setLastHarvestIndex(DataTypes.VaultConfigurationMap memory self, uint256 lastHarvestIndex) internal pure {
        if (lastHarvestIndex > MAX_VALID_LAST_HARVEST_INDEX) {
            revert INVALID_LAST_HARVEST_INDEX();
        }

        self.data = (self.data & LAST_HARVEST_INDEX_MASK) | (lastHarvestIndex << LAST_HARVEST_INDEX_START_BIT_POSITION);
    }

    /**
     * @notice Gets the Loan to Value of the reserve
     * @param self The reserve configuration
     * @return The loan to value
     */
    function getLastHarvestIndex(DataTypes.VaultConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~LAST_HARVEST_INDEX_MASK) >> LAST_HARVEST_INDEX_START_BIT_POSITION;
    }

    /**
     * @notice Sets the frozen state of the reserve
     * @param self The reserve configuration
     * @param timelockEnabled The frozen state
     */
    function setTimelockEnabled(DataTypes.VaultConfigurationMap memory self, bool timelockEnabled) internal pure {
        self.data = (self.data & TIMELOCK_ENABLED_MASK)
            | (uint256(timelockEnabled ? 1 : 0) << TIMELOCK_ENABLED_START_BIT_POSITION);
    }

    /**
     * @notice Gets the frozen state of the reserve
     * @param self The reserve configuration
     * @return The frozen state
     */
    function getTimelockEnabled(DataTypes.VaultConfigurationMap memory self) internal pure returns (bool) {
        return (self.data & ~TIMELOCK_ENABLED_MASK) != 0;
    }
}

