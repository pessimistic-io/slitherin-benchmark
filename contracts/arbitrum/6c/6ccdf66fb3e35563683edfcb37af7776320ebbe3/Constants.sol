// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ConstantsInternal } from "./ConstantsInternal.sol";

contract Constants {
    function getPrecision() external pure returns (uint256) {
        return ConstantsInternal.getPrecision();
    }

    function getPercentBase() external pure returns (uint256) {
        return ConstantsInternal.getPercentBase();
    }

    function getCollateral() external view returns (address) {
        return ConstantsInternal.getCollateral();
    }

    function getLiquidationFee() external view returns (uint256) {
        return ConstantsInternal.getLiquidationFee().value;
    }

    function getProtocolLiquidationShare() external view returns (uint256) {
        return ConstantsInternal.getProtocolLiquidationShare().value;
    }

    function getCVA() external view returns (uint256) {
        return ConstantsInternal.getCVA().value;
    }

    function getRequestTimeout() external view returns (uint256) {
        return ConstantsInternal.getRequestTimeout();
    }

    function getMaxOpenPositionsCross() external view returns (uint256) {
        return ConstantsInternal.getMaxOpenPositionsCross();
    }
}

