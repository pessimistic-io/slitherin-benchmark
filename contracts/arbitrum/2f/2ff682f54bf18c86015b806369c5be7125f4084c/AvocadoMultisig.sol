// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { ECDSA } from "./ECDSA.sol";
import { Address } from "./Address.sol";
import { IERC1271 } from "./IERC1271.sol";

import { IAvoRegistry } from "./IAvoRegistry.sol";
import { IAvoSignersList } from "./IAvoSignersList.sol";
import { IAvocadoMultisigV1Base } from "./IAvocadoMultisigV1.sol";
import { IAvocado } from "./Avocado.sol";
import { IAvoConfigV1 } from "./IAvoConfigV1.sol";
import { AvocadoMultisigCore } from "./AvocadoMultisigCore.sol";

// --------------------------- DEVELOPER NOTES -----------------------------------------
// @dev IMPORTANT: all storage variables go into AvocadoMultisigVariables.sol
// -------------------------------------------------------------------------------------

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvocadoMultisig v1.0.1
/// @notice Smart wallet enabling meta transactions through multiple EIP712 signatures (Multisig n out of m).
///
/// Supports:
/// - Executing arbitrary actions
/// - Receiving NFTs (ERC721)
/// - Receiving ERC1155 tokens
/// - ERC1271 smart contract signatures
/// - Instadapp Flashloan callbacks
///
/// The `cast` method allows the AvoForwarder (relayer) to execute multiple arbitrary actions authorized by signature.
///
/// Broadcasters are expected to call the AvoForwarder contract `execute()` method, which also automatically
/// deploys an AvocadoMultisig if necessary first.
///
/// Upgradeable by calling `upgradeTo` through a `cast` / `castAuthorized` call.
///
/// The `castAuthorized` method allows the signers of the wallet to execute multiple arbitrary actions with signatures
/// without the AvoForwarder in between, to guarantee the smart wallet is truly non-custodial.
///
/// _@dev Notes:_
/// - This contract implements parts of EIP-2770 in a minimized form. E.g. domainSeparator is immutable etc.
/// - This contract does not implement ERC2771, because trusting an upgradeable "forwarder" bears a security
/// risk for this non-custodial wallet.
/// - Signature related logic is based off of OpenZeppelin EIP712Upgradeable.
/// - All signatures are validated for defaultChainId of `63400` instead of `block.chainid` from opcode (EIP-1344).
/// - For replay protection, the current `block.chainid` instead is used in the EIP-712 salt.
interface AvocadoMultisig_V1 {

}

/// @dev Simple contract to upgrade the implementation address stored at storage slot 0x0.
///      Mostly based on OpenZeppelin ERC1967Upgrade contract, adapted with onlySelf etc.
///      IMPORTANT: For any new implementation, the upgrade method MUST be in the implementation itself,
///      otherwise it can not be upgraded anymore!
abstract contract AvocadoMultisigSelfUpgradeable is AvocadoMultisigCore {
    /// @notice upgrade the contract to a new implementation address.
    ///         - Must be a valid version at the AvoRegistry.
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param avoImplementation_       New contract address
    /// @param afterUpgradeHookData_    flexible bytes for custom usage in after upgrade hook logic
    //
    // Implementation must call `_afterUpgradeHook()`
    function upgradeTo(address avoImplementation_, bytes calldata afterUpgradeHookData_) public onlySelf {
        if (avoImplementation_ == _avoImpl) {
            return;
        }

        // checks that `avoImplementation_` is a valid version at registry. reverts if not.
        avoRegistry.requireValidAvoVersion(avoImplementation_);

        // store previous implementation address to pass to after upgrade hook, for version x > version y specific logic
        address fromImplementation_ = _avoImpl;

        _avoImpl = avoImplementation_;
        emit Upgraded(avoImplementation_);

        // Address.functionDelegateCall will revert if success = false
        Address.functionDelegateCall(
            avoImplementation_,
            abi.encodeCall(this._afterUpgradeHook, (fromImplementation_, afterUpgradeHookData_))
        );
    }

    /// @notice hook called after executing an upgrade from previous `fromImplementation_`, with flexible bytes `data_`
    function _afterUpgradeHook(address fromImplementation_, bytes calldata data_) public virtual onlySelf {}
}

