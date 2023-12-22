// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IRequestController.sol";
import "./RequestControllerModifiers.sol";
import "./RequestControllerEvents.sol";
import "./CommonConsts.sol";

abstract contract RequestControllerAdmin is
    IRequestController,
    RequestControllerModifiers,
    RequestControllerEvents,
    CommonConsts
{
    function deprecateMarket(
        address loanMarketAsset,
        bool deprecatedStatus
    ) external override onlyAdmin() {
        emit MarketDeprecationChanged(loanMarketAsset, isdeprecated[loanMarketAsset], deprecatedStatus);

        isdeprecated[loanMarketAsset] = deprecatedStatus;
    }

    function freezeLoanMarket(
        address loanMarketAsset,
        bool freezeStatus
    ) external override onlyAdmin() {
        emit LoanMarketFrozen(loanMarketAsset, isLoanMarketFrozen[loanMarketAsset], freezeStatus);

        isLoanMarketFrozen[loanMarketAsset] = freezeStatus;
    }

    function freezePToken(
        address pToken,
        bool freezeStatus
    ) external override onlyAdmin() {
        emit PTokenFrozen(pToken, isPTokenFrozen[pToken], freezeStatus);

        isPTokenFrozen[pToken] = freezeStatus;
    }

    function setMidLayer(
        address newMiddleLayer
    ) external override onlyAdmin() isContractIdentifier(newMiddleLayer, MIDDLE_LAYER_IDENTIFIER) {
        emit SetMiddleLayer(address(middleLayer), newMiddleLayer);

        middleLayer = IMiddleLayer(newMiddleLayer);
    }
}

