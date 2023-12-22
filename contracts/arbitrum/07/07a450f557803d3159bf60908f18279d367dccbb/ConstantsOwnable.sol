// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { AccessControlInternal } from "./AccessControlInternal.sol";
import { ConstantsInternal } from "./ConstantsInternal.sol";
import { IConstantsEvents } from "./IConstantsEvents.sol";

contract ConstantsOwnable is AccessControlInternal, IConstantsEvents {
    function setCollateral(address collateral) external onlyRole(ADMIN_ROLE) {
        emit SetCollateral(ConstantsInternal.getCollateral(), collateral);
        ConstantsInternal.setCollateral(collateral);
    }

    function setLiquidationFee(uint256 liquidationFee) external onlyRole(ADMIN_ROLE) {
        emit SetLiquidationFee(ConstantsInternal.getLiquidationFee().value, liquidationFee);
        ConstantsInternal.setLiquidationFee(liquidationFee);
    }

    function setProtocolLiquidationShare(uint256 protocolLiquidationShare) external onlyRole(ADMIN_ROLE) {
        emit SetProtocolLiquidationShare(
            ConstantsInternal.getProtocolLiquidationShare().value,
            protocolLiquidationShare
        );
        ConstantsInternal.setProtocolLiquidationShare(protocolLiquidationShare);
    }

    function setCVA(uint256 cva) external onlyRole(ADMIN_ROLE) {
        emit SetCVA(ConstantsInternal.getCVA().value, cva);
        ConstantsInternal.setCVA(cva);
    }

    function setRequestTimeout(uint256 requestTimeout) external onlyRole(ADMIN_ROLE) {
        emit SetRequestTimeout(ConstantsInternal.getRequestTimeout(), requestTimeout);
        ConstantsInternal.setRequestTimeout(requestTimeout);
    }

    function setMaxOpenPositionsCross(uint256 maxOpenPositionsCross) external onlyRole(ADMIN_ROLE) {
        emit SetMaxOpenPositionsCross(ConstantsInternal.getMaxOpenPositionsCross(), maxOpenPositionsCross);
        ConstantsInternal.setMaxOpenPositionsCross(maxOpenPositionsCross);
    }
}

