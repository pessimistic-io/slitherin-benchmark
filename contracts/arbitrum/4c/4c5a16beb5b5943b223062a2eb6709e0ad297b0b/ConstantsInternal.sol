// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Decimal } from "./LibDecimal.sol";
import { ConstantsStorage } from "./ConstantsStorage.sol";
import { IConstantsEvents } from "./IConstantsEvents.sol";

library ConstantsInternal {
    using ConstantsStorage for ConstantsStorage.Layout;
    using Decimal for Decimal.D256;

    uint256 private constant PERCENT_BASE = 1e18;
    uint256 private constant PRECISION = 1e18;

    /* ========== VIEWS ========== */

    function getPrecision() internal pure returns (uint256) {
        return PRECISION;
    }

    function getPercentBase() internal pure returns (uint256) {
        return PERCENT_BASE;
    }

    function getCollateral() internal view returns (address) {
        return ConstantsStorage.layout().collateral;
    }

    function getLiquidationFee() internal view returns (Decimal.D256 memory) {
        return Decimal.ratio(ConstantsStorage.layout().liquidationFee, PERCENT_BASE);
    }

    function getProtocolLiquidationShare() internal view returns (Decimal.D256 memory) {
        return Decimal.ratio(ConstantsStorage.layout().protocolLiquidationShare, PERCENT_BASE);
    }

    function getCVA() internal view returns (Decimal.D256 memory) {
        return Decimal.ratio(ConstantsStorage.layout().cva, PERCENT_BASE);
    }

    function getRequestTimeout() internal view returns (uint256) {
        return ConstantsStorage.layout().requestTimeout;
    }

    function getMaxOpenPositionsCross() internal view returns (uint256) {
        return ConstantsStorage.layout().maxOpenPositionsCross;
    }

    /* ========== SETTERS ========== */

    function setCollateral(address collateral) internal {
        ConstantsStorage.layout().collateral = collateral;
    }

    function setLiquidationFee(uint256 liquidationFee) internal {
        ConstantsStorage.layout().liquidationFee = liquidationFee;
    }

    function setProtocolLiquidationShare(uint256 protocolLiquidationShare) internal {
        ConstantsStorage.layout().protocolLiquidationShare = protocolLiquidationShare;
    }

    function setCVA(uint256 cva) internal {
        ConstantsStorage.layout().cva = cva;
    }

    function setRequestTimeout(uint256 requestTimeout) internal {
        ConstantsStorage.layout().requestTimeout = requestTimeout;
    }

    function setMaxOpenPositionsCross(uint256 maxOpenPositionsCross) internal {
        ConstantsStorage.layout().maxOpenPositionsCross = maxOpenPositionsCross;
    }
}