abstract contract AvocadoMultisigProtected is AvocadoMultisigCore {
    /***********************************|
    |             ONLY SELF             |
    |__________________________________*/

    /// @notice occupies the sequential `avoNonces_` in storage. This can be used to cancel / invalidate
    ///         a previously signed request(s) because the nonce will be "used" up.
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param  avoNonces_ sequential ascending ordered nonces to be occupied in storage.
    ///         E.g. if current AvoNonce is 77 and txs are queued with avoNonces 77, 78 and 79,
    ///         then you would submit [78, 79] here because 77 will be occupied by the tx executing
    ///         `occupyAvoNonces()` as an action itself. If executing via non-sequential nonces, you would
    ///         submit [77, 78, 79].
    ///         - Maximum array length is 5.
    ///         - gap from the current avoNonce will revert (e.g. [79, 80] if current one is 77)
    function occupyAvoNonces(uint88[] calldata avoNonces_) external onlySelf {
        uint256 avoNoncesLength_ = avoNonces_.length;
        if (avoNoncesLength_ == 0) {
            // in case to cancel just one nonce via normal sequential nonce execution itself
            return;
        }

        if (avoNoncesLength_ > 5) {
            revert AvocadoMultisig__InvalidParams();
        }

        uint256 nextAvoNonce_ = _avoNonce;

        for (uint256 i; i < avoNoncesLength_; ) {
            if (avoNonces_[i] == nextAvoNonce_) {
                // nonce to occupy is valid -> must match the current avoNonce
                emit AvoNonceOccupied(nextAvoNonce_);

                nextAvoNonce_++;
            } else if (avoNonces_[i] > nextAvoNonce_) {
                // input nonce is not smaller or equal current nonce -> invalid sorted ascending input params
                revert AvocadoMultisig__InvalidParams();
            }
            // else while nonce to occupy is < current nonce, skip ahead

            unchecked {
                ++i;
            }
        }

        _avoNonce = uint80(nextAvoNonce_);
    }

    /// @notice occupies the `nonSequentialNonces_` in storage. This can be used to cancel / invalidate
    ///         previously signed request(s) because the nonce will be "used" up.
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param  nonSequentialNonces_ the non-sequential nonces to occupy
    function occupyNonSequentialNonces(bytes32[] calldata nonSequentialNonces_) external onlySelf {
        uint256 nonSequentialNoncesLength_ = nonSequentialNonces_.length;

        for (uint256 i; i < nonSequentialNoncesLength_; ) {
            nonSequentialNonces[nonSequentialNonces_[i]] = 1;

            emit NonSequentialNonceOccupied(nonSequentialNonces_[i]);

            unchecked {
                ++i;
            }
        }
    }

    /***********************************|
    |         FLASHLOAN CALLBACK        |
    |__________________________________*/

    /// @dev                    callback used by Instadapp Flashloan Aggregator, executes operations while owning
    ///                         the flashloaned amounts. `data_` must contain actions, one of them must pay back flashloan
    // /// @param assets_       assets_ received a flashloan for
    // /// @param amounts_      flashloaned amounts for each asset
    // /// @param premiums_     fees to pay for the flashloan
    /// @param initiator_       flashloan initiator -> must be this contract
    /// @param data_            data bytes containing the `abi.encoded()` actions that are executed like in `CastParams.actions`
    function executeOperation(
        address[] calldata /*  assets_ */,
        uint256[] calldata /*  amounts_ */,
        uint256[] calldata /*  premiums_ */,
        address initiator_,
        bytes calldata data_
    ) external returns (bool) {
        // @dev using the valid case inverted via one ! to optimize gas usage
        // data_ includes id and actions
        if (
            !(_transientAllowHash ==
                bytes31(keccak256(abi.encode(data_, block.timestamp, EXECUTE_OPERATION_SELECTOR))) &&
                initiator_ == address(this))
        ) {
            revert AvocadoMultisig__Unauthorized();
        }

        // get and reset transient id
        uint256 id_ = uint256(_transientId);
        _transientId = 0;

        // decode actions to be executed after getting the flashloan and id_ packed into the data_
        _executeActions(abi.decode(data_, (Action[])), id_, true);

        return true;
    }

    /***********************************|
    |         INDIRECT INTERNAL         |
    |__________________________________*/

    /// @dev             executes a low-level .call or .delegateCall on all `actions_`.
    ///                  Can only be self-called by this contract under certain conditions, essentially internal method.
    ///                  This is called like an external call to create a separate execution frame.
    ///                  This way we can revert all the `actions_` if one fails without reverting the whole transaction.
    /// @param actions_  the actions to execute (target, data, value, operation)
    /// @param id_       id for `actions_`, see `CastParams.id`
    function _callTargets(Action[] calldata actions_, uint256 id_) external payable {
        // _transientAllowHash must be set or 0x000000000000000000000000000000000000dEaD used for backend gas estimations
        if (
            !(_transientAllowHash ==
                bytes31(keccak256(abi.encode(actions_, id_, block.timestamp, _CALL_TARGETS_SELECTOR))) ||
                tx.origin == 0x000000000000000000000000000000000000dEaD)
        ) {
            revert AvocadoMultisig__Unauthorized();
        }

        _executeActions(actions_, id_, false);
    }
}

