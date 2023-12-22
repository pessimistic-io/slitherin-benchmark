// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IPToken.sol";
import "./PTokenModifiers.sol";
import "./PTokenEvents.sol";
import "./CommonConsts.sol";

abstract contract PTokenAdmin is IPToken, PTokenModifiers, PTokenEvents, CommonConsts {
    function deprecateMarket(
        bool deprecatedStatus
    ) external override onlyAdmin() {
        emit MarketDeprecationChanged(isdeprecated, deprecatedStatus);

        isdeprecated = deprecatedStatus;
    }

    function freezeMarket(
        bool freezeStatus
    ) external override onlyAdmin() {
        emit MarketFreezeChanged(isFrozen, freezeStatus);

        isFrozen = freezeStatus;
    }

    function setMidLayer(
        address newMiddleLayer
    ) external override onlyAdmin() isContractIdentifier(newMiddleLayer, MIDDLE_LAYER_IDENTIFIER) {
        emit SetMiddleLayer(address(middleLayer), newMiddleLayer);

        middleLayer = IMiddleLayer(newMiddleLayer);
    }

    function changeRequestController(
        address newRequestController
    ) external onlyAdmin() {
        if (newRequestController == address(0)) revert AddressExpected();

        emit RequestControllerChanged(requestController, newRequestController);

        requestController = newRequestController;
    }
}

