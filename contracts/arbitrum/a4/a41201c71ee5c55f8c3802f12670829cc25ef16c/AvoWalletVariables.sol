// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";
import { IAvoAuthoritiesList } from "./IAvoAuthoritiesList.sol";
import { AvoWalletErrors } from "./AvoWalletErrors.sol";
import { AvoCoreConstants, AvoCoreConstantsOverride, AvoCoreVariablesSlot0, AvoCoreVariablesSlot1, AvoCoreVariablesSlot2, AvoCoreVariablesSlot3, AvoCoreSlotGaps } from "./AvoCoreVariables.sol";

abstract contract AvoWalletConstants is AvoCoreConstants, AvoCoreConstantsOverride, AvoWalletErrors {
    // constants for EIP712 values (can't be overriden as immutables as other AvoCore constants, strings not supported)
    string public constant DOMAIN_SEPARATOR_NAME = "Avocado-Safe";
    string public constant DOMAIN_SEPARATOR_VERSION = "3.0.0";

    /************************************|
    |            CUSTOM CONSTANTS        |
    |___________________________________*/

    /// @notice Authorities <> AvoSafes mapping list contract for easy on-chain tracking
    IAvoAuthoritiesList public immutable avoAuthoritiesList;

    /***********************************|
    |            CONSTRUCTOR            |
    |__________________________________*/

    // @dev use 52_000 as reserve gas for `castAuthorized()`. Usually it will cost less but 52_000 is the maximum amount
    // pay fee logic etc. could cost on maximum logic execution
    constructor(
        IAvoVersionsRegistry avoVersionsRegistry_,
        address avoForwarder_,
        IAvoAuthoritiesList avoAuthoritiesList_,
        uint256 authorizedMinFee_,
        uint256 authorizedMaxFee_,
        address authorizedFeeCollector_
    )
        AvoCoreConstants(avoVersionsRegistry_, avoForwarder_)
        AvoCoreConstantsOverride(
            DOMAIN_SEPARATOR_NAME,
            DOMAIN_SEPARATOR_VERSION,
            52_000,
            12_000,
            authorizedMinFee_,
            authorizedMaxFee_,
            authorizedFeeCollector_,
            false
        )
    {
        if (address(avoAuthoritiesList_) == address(0)) {
            revert AvoWallet__InvalidParams();
        }
        avoAuthoritiesList = avoAuthoritiesList_;
    }
}

/// @notice Defines storage variables for AvoWallet
abstract contract AvoWalletVariables is
    AvoWalletConstants,
    AvoCoreVariablesSlot0,
    AvoCoreVariablesSlot1,
    AvoCoreVariablesSlot2,
    AvoCoreVariablesSlot3,
    AvoCoreSlotGaps
{
    // ----------- storage slot 0 to 53 through inheritance, see respective contracts -----------

    /***********************************|
    |        CUSTOM STORAGE VARS        |
    |__________________________________*/

    // ----------- storage slot 54 -----------

    /// @notice mapping for allowed authorities. Authorities can trigger actions through signature & AvoForwarder
    ///         just like the owner
    mapping(address => uint256) public authorities;

    /***********************************|
    |            CONSTRUCTOR            |
    |__________________________________*/

    constructor(
        IAvoVersionsRegistry avoVersionsRegistry_,
        address avoForwarder_,
        IAvoAuthoritiesList avoAuthoritiesList_,
        uint256 authorizedMinFee_,
        uint256 authorizedMaxFee_,
        address authorizedFeeCollector_
    )
        AvoWalletConstants(
            avoVersionsRegistry_,
            avoForwarder_,
            avoAuthoritiesList_,
            authorizedMinFee_,
            authorizedMaxFee_,
            authorizedFeeCollector_
        )
    {}
}

