// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { SSTORE2 } from "./SSTORE2.sol";

import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";
import { IAvoSignersList } from "./IAvoSignersList.sol";
import { AvoMultisigErrors } from "./AvoMultisigErrors.sol";
import { AvoCoreConstants, AvoCoreConstantsOverride, AvoCoreVariablesSlot0, AvoCoreVariablesSlot1, AvoCoreVariablesSlot2, AvoCoreVariablesSlot3, AvoCoreSlotGaps } from "./AvoCoreVariables.sol";

abstract contract AvoMultisigConstants is AvoCoreConstants, AvoCoreConstantsOverride, AvoMultisigErrors {
    // constants for EIP712 values (can't be overriden as immutables as other AvoCore constants, strings not supported)
    string public constant DOMAIN_SEPARATOR_NAME = "Avocado-Multisig";
    string public constant DOMAIN_SEPARATOR_VERSION = "3.0.0";

    /************************************|
    |            CUSTOM CONSTANTS        |
    |___________________________________*/

    /// @notice Signers <> AvoMultiSafes mapping list contract for easy on-chain tracking
    IAvoSignersList public immutable avoSignersList;

    /// @notice defines the max signers count for the Multisig. This is chosen deliberately very high, as there shouldn't
    /// really be a limit on signers count in practice. It is extremely unlikely that anyone runs into this very high
    /// limit but it helps to implement test coverage within this given limit
    uint256 public constant MAX_SIGNERS_COUNT = 90;

    /// @dev each additional signer costs ~358 gas to emit in the CastFailed / CastExecuted event. this amount must be
    /// factored in dynamically depending on the number of signers (PER_SIGNER_RESERVE_GAS * number of signers)
    uint256 internal constant PER_SIGNER_RESERVE_GAS = 370;

    /***********************************|
    |            CONSTRUCTOR            |
    |__________________________________*/

    // @dev use 52_000 as reserve gas for `castAuthorized()`. Usually it will cost less but 52_000 is the maximum amount
    // pay fee logic etc. could cost on maximum logic execution
    constructor(
        IAvoVersionsRegistry avoVersionsRegistry_,
        address avoForwarder_,
        IAvoSignersList avoSignersList_,
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
            true
        )
    {
        if (address(avoSignersList_) == address(0)) {
            revert AvoMultisig__InvalidParams();
        }
        avoSignersList = avoSignersList_;
    }
}

/// @notice Defines storage variables for AvoMultisig
abstract contract AvoMultisigVariables is
    AvoMultisigConstants,
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

    /// @dev signers are stored with SSTORE2 to save gas, especially for storage checks at delegateCalls.
    /// getter and setter is implemented below
    address internal _signersPointer;

    /// @notice signers count required to reach quorom and be able to execute actions
    uint8 public requiredSigners;

    /// @notice number of signers currently listed as allowed signers
    //
    // @dev should be updated directly via `_setSigners()`
    uint8 public signersCount;

    /***********************************|
    |            CONSTRUCTOR            |
    |__________________________________*/

    constructor(
        IAvoVersionsRegistry avoVersionsRegistry_,
        address avoForwarder_,
        IAvoSignersList avoSignersList_,
        uint256 authorizedMinFee_,
        uint256 authorizedMaxFee_,
        address authorizedFeeCollector_
    )
        AvoMultisigConstants(
            avoVersionsRegistry_,
            avoForwarder_,
            avoSignersList_,
            authorizedMinFee_,
            authorizedMaxFee_,
            authorizedFeeCollector_
        )
    {}

    /***********************************|
    |      SIGNERS GETTER / SETTER      |
    |__________________________________*/

    /// @dev writes `signers_` to storage with SSTORE2 and updates `signersCount`
    function _setSigners(address[] memory signers_) internal {
        signersCount = uint8(signers_.length);

        _signersPointer = SSTORE2.write(abi.encode(signers_));
    }

    /// @dev reads signers from storage with SSTORE2
    function _getSigners() internal view returns (address[] memory) {
        address pointer_ = _signersPointer;
        if (pointer_ == address(0)) {
            return new address[](0);
        }

        return abi.decode(SSTORE2.read(_signersPointer), (address[]));
    }
}