abstract contract AvocadoMultisigEIP1271 is AvocadoMultisigCore {
    /// @dev length of a normal expected ECDSA signature
    uint256 private constant _SIGNATURE_LENGTH = 65;
    /// @dev signature must be 65 bytes or otherwise at least 90 bytes to be either a multiple
    /// of 85 bytes + prefix or a decodable `SignatureParams` struct array.
    uint256 private constant _MIN_SIGNATURE_LENGTH = 90;
    /// @dev prefix to signal decoding with multiple of 85 bytes is "0xDEC0DE6520" (appending 000000 to get to bytes8)
    bytes8 private constant _PREFIX_SIGNAL = bytes8(uint64(0xdec0de6520000000));
    /// @dev prefix length to cut of is 5 bytes (DE_C0_DE_65_20)
    uint256 private constant _PREFIX_SIGNAL_LENGTH = 5;

    /// @inheritdoc IERC1271
    /// @param signature This can be one of the following:
    ///         - empty: `hash` must be a previously signed message in storage then.
    ///         - 65 bytes: owner signature for a Multisig with only owner as signer (requiredSigners = 1, signers=[owner]).
    ///         - a multiple of 85 bytes, through grouping of 65 bytes signature + 20 bytes signer address each.
    ///           To signal decoding this way, the signature bytes must be prefixed with `0xDEC0DE6520`.
    ///         - the `abi.encode` result for `SignatureParams` struct array.
    /// @dev reverts with `AvocadoMultisig__InvalidEIP1271Signature` or `AvocadoMultisig__InvalidParams` if signature is invalid.
    /// @dev input `message_` is hashed with `domainSeparatorV4()` according to EIP712 typed data (`EIP1271_TYPE_HASH`)
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view override returns (bytes4 magicValue) {
        // hashing with domain separator mitigates any potential replaying on other networks or other Avocados of the same owner
        hash = ECDSA.toTypedDataHash(_domainSeparatorV4(), keccak256(abi.encode(EIP1271_TYPE_HASH, hash)));

        // @dev function params without _ for inheritdoc
        if (signature.length == 0) {
            // must be pre-allow-listed via `signMessage` method
            if (_signedMessages[hash] != 1) {
                revert AvocadoMultisig__InvalidEIP1271Signature();
            }
        } else {
            // decode signaturesParams_ from bytes signature
            SignatureParams[] memory signaturesParams_;

            uint256 signatureLength_ = signature.length;

            if (signatureLength_ == _SIGNATURE_LENGTH) {
                // signature must be from owner for a Multisig with requiredSigners = 1, signers=[owner]
                signaturesParams_ = new SignatureParams[](1);
                signaturesParams_[0] = SignatureParams({
                    signature: signature,
                    signer: IAvocado(address(this))._owner()
                });
            } else if (signatureLength_ < _MIN_SIGNATURE_LENGTH) {
                revert AvocadoMultisig__InvalidEIP1271Signature();
            } else if (bytes8(signature[0:_PREFIX_SIGNAL_LENGTH]) == _PREFIX_SIGNAL) {
                // if signature is prefixed with _PREFIX_SIGNAL ("0xDEC0DE6520") ->
                // signature after the prefix should be divisible by 85
                // (65 bytes signature and 20 bytes signer address) each
                uint256 signaturesCount_;
                unchecked {
                    // -_PREFIX_SIGNAL_LENGTH to not count prefix
                    signaturesCount_ = (signatureLength_ - _PREFIX_SIGNAL_LENGTH) / 85;
                }
                signaturesParams_ = new SignatureParams[](signaturesCount_);

                for (uint256 i; i < signaturesCount_; ) {
                    // used operations can not overflow / underflow
                    unchecked {
                        // +_PREFIX_SIGNAL_LENGTH to start after prefix
                        uint256 signerOffset_ = (i * 85) + _SIGNATURE_LENGTH + _PREFIX_SIGNAL_LENGTH;

                        bytes memory signerBytes_ = signature[signerOffset_:signerOffset_ + 20];
                        address signer_;
                        // cast bytes to address in the easiest way via assembly
                        assembly {
                            signer_ := shr(96, mload(add(signerBytes_, 0x20)))
                        }

                        signaturesParams_[i] = SignatureParams({
                            signature: signature[(signerOffset_ - _SIGNATURE_LENGTH):signerOffset_],
                            signer: signer_
                        });

                        ++i;
                    }
                }
            } else {
                // multiple signatures are present that should form `SignatureParams[]` through abi.decode
                // @dev this will fail and revert if invalid typed data is passed in
                signaturesParams_ = abi.decode(signature, (SignatureParams[]));
            }

            (bool validSignature_, ) = _verifySig(
                hash,
                signaturesParams_,
                // we have no way to know nonce type, so make sure validity test covers everything.
                // setting this flag true will check that the digest is not a used non-sequential nonce.
                // unfortunately, for sequential nonces it adds unneeded verification and gas cost,
                // because the check will always pass, but there is no way around it.
                true
            );
            if (!validSignature_) {
                revert AvocadoMultisig__InvalidEIP1271Signature();
            }
        }

        return EIP1271_MAGIC_VALUE;
    }

    /// @notice Marks a bytes32 `message_` (signature digest) as signed, making it verifiable by EIP-1271 `isValidSignature()`.
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param message_ data hash to be allow-listed as signed
    /// @dev input `message_` is hashed with `domainSeparatorV4()` according to EIP712 typed data (`EIP1271_TYPE_HASH`)
    function signMessage(bytes32 message_) external onlySelf {
        // hashing with domain separator mitigates any potential replaying on other networks or other Avocados of the same owner
        message_ = ECDSA.toTypedDataHash(_domainSeparatorV4(), keccak256(abi.encode(EIP1271_TYPE_HASH, message_)));

        _signedMessages[message_] = 1;

        emit SignedMessage(message_);
    }

    /// @notice Removes a previously `signMessage()` signed bytes32 `message_` (signature digest).
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param message_ data hash to be removed from allow-listed signatures
    function removeSignedMessage(bytes32 message_) external onlySelf {
        _signedMessages[message_] = 0;

        emit RemoveSignedMessage(message_);
    }
}

