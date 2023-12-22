/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

import "./IRateOracleModule.sol";
import "./IRateOracle.sol";
import "./RateOracleReader.sol";
import "./IERC165.sol";
import "./OwnableStorage.sol";
import { UD60x18 } from "./UD60x18.sol";

/**
 * @title Module for managing rate oracles connected to the Dated IRS Product
 * @dev See IRateOracleModule
 *  // todo: register a new rate oracle
 * // I'd call this RateOracleManagerModule to avoid confusion
 */
contract RateOracleManager is IRateOracleModule {
    using RateOracleReader for RateOracleReader.Data;

    /**
     * @inheritdoc IRateOracleModule
     */

    function getRateIndexCurrent(
        uint128 marketId,
        uint32 maturityTimestamp
    )
        external
        view
        override
        returns (UD60x18 rateIndexCurrent)
    {
        return RateOracleReader.load(marketId).getRateIndexCurrent(maturityTimestamp);
    }

    /**
     * @inheritdoc IRateOracleModule
     */
    function getRateIndexMaturity(
        uint128 marketId,
        uint32 maturityTimestamp
    )
        external
        view
        override
        returns (UD60x18 rateIndexMaturity)
    {
        return RateOracleReader.load(marketId).getRateIndexMaturity(maturityTimestamp);
    }

    /**
     * @inheritdoc IRateOracleModule
     */
    function setVariableOracle(uint128 marketId, address oracleAddress) external override {
        OwnableStorage.onlyOwner();

        validateAndConfigureOracleAddress(marketId, oracleAddress);
    }

    // todo: add getVariableOracle function

    /**
     * @dev Validates the address interface and creates or configures a rate oracle
     */
    function validateAndConfigureOracleAddress(uint128 marketId, address oracleAddress) internal {
        if (!_validateVariableOracleAddress(oracleAddress)) {
            revert InvalidVariableOracleAddress(oracleAddress);
        }

        // configure the variable rate oracle
        RateOracleReader.set(marketId, oracleAddress);

        emit RateOracleConfigured(marketId, oracleAddress, block.timestamp);
    }

    function _validateVariableOracleAddress(address oracleAddress) internal returns (bool isValid) {
        return IERC165(oracleAddress).supportsInterface(type(IRateOracle).interfaceId);
    }
}

