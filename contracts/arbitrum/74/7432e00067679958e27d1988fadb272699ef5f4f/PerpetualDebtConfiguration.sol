// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Errors} from "./Errors.sol";
import {DataTypes} from "./DataTypes.sol";

//bit 0: perpetual debt is paused (no mint, no burn/distribute, no liquidate, no refinance)
//bit 1: perpetual debt is frozen (no mint, yes burn/distribute, yes liquidate, yes refinance)
//bit 2-37: mint cap in whole tokens, mintCap ==0 => no cap
//bit 38-255: unused

/**
 * @title Perpetual Debt Configuration library
 * @author Tazz Labs, inspired by AAVE v3
 * @notice Handles the perpetual debt configuration (not storage optimized)
 */
library PerpetualDebtConfiguration {
    uint256 internal constant PAUSED_MASK =   0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE; // prettier-ignore
    uint256 internal constant FROZEN_MASK =   0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFD; // prettier-ignore
    uint256 internal constant MINT_CAP_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE000000003; // prettier-ignore

    /// @dev For the PAUSED flag, the start bit is 0, hence no bitshifting is needed
    uint256 internal constant IS_FROZEN_MASK_START_BIT_POSITION = 1;
    uint256 internal constant MINT_CAP_START_BIT_POSITION = 2;

    uint256 internal constant MAX_VALID_MINT_CAP = 68719476735;

    /**
     * @notice Sets the paused state of the perpetual debt
     * @param self The perpetual debt configuration
     * @param paused The paused state
     **/
    function setPaused(DataTypes.PerpDebtConfigurationMap memory self, bool paused) internal pure {
        self.data = (self.data & PAUSED_MASK) | (uint256(paused ? 1 : 0));
    }

    /**
     * @notice Gets the paused state of the perpetual debt
     * @param self The perpetual debt configuration
     * @return The paused state
     **/
    function getPaused(DataTypes.PerpDebtConfigurationMap memory self) internal pure returns (bool) {
        return (self.data & ~PAUSED_MASK) != 0;
    }

    /**
     * @notice Sets the active state of the perpetual debt
     * @param self The perpetual debt configuration
     * @param frozen The active state
     **/
    function setFrozen(DataTypes.PerpDebtConfigurationMap memory self, bool frozen) internal pure {
        self.data = (self.data & FROZEN_MASK) | (uint256(frozen ? 1 : 0) << IS_FROZEN_MASK_START_BIT_POSITION);
    }

    /**
     * @notice Gets the fozen state of the perpetual debt
     * @param self The perpetual debt configuration
     * @return The frozen state
     **/
    function getFrozen(DataTypes.PerpDebtConfigurationMap memory self) internal pure returns (bool) {
        return (self.data & ~FROZEN_MASK) != 0;
    }

    /**
     * @notice Sets the supply cap of the perpetual debt
     * @param self The perpetual debt configuration
     * @param mintCap The mint cap
     **/
    function setMintCap(DataTypes.PerpDebtConfigurationMap memory self, uint256 mintCap) internal pure {
        require(mintCap <= MAX_VALID_MINT_CAP, Errors.INVALID_MINT_CAP);

        self.data = (self.data & MINT_CAP_MASK) | (mintCap << MINT_CAP_START_BIT_POSITION);
    }

    /**
     * @notice Gets the mint cap of the perpetual debt
     * @param self The perpetual debt configuration
     * @return The mint cap
     **/
    function getMintCap(DataTypes.PerpDebtConfigurationMap memory self) internal pure returns (uint256) {
        return (self.data & ~MINT_CAP_MASK) >> MINT_CAP_START_BIT_POSITION;
    }

    /**
     * @notice Gets the configuration flags of the perpetual debt
     * @param self The perpetual debt configuration
     * @return The state flag representing frozen
     * @return The state flag representing paused
     **/
    function getFlags(DataTypes.PerpDebtConfigurationMap memory self) internal pure returns (bool, bool) {
        uint256 dataLocal = self.data;

        return ((dataLocal & ~FROZEN_MASK) != 0, (dataLocal & ~PAUSED_MASK) != 0);
    }

    /**
     * @notice Gets the caps parameters of the perpetual debt from storage
     * @param self The perpetual debt configuration
     * @return The state param representing mint cap.
     **/
    function getCaps(DataTypes.PerpDebtConfigurationMap memory self) internal pure returns (uint256) {
        uint256 dataLocal = self.data;

        return ((dataLocal & ~MINT_CAP_MASK) >> MINT_CAP_START_BIT_POSITION);
    }
}