abstract contract AvocadoMultisigSigners is AvocadoMultisigCore {
    /// @inheritdoc IAvocadoMultisigV1Base
    function isSigner(address signer_) public view returns (bool) {
        address[] memory allowedSigners_ = _getSigners(); // includes owner

        uint256 allowedSignersLength_ = allowedSigners_.length;
        for (uint256 i; i < allowedSignersLength_; ) {
            if (allowedSigners_[i] == signer_) {
                return true;
            }

            unchecked {
                ++i;
            }
        }

        return false;
    }

    /// @notice adds `addSigners_` to allowed signers and sets required signers count to `requiredSigners_`
    /// Note the `addSigners_` to be added must:
    ///     - NOT be duplicates (already present in current allowed signers)
    ///     - NOT be the zero address
    ///     - be sorted ascending
    function addSigners(address[] calldata addSigners_, uint8 requiredSigners_) external onlySelf {
        uint256 addSignersLength_ = addSigners_.length;

        // check array length and make sure signers can not be zero address
        // (only check for first elem needed, rest is checked through sort)
        if (addSignersLength_ == 0 || addSigners_[0] == address(0)) {
            revert AvocadoMultisig__InvalidParams();
        }

        address[] memory currentSigners_ = _getSigners();
        uint256 currentSignersLength_ = currentSigners_.length;

        uint256 newSignersLength_ = currentSignersLength_ + addSignersLength_;
        if (newSignersLength_ > MAX_SIGNERS_COUNT) {
            revert AvocadoMultisig__InvalidParams();
        }
        address[] memory newSigners_ = new address[](newSignersLength_);

        uint256 currentSignersPos_ = 0; // index of position of loop in currentSigners_ array
        uint256 addedCount_ = 0; // keep track of number of added signers of current signers array
        for (uint256 i; i < newSignersLength_; ) {
            unchecked {
                currentSignersPos_ = i - addedCount_;
            }

            if (
                addedCount_ == addSignersLength_ ||
                (currentSignersPos_ < currentSignersLength_ &&
                    currentSigners_[currentSignersPos_] < addSigners_[addedCount_])
            ) {
                // if already added all signers or if current signer is <  next signer, keep the current one
                newSigners_[i] = currentSigners_[currentSignersPos_];
            } else {
                //  add signer
                newSigners_[i] = addSigners_[addedCount_];

                emit SignerAdded(addSigners_[addedCount_]);

                unchecked {
                    ++addedCount_;
                }
            }

            if (i > 0 && newSigners_[i] <= newSigners_[i - 1]) {
                // make sure input signers are ordered ascending and no duplicate signers are added
                revert AvocadoMultisig__InvalidParams();
            }

            unchecked {
                ++i;
            }
        }

        // update values in storage
        _setSigners(newSigners_, requiredSigners_); // updates `signersCount`, checks and sets `requiredSigners_`

        // sync mappings at AvoSignersList -> must happen *after* storage write update
        // use call with success_ here to not block users transaction if the helper contract fails.
        // in case of failure, only emit event ListSyncFailed() so off-chain tracking is informed to react.
        (bool success_, ) = address(avoSignersList).call(
            abi.encodeCall(IAvoSignersList.syncAddAvoSignerMappings, (address(this), addSigners_))
        );
        if (!success_) {
            emit ListSyncFailed();
        }
    }

    /// @notice removes `removeSigners_` from allowed signers and sets required signers count to `requiredSigners_`
    /// Note the `removeSigners_` to be removed must:
    ///     - NOT be the owner
    ///     - be sorted ascending
    ///     - be present in current allowed signers
    function removeSigners(address[] calldata removeSigners_, uint8 requiredSigners_) external onlySelf {
        uint256 removeSignersLength_ = removeSigners_.length;
        if (removeSignersLength_ == 0) {
            revert AvocadoMultisig__InvalidParams();
        }

        address[] memory currentSigners_ = _getSigners();
        uint256 currentSignersLength_ = currentSigners_.length;

        uint256 newSignersLength_ = currentSignersLength_ - removeSignersLength_;

        address owner_ = IAvocado(address(this))._owner();

        address[] memory newSigners_ = new address[](newSignersLength_);

        uint256 currentInsertPos_ = 0; // index of position of loop in `newSigners_` array
        uint256 removedCount_ = 0; // keep track of number of removed signers of current signers array
        for (uint256 i; i < currentSignersLength_; ) {
            unchecked {
                currentInsertPos_ = i - removedCount_;
            }
            if (removedCount_ == removeSignersLength_ || currentSigners_[i] != removeSigners_[removedCount_]) {
                // if already removed all signers or if current signer is not a signer to be removed, keep the current one
                if (currentInsertPos_ < newSignersLength_) {
                    // make sure index to insert is within bounds of newSigners_ array
                    newSigners_[currentInsertPos_] = currentSigners_[i];
                } else {
                    // a signer has been passed in that was not found and thus we would be inserting at a position
                    // in newSigners_ array that overflows its length
                    revert AvocadoMultisig__InvalidParams();
                }
            } else {
                // remove signer, i.e. do not insert the current signer in the newSigners_ array

                // make sure signer to be removed is not the owner
                if (removeSigners_[removedCount_] == owner_) {
                    revert AvocadoMultisig__InvalidParams();
                }

                emit SignerRemoved(removeSigners_[removedCount_]);

                unchecked {
                    ++removedCount_;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (removedCount_ != removeSignersLength_) {
            // this case should not be possible but it is a good cheap extra check to make sure nothing goes wrong
            // and the contract does not end up in an invalid signers state
            revert AvocadoMultisig__InvalidParams();
        }

        // update values in storage
        _setSigners(newSigners_, requiredSigners_); // updates `signersCount`, checks and sets `requiredSigners_`

        // sync mappings at AvoSignersList -> must happen *after* storage write update
        // use call with success_ here to not block users transaction if the helper contract fails.
        // in case of failure, only emit event ListSyncFailed() so off-chain tracking is informed to react.
        (bool success_, ) = address(avoSignersList).call(
            abi.encodeCall(IAvoSignersList.syncRemoveAvoSignerMappings, (address(this), removeSigners_))
        );
        if (!success_) {
            emit ListSyncFailed();
        }
    }

    /// @notice sets number of required signers for a valid request to `requiredSigners_`
    function setRequiredSigners(uint8 requiredSigners_) external onlySelf {
        _setRequiredSigners(requiredSigners_);
    }
}

abstract contract AvocadoMultisigCast is AvocadoMultisigCore {
    /// @inheritdoc IAvocadoMultisigV1Base
    function getSigDigest(
        CastParams memory params_,
        CastForwardParams memory forwardParams_
    ) public view returns (bytes32) {
        return _getSigDigest(params_, forwardParams_);
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function verify(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_,
        SignatureParams[] calldata signaturesParams_
    ) external view returns (bool) {
        _validateParams(
            params_.actions.length,
            params_.avoNonce,
            forwardParams_.validAfter,
            forwardParams_.validUntil,
            forwardParams_.value
        );

        (bool validSignature_, ) = _verifySig(
            getSigDigest(params_, forwardParams_),
            signaturesParams_,
            params_.avoNonce == -1
        );

        // signature must be valid
        if (!validSignature_) {
            revert AvocadoMultisig__InvalidSignature();
        }

        return true;
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function cast(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_,
        SignatureParams[] memory signaturesParams_
    ) external payable returns (bool success_, string memory revertReason_) {
        bool notSimulate_ = tx.origin != 0x000000000000000000000000000000000000dEaD;
        {
            if (msg.sender != avoForwarder) {
                // sender must be the allowed AvoForwarder
                revert AvocadoMultisig__Unauthorized();
            }

            unchecked {
                // compare actual sent gas to user instructed gas, adding 500 to `gasleft()` for approx. already used gas
                if ((gasleft() + 500) < forwardParams_.gas) {
                    // relayer has not sent enough gas to cover gas limit as user instructed.
                    // this error should not be blamed on the user but rather on the relayer
                    revert AvocadoMultisig__InsufficientGasSent();
                }
            }

            if (notSimulate_) {
                // @dev gas measurement: uses maximum 685 gas when all params must be validated
                _validateParams(
                    params_.actions.length,
                    params_.avoNonce,
                    forwardParams_.validAfter,
                    forwardParams_.validUntil,
                    forwardParams_.value
                );
            }
        }

        bytes32 digest_ = getSigDigest(params_, forwardParams_);
        address[] memory signers_;
        {
            if (notSimulate_) {
                bool validSignature_;
                (validSignature_, signers_) = _verifySig(digest_, signaturesParams_, params_.avoNonce == -1);

                // signature must be valid
                if (!validSignature_) {
                    revert AvocadoMultisig__InvalidSignature();
                }
            }
        }

        {
            uint256 reserveGas_;
            unchecked {
                reserveGas_ = CAST_EVENTS_RESERVE_GAS + _dynamicReserveGas(signers_.length, params_.metadata.length);
            }

            (success_, revertReason_) = _executeCast(
                params_,
                reserveGas_,
                params_.avoNonce == -1 ? digest_ : bytes32(0)
            );
        }

        // @dev on changes in the code below this point, measure the needed reserve gas via `gasleft()` anew
        // and update the reserve gas constant amounts.
        // gas measurement currently: ~7500 gas for emit event with max revertReason length
        if (success_) {
            emit CastExecuted(params_.source, msg.sender, signers_, params_.metadata);
        } else {
            emit CastFailed(params_.source, msg.sender, signers_, revertReason_, params_.metadata);
        }
        // @dev ending point for measuring reserve gas should be here. Also see comment in `AvocadoMultisigCore._executeCast()`
    }
}

abstract contract AvocadoMultisigCastAuthorized is AvocadoMultisigCore {
    /// @inheritdoc IAvocadoMultisigV1Base
    function getSigDigestAuthorized(
        CastParams memory params_,
        CastAuthorizedParams memory authorizedParams_
    ) public view returns (bytes32) {
        return _getSigDigestAuthorized(params_, authorizedParams_);
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function verifyAuthorized(
        CastParams calldata params_,
        CastAuthorizedParams calldata authorizedParams_,
        SignatureParams[] calldata signaturesParams_
    ) external view returns (bool) {
        {
            // make sure actions are defined and nonce is valid
            _validateParams(
                params_.actions.length,
                params_.avoNonce,
                authorizedParams_.validAfter,
                authorizedParams_.validUntil,
                0 // no value param in authorized interaction
            );
        }

        (bool validSignature_, ) = _verifySig(
            getSigDigestAuthorized(params_, authorizedParams_),
            signaturesParams_,
            params_.avoNonce == -1
        );

        // signature must be valid
        if (!validSignature_) {
            revert AvocadoMultisig__InvalidSignature();
        }

        return true;
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function castAuthorized(
        CastParams calldata params_,
        CastAuthorizedParams calldata authorizedParams_,
        SignatureParams[] memory signaturesParams_
    ) external payable returns (bool success_, string memory revertReason_) {
        uint256 gasSnapshot_ = gasleft();

        {
            // make sure actions are defined and nonce is valid
            _validateParams(
                params_.actions.length,
                params_.avoNonce,
                authorizedParams_.validAfter,
                authorizedParams_.validUntil,
                0 // no value param in authorized interaction
            );
        }

        bytes32 digest_ = getSigDigestAuthorized(params_, authorizedParams_);
        address[] memory signers_;
        {
            bool validSignature_;
            (validSignature_, signers_) = _verifySig(digest_, signaturesParams_, params_.avoNonce == -1);

            // signature must be valid
            if (!validSignature_) {
                revert AvocadoMultisig__InvalidSignature();
            }
        }

        {
            uint256 reserveGas_;
            unchecked {
                reserveGas_ =
                    CAST_AUTHORIZED_RESERVE_GAS +
                    _dynamicReserveGas(signers_.length, params_.metadata.length);
            }

            (success_, revertReason_) = _executeCast(
                params_,
                reserveGas_,
                params_.avoNonce == -1 ? digest_ : bytes32(0)
            );

            // @dev on changes in the code below this point, measure the needed reserve gas via `gasleft()` anew
            // and update reserve gas constant amounts
            if (success_) {
                emit CastExecuted(params_.source, msg.sender, signers_, params_.metadata);
            } else {
                emit CastFailed(params_.source, msg.sender, signers_, revertReason_, params_.metadata);
            }
        }

        // @dev `_payAuthorizedFee()` costs ~24.5k gas for if a fee is configured and maxFee is set
        _payAuthorizedFee(gasSnapshot_, authorizedParams_.maxFee);

        // @dev ending point for measuring reserve gas should be here. Also see comment in `AvocadoMultisigCore._executeCast()`
    }
}

contract AvocadoMultisig is
    AvocadoMultisigCore,
    AvocadoMultisigSelfUpgradeable,
    AvocadoMultisigProtected,
    AvocadoMultisigEIP1271,
    AvocadoMultisigSigners,
    AvocadoMultisigCast,
    AvocadoMultisigCastAuthorized
{
    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    /// @notice                        constructor sets multiple immutable values for contracts and payFee fallback logic.
    /// @param avoRegistry_            address of the avoRegistry (proxy) contract
    /// @param avoForwarder_           address of the avoForwarder (proxy) contract
    ///                                to forward tx with valid signatures. must be valid version in AvoRegistry.
    /// @param avoSignersList_         address of the AvoSignersList (proxy) contract
    /// @param avoConfigV1_            AvoConfigV1 contract holding values for authorizedFee values
    constructor(
        IAvoRegistry avoRegistry_,
        address avoForwarder_,
        IAvoSignersList avoSignersList_,
        IAvoConfigV1 avoConfigV1_
    ) AvocadoMultisigCore(avoRegistry_, avoForwarder_, avoSignersList_, avoConfigV1_) {}

    /// @inheritdoc IAvocadoMultisigV1Base
    function initialize() public initializer {
        _initialize();
    }

    /***********************************|
    |            PUBLIC API             |
    |__________________________________*/

    receive() external payable {}

    /// @inheritdoc IAvocadoMultisigV1Base
    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function signers() public view returns (address[] memory signers_) {
        return _getSigners();
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function requiredSigners() public view returns (uint8) {
        return _getRequiredSigners();
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function signersCount() public view returns (uint8) {
        return _getSignersCount();
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function owner() public view returns (address) {
        return IAvocado(address(this))._owner();
    }

    /// @inheritdoc IAvocadoMultisigV1Base
    function index() public view returns (uint32) {
        return uint32(IAvocado(address(this))._data() >> 160);
    }

    /// @notice incrementing nonce for each valid tx executed (to ensure uniqueness)
    function avoNonce() public view returns (uint256) {
        return uint256(_avoNonce);
    }
}

