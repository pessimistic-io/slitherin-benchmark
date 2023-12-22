// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { ECDSA } from "./ECDSA.sol";
import { Address } from "./Address.sol";
import { Strings } from "./Strings.sol";
import { ERC721Holder } from "./ERC721Holder.sol";
import { IERC1271 } from "./IERC1271.sol";
import { ERC1155Holder } from "./ERC1155Holder.sol";

import { InstaFlashReceiverInterface } from "./InstaFlashReceiverInterface.sol";
import { IAvoRegistry } from "./IAvoRegistry.sol";
import { IAvoSignersList } from "./IAvoSignersList.sol";
import { IAvocadoMultisigV1Base } from "./IAvocadoMultisigV1.sol";
import { IAvoConfigV1 } from "./IAvoConfigV1.sol";
import { IAvocado } from "./Avocado.sol";
import { AvocadoMultisigErrors } from "./AvocadoMultisigErrors.sol";
import { AvocadoMultisigEvents } from "./AvocadoMultisigEvents.sol";
import { AvocadoMultisigVariables } from "./AvocadoMultisigVariables.sol";
import { AvocadoMultisigInitializable } from "./AvocadoMultisigInitializable.sol";
import { AvocadoMultisigStructs } from "./AvocadoMultisigStructs.sol";
import { AvocadoMultisigProtected } from "./AvocadoMultisig.sol";

abstract contract AvocadoMultisigCore is
    AvocadoMultisigErrors,
    AvocadoMultisigEvents,
    AvocadoMultisigVariables,
    AvocadoMultisigStructs,
    AvocadoMultisigInitializable,
    ERC721Holder,
    ERC1155Holder,
    InstaFlashReceiverInterface,
    IERC1271,
    IAvocadoMultisigV1Base
{
    /// @dev ensures the method can only be called by the same contract itself.
    modifier onlySelf() {
        _requireSelfCalled();
        _;
    }

    /// @dev internal method for modifier logic to reduce bytecode size of contract.
    function _requireSelfCalled() internal view {
        if (msg.sender != address(this)) {
            revert AvocadoMultisig__Unauthorized();
        }
    }

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    constructor(
        IAvoRegistry avoRegistry_,
        address avoForwarder_,
        IAvoSignersList avoSignersList_,
        IAvoConfigV1 avoConfigV1_
    ) AvocadoMultisigVariables(avoRegistry_, avoForwarder_, avoSignersList_, avoConfigV1_) {
        // Ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /// @dev sets the initial state of the Multisig for `owner_` as owner and first and only required signer
    function _initialize() internal {
        address owner_ = IAvocado(address(this))._owner();

        // owner must be EOA
        if (Address.isContract(owner_) || owner_ == address(0)) {
            revert AvocadoMultisig__InvalidParams();
        }

        // set _transientAllowHash so refund behaviour is already active for first tx and this cost is applied to deployment
        _resetTransientStorage();

        // emit events
        emit SignerAdded(owner_);
        emit RequiredSignersSet(1);

        // add owner as signer at AvoSignersList
        address[] memory signers_ = new address[](1);
        signers_[0] = owner_;
        // use call with success_ here to not block users transaction if the helper contract fails.
        // in case of failure, only emit event ListSyncFailed() so off-chain tracking is informed to react.
        (bool success_, ) = address(avoSignersList).call(
            abi.encodeCall(IAvoSignersList.syncAddAvoSignerMappings, (address(this), signers_))
        );
        if (!success_) {
            emit ListSyncFailed();
        }
    }

    /***********************************|
    |               INTERNAL            |
    |__________________________________*/

    /// @dev                          Verifies a EIP712 signature, returning valid status in `isValid_` or reverting
    ///                               in case the params for the signatures / digest are wrong
    /// @param digest_                the EIP712 digest for the signature
    /// @param signaturesParams_      SignatureParams structs array for signature and signer:
    ///                               - signature: the EIP712 signature, 65 bytes ECDSA signature for a default EOA.
    ///                                 For smart contract signatures it must fulfill the requirements for the relevant
    ///                                 smart contract `.isValidSignature()` EIP1271 logic
    ///                               - signer: address of the signature signer.
    ///                                 Must match the actual signature signer or refer to the smart contract
    ///                                 that must be an allowed signer and validates signature via EIP1271
    /// @param  isNonSequentialNonce_ flag to signal verify with non sequential nonce or not
    /// @return isValid_              true if the signature is valid, false otherwise
    /// @return recoveredSigners_     recovered valid signer addresses of the signatures. In case that `isValid_` is
    ///                               false, the last element in the array with a value is the invalid signer
    function _verifySig(
        bytes32 digest_,
        SignatureParams[] memory signaturesParams_,
        bool isNonSequentialNonce_
    ) internal view returns (bool isValid_, address[] memory recoveredSigners_) {
        // gas measurements:
        // cost until the for loop in verify signature is:
        // 1 signer 3374 (_getSigners() with only owner is cheaper)
        // 2 signers 6473
        // every additional allowedSigner (!) + 160 gas (additional SSTORE2 load cost)
        // For non-sequential nonce additional cold SLOAD + check cost is ~2200
        // dynamic cost for verifying any additional signer 7500
        // So formula:
        // Avoado signersCount == 1 ? -> 11_000 gas
        // Avoado signersCount > 1 ? -> 6400  + allowedSignersCount * 160 + signersLength * 7500
        // is non Sequential nonce? + 2200
        // is smart contract signer? + buffer amount. A very basic ECDSA verify call like with e.g. MockSigner costs ~9k.
        uint256 signaturesLength_ = signaturesParams_.length;

        if (
            // enough signatures must be submitted to reach quorom of `requiredSigners`
            signaturesLength_ < _getRequiredSigners() ||
            // for non sequential nonce, if nonce is already used, the signature has already been used and is invalid
            (isNonSequentialNonce_ && nonSequentialNonces[digest_] == 1)
        ) {
            revert AvocadoMultisig__InvalidParams();
        }

        // fill recovered signers array for use in event emit
        recoveredSigners_ = new address[](signaturesLength_);

        // get current signers from storage
        address[] memory allowedSigners_ = _getSigners(); // includes owner
        uint256 allowedSignersLength_ = allowedSigners_.length;
        // track last allowed signer index for loop performance improvements
        uint256 lastAllowedSignerIndex_ = 0;

        bool isContract_ = false; // keeping this variable outside the loop so it is not re-initialized in each loop -> cheaper
        bool isAllowedSigner_ = false;
        for (uint256 i; i < signaturesLength_; ) {
            if (Address.isContract(signaturesParams_[i].signer)) {
                recoveredSigners_[i] = signaturesParams_[i].signer;
                // set flag that the signer is a contract so we don't have to check again in code below
                isContract_ = true;
            } else {
                // recover signer from signature
                recoveredSigners_[i] = ECDSA.recover(digest_, signaturesParams_[i].signature);

                if (signaturesParams_[i].signer != recoveredSigners_[i]) {
                    // signer does not match recovered signer. Either signer param is wrong or params used to
                    // build digest are not the same as for the signature
                    revert AvocadoMultisig__InvalidParams();
                }
            }

            // because signers in storage and signers from signatures input params must be ordered ascending,
            // the for loop can be optimized each new cycle to start from the position where the last signer
            // has been found.
            // this also ensures that input params signers must be ordered ascending off-chain
            // (which again is used to improve performance and simplifies ensuring unique signers)
            for (uint256 j = lastAllowedSignerIndex_; j < allowedSignersLength_; ) {
                if (allowedSigners_[j] == recoveredSigners_[i]) {
                    isAllowedSigner_ = true;
                    unchecked {
                        lastAllowedSignerIndex_ = j + 1; // set to j+1 so that next cycle starts at next array position
                    }
                    break;
                }

                // could be optimized by checking if allowedSigners_[j] > recoveredSigners_[i]
                // and immediately skipping with a `break;` if so. Because that implies that the recoveredSigners_[i]
                // can not be present in allowedSigners_ due to ascending sort.
                // But that would optimize the failing invalid case and increase cost for the default case where
                // the input data is valid -> skip.

                unchecked {
                    ++j;
                }
            }

            // validate if signer is allowed
            if (!isAllowedSigner_) {
                return (false, recoveredSigners_);
            } else {
                // reset `isAllowedSigner_` for next loop
                isAllowedSigner_ = false;
            }

            if (isContract_) {
                // validate as smart contract signature
                if (
                    IERC1271(signaturesParams_[i].signer).isValidSignature(digest_, signaturesParams_[i].signature) !=
                    EIP1271_MAGIC_VALUE
                ) {
                    // return value is not EIP1271_MAGIC_VALUE -> smart contract returned signature is invalid
                    return (false, recoveredSigners_);
                }

                // reset isContract for next loop (because defined outside of the loop to save gas)
                isContract_ = false;
            }
            // else already everything validated through recovered signer must be an allowed signer etc. in logic above

            unchecked {
                ++i;
            }
        }

        return (true, recoveredSigners_);
    }

    /// @dev returns the dynamic reserve gas to be kept back for emitting the CastExecuted or CastFailed event
    function _dynamicReserveGas(
        uint256 signersCount_,
        uint256 metadataLength_
    ) internal pure returns (uint256 reserveGas_) {
        unchecked {
            // the gas usage for the emitting the CastExecuted/CastFailed events depends on the signers count
            // the cost per signer is PER_SIGNER_RESERVE_GAS. We calculate this dynamically to ensure
            // enough reserve gas is reserved in Multisigs with a higher signersCount.
            // same for metadata bytes length, dynamically calculated with cost per byte for emit event
            reserveGas_ = (PER_SIGNER_RESERVE_GAS * signersCount_) + (EMIT_EVENT_COST_PER_BYTE * metadataLength_);
        }
    }

    /// @dev executes multiple cast actions according to CastParams `params_`, reserving `reserveGas_` in this contract.
    /// Uses a sequential nonce unless `nonSequentialNonce_` is set.
    /// @return success_ boolean flag indicating whether all actions have been executed successfully.
    /// @return revertReason_ if `success_` is false, then revert reason is returned as string here.
    function _executeCast(
        CastParams calldata params_,
        uint256 reserveGas_,
        bytes32 nonSequentialNonce_
    ) internal returns (bool success_, string memory revertReason_) {
        // set allowHash to signal allowed entry into _callTargets with actions in current block only
        _transientAllowHash = bytes31(
            keccak256(abi.encode(params_.actions, params_.id, block.timestamp, _CALL_TARGETS_SELECTOR))
        );

        // nonce must be used *always* if signature is valid
        if (nonSequentialNonce_ == bytes32(0)) {
            // use sequential nonce, already validated in `_validateParams()`
            _avoNonce++;
        } else {
            // use non-sequential nonce, already validated in `_verifySig()`
            nonSequentialNonces[nonSequentialNonce_] = 1;
        }

        // execute _callTargets via a low-level call to create a separate execution frame
        // this is used to revert all the actions if one action fails without reverting the whole transaction
        bytes memory calldata_ = abi.encodeCall(AvocadoMultisigProtected._callTargets, (params_.actions, params_.id));
        bytes memory result_;
        unchecked {
            if (gasleft() < reserveGas_ + 150) {
                // catch out of gas issues when available gas does not even cover reserveGas
                // -> immediately return with out of gas. + 150 to cover sload, sub etc.
                _resetTransientStorage();
                return (false, "AVO__OUT_OF_GAS");
            }
        }
        // using inline assembly for delegatecall to define custom gas amount that should stay here in caller
        assembly {
            success_ := delegatecall(
                // reserve some gas to make sure we can emit CastFailed event even for out of gas cases
                // and execute fee paying logic for `castAuthorized()`.
                // if gasleft() is less than the amount wanted to be sent along, sub would overflow and send all gas
                // that's why there is the explicit check a few lines up.
                sub(gas(), reserveGas_),
                // load _avoImpl from slot 0 and explicitly convert to address with bit mask
                and(sload(0), 0xffffffffffffffffffffffffffffffffffffffff),
                add(calldata_, 0x20),
                mload(calldata_),
                0,
                0
            )
            let size := returndatasize()

            result_ := mload(0x40)
            mstore(0x40, add(result_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(result_, size)
            returndatacopy(add(result_, 0x20), 0, size)
        }

        // @dev starting point for measuring reserve gas should be here right after actions execution.
        // on changes in code after execution (below here or below `_executeCast()` call in calling method),
        // measure the needed reserve gas via `gasleft()` anew and update `CAST_AUTHORIZED_RESERVE_GAS`
        // and `CAST_EVENTS_RESERVE_GAS` accordingly. use a method that forces maximum logic execution,
        // e.g. `castAuthorized()` with failing action.
        // gas measurement currently: ~1400 gas for logic in this method below
        if (!success_) {
            if (result_.length == 0) {
                if (gasleft() < reserveGas_ - 150) {
                    // catch out of gas errors where not the action ran out of gas but the logic around execution
                    // of the action itself. -150 to cover gas cost until here
                    revertReason_ = "AVO__OUT_OF_GAS";
                } else {
                    // @dev this case might be caused by edge-case out of gas errors that we were unable to catch,
                    // but could potentially also have other reasons
                    revertReason_ = "AVO__REASON_NOT_DEFINED";
                }
            } else {
                assembly {
                    result_ := add(result_, 0x04)
                }
                revertReason_ = abi.decode(result_, (string));
            }
        }

        // reset all transient variables to get the gas refund (4800)
        _resetTransientStorage();
    }

    function _handleActionFailure(uint256 actionMinGasLeft_, uint256 i, bytes memory result_) internal view {
        if (gasleft() < actionMinGasLeft_) {
            // action ran out of gas. can not add action index as that again might run out of gas. keep revert minimal
            revert("AVO__OUT_OF_GAS");
        }
        revert(string.concat(Strings.toString(i), _getRevertReasonFromReturnedData(result_)));
    }

    /// @dev executes `actions_` with respective target, calldata, operation etc.
    /// IMPORTANT: Validation of `id_` and `_transientAllowHash` is expected to happen in `executeOperation()` and `_callTargets()`.
    /// catches out of gas errors (as well as possible), reverting with `AVO__OUT_OF_GAS`.
    /// reverts with action index + error code in case of failure (e.g. "1_SOME_ERROR").
    function _executeActions(Action[] memory actions_, uint256 id_, bool isFlashloanCallback_) internal {
        // reset _transientAllowHash immediately to avert reentrancy etc. & get the gas refund (4800)
        _resetTransientStorage();

        uint256 storageSlot0Snapshot_; // avoImpl, nonce, initialized vars
        uint256 storageSlot1Snapshot_; // signers related variables
        // delegate call = ids 1 and 21
        bool isDelegateCallId_ = id_ == 1 || id_ == 21;
        if (isDelegateCallId_) {
            // store values before execution to make sure core storage vars are not modified by a delegatecall.
            // this ensures the smart wallet does not end up in a corrupted state.
            // for mappings etc. it is hard to protect against storage changes, so we must rely on the owner / signer
            // to know what is being triggered and the effects of a tx
            assembly {
                storageSlot0Snapshot_ := sload(0x0) // avoImpl, nonce & initialized vars
                storageSlot1Snapshot_ := sload(0x1) // signers related variables
            }
        }

        uint256 actionsLength_ = actions_.length;
        for (uint256 i; i < actionsLength_; ) {
            Action memory action_ = actions_[i];

            // execute action
            bool success_;
            bytes memory result_;
            uint256 actionMinGasLeft_;
            if (action_.operation == 0 && (id_ < 2 || id_ == 20 || id_ == 21)) {
                // call (operation = 0 & id = call(0 / 20) or mixed(1 / 21))
                unchecked {
                    // store amount of gas that stays with caller, according to EIP150 to detect out of gas errors
                    // -> as close as possible to actual call
                    actionMinGasLeft_ = gasleft() / 64;
                }

                // low-level call will return success true also if action target is not even a contract.
                // we do not explicitly check for this, default interaction is via UI which can check and handle this.
                // Also applies to delegatecall etc.
                (success_, result_) = action_.target.call{ value: action_.value }(action_.data);

                // handle action failure right after external call to better detect out of gas errors
                if (!success_) {
                    _handleActionFailure(actionMinGasLeft_, i, result_);
                }
            } else if (action_.operation == 1 && isDelegateCallId_) {
                // delegatecall (operation = 1 & id = mixed(1 / 21))
                unchecked {
                    // store amount of gas that stays with caller, according to EIP150 to detect out of gas errors
                    // -> as close as possible to actual call
                    actionMinGasLeft_ = gasleft() / 64;
                }

                (success_, result_) = action_.target.delegatecall(action_.data);

                // handle action failure right after external call to better detect out of gas errors
                if (!success_) {
                    _handleActionFailure(actionMinGasLeft_, i, result_);
                }

                // reset _transientAllowHash to make sure it can not be set up in any way for reentrancy
                _resetTransientStorage();

                // for delegatecall, make sure storage was not modified. After every action, to also defend reentrancy
                uint256 storageSlot0_;
                uint256 storageSlot1_;
                assembly {
                    storageSlot0_ := sload(0x0) // avoImpl, nonce & initialized vars
                    storageSlot1_ := sload(0x1) // signers related variables
                }

                if (!(storageSlot0_ == storageSlot0Snapshot_ && storageSlot1_ == storageSlot1Snapshot_)) {
                    revert(string.concat(Strings.toString(i), "_AVO__MODIFIED_STORAGE"));
                }
            } else if (action_.operation == 2 && (id_ == 20 || id_ == 21)) {
                // flashloan (operation = 2 & id = flashloan(20 / 21))
                if (isFlashloanCallback_) {
                    revert(string.concat(Strings.toString(i), "_AVO__NO_FLASHLOAN_IN_FLASHLOAN"));
                }
                // flashloan is always executed via .call, flashloan aggregator uses `msg.sender`, so .delegatecall
                // wouldn't send funds to this contract but rather to the original sender.

                bytes memory data_ = action_.data;
                assembly {
                    data_ := add(data_, 4) // Skip function selector (4 bytes)
                }
                // get actions data from calldata action_.data. Only supports InstaFlashAggregatorInterface
                (, , , data_, ) = abi.decode(data_, (address[], uint256[], uint256, bytes, bytes));

                // set allowHash to signal allowed entry into executeOperation()
                _transientAllowHash = bytes31(
                    keccak256(abi.encode(data_, block.timestamp, EXECUTE_OPERATION_SELECTOR))
                );
                // store id_ in transient storage slot
                _transientId = uint8(id_);

                unchecked {
                    // store amount of gas that stays with caller, according to EIP150 to detect out of gas errors
                    // -> as close as possible to actual call
                    actionMinGasLeft_ = gasleft() / 64;
                }

                // handle action failure right after external call to better detect out of gas errors
                (success_, result_) = action_.target.call{ value: action_.value }(action_.data);

                if (!success_) {
                    _handleActionFailure(actionMinGasLeft_, i, result_);
                }

                // reset _transientAllowHash to prevent reentrancy during actions execution
                _resetTransientStorage();
            } else {
                // either operation does not exist or the id was not set according to what the action wants to execute
                revert(string.concat(Strings.toString(i), "_AVO__INVALID_ID_OR_OPERATION"));
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev                   Validates input params, reverts on invalid values.
    /// @param actionsLength_  the length of the actions array to execute
    /// @param avoNonce_   the avoNonce from input CastParams
    /// @param validAfter_     timestamp after which the request is valid
    /// @param validUntil_     timestamp before which the request is valid
    function _validateParams(
        uint256 actionsLength_,
        int256 avoNonce_,
        uint256 validAfter_,
        uint256 validUntil_,
        uint256 value_
    ) internal view {
        // make sure actions are defined and nonce is valid:
        // must be -1 to use a non-sequential nonce or otherwise it must match the avoNonce
        if (!(actionsLength_ > 0 && (avoNonce_ == -1 || uint256(avoNonce_) == _avoNonce))) {
            revert AvocadoMultisig__InvalidParams();
        }

        // make sure request is within valid timeframe
        if ((validAfter_ > block.timestamp) || (validUntil_ > 0 && validUntil_ < block.timestamp)) {
            revert AvocadoMultisig__InvalidTiming();
        }

        // make sure msg.value matches value_ (if set)
        if (value_ > 0 && msg.value != value_) {
            revert AvocadoMultisig__InvalidParams();
        }
    }

    /// @dev pays the fee for `castAuthorized()` calls via the AvoRegistry (or fallback)
    /// @param gasUsedFrom_ `gasleft()` snapshot at gas measurement starting point
    /// @param maxFee_      maximum acceptable fee to be paid, revert if fee is bigger than this value
    function _payAuthorizedFee(uint256 gasUsedFrom_, uint256 maxFee_) internal {
        // @dev part below costs ~24k gas for if `feeAmount_` and `maxFee_` is set
        uint256 feeAmount_;
        address payable feeCollector_;
        {
            uint256 gasUsed_;
            unchecked {
                // gas can not underflow
                // gasUsed already includes everything at this point except for paying fee logic
                gasUsed_ = gasUsedFrom_ - gasleft();
            }

            // Using a low-level function call to prevent reverts (making sure the contract is truly non-custodial).
            // also limit gas, so that registry can not cause out of gas.
            (bool success_, bytes memory result_) = address(avoRegistry).staticcall{ gas: 15000 }(
                abi.encodeWithSignature("calcFee(uint256)", gasUsed_)
            );

            // checks to ensure decoding does not fail, breaking non-custodial feature
            uint256 addressValue;
            assembly {
                addressValue := mload(add(result_, 0x40))
            }
            if (success_ && result_.length > 63 && addressValue <= type(uint160).max) {
                // result bytes length < 64 or a too long address value would fail the abi.decode and cause revert
                (feeAmount_, feeCollector_) = abi.decode(result_, (uint256, address));
                if (feeAmount_ > AUTHORIZED_MAX_FEE) {
                    // make sure AvoRegistry fee is capped
                    feeAmount_ = AUTHORIZED_MAX_FEE;
                }
            } else {
                // registry calcFee failed. Use local backup minimum fee
                feeCollector_ = AUTHORIZED_FEE_COLLECTOR;
                feeAmount_ = AUTHORIZED_MIN_FEE;
            }
        }

        // pay fee, if any
        if (feeAmount_ > 0) {
            if (maxFee_ > 0 && feeAmount_ > maxFee_) {
                revert AvocadoMultisig__MaxFee(feeAmount_, maxFee_);
            }

            // sending fee based on OZ Address.sendValue, but modified to properly act based on actual error case
            // (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.8/contracts/utils/Address.sol#L60)
            if (address(this).balance < feeAmount_) {
                revert AvocadoMultisig__InsufficientBalance(feeAmount_);
            }

            // Setting gas to very low 1000 because 2_300 gas is added automatically for a .call with a value amount.
            // This should be enough for any normal transfer to an EOA or an Avocado Multisig.
            (bool success_, ) = feeCollector_.call{ value: feeAmount_, gas: 1000 }("");

            if (success_) {
                emit FeePaid(feeAmount_);
            } else {
                // do not revert, as an error on the feeCollector_ side should not be the "fault" of the Avo contract.
                // Letting this case pass ensures that the contract is truly non-custodial (not blockable by feeCollector)
                emit FeePayFailed(feeAmount_);
            }
        } else {
            emit FeePaid(feeAmount_);
        }
    }

    /// @notice                  builds the digest (hash) used to verify an EIP712 signature
    /// @param params_           Cast params such as id, avoNonce and actions to execute
    /// @param functionTypeHash_ whole function type hash, e.g. CAST_TYPE_HASH or CAST_AUTHORIZED_TYPE_HASH
    /// @param customStructHash_ struct hash added after CastParams hash, e.g. CastForwardParams or CastAuthorizedParams hash
    /// @return                  bytes32 digest e.g. for signature or non-sequential nonce
    function _buildSigDigest(
        CastParams memory params_,
        bytes32 functionTypeHash_,
        bytes32 customStructHash_
    ) internal view returns (bytes32) {
        bytes32[] memory keccakActions_;

        {
            // get keccak256s for actions
            uint256 actionsLength_ = params_.actions.length;
            keccakActions_ = new bytes32[](actionsLength_);
            for (uint256 i; i < actionsLength_; ) {
                keccakActions_[i] = keccak256(
                    abi.encode(
                        ACTION_TYPE_HASH,
                        params_.actions[i].target,
                        keccak256(params_.actions[i].data),
                        params_.actions[i].value,
                        params_.actions[i].operation
                    )
                );

                unchecked {
                    ++i;
                }
            }
        }

        return
            ECDSA.toTypedDataHash(
                // domain separator
                _domainSeparatorV4(),
                // structHash
                keccak256(
                    abi.encode(
                        functionTypeHash_,
                        // CastParams hash
                        keccak256(
                            abi.encode(
                                CAST_PARAMS_TYPE_HASH,
                                // actions
                                keccak256(abi.encodePacked(keccakActions_)),
                                params_.id,
                                params_.avoNonce,
                                params_.salt,
                                params_.source,
                                keccak256(params_.metadata)
                            )
                        ),
                        // CastForwardParams or CastAuthorizedParams hash
                        customStructHash_
                    )
                )
            );
    }

    /// @notice                  gets the digest (hash) used to verify an EIP712 signature for `forwardParams_`
    /// @param params_           Cast params such as id, avoNonce and actions to execute
    /// @param forwardParams_    Cast params related to validity of forwarding as instructed and signed
    /// @return                  bytes32 digest e.g. for signature or non-sequential nonce
    function _getSigDigest(
        CastParams memory params_,
        CastForwardParams memory forwardParams_
    ) internal view returns (bytes32) {
        return
            _buildSigDigest(
                params_,
                CAST_TYPE_HASH,
                // CastForwardParams hash
                keccak256(
                    abi.encode(
                        CAST_FORWARD_PARAMS_TYPE_HASH,
                        forwardParams_.gas,
                        forwardParams_.gasPrice,
                        forwardParams_.validAfter,
                        forwardParams_.validUntil,
                        forwardParams_.value
                    )
                )
            );
    }

    /// @notice                   gets the digest (hash) used to verify an EIP712 signature for `authorizedParams_`
    /// @param params_            Cast params such as id, avoNonce and actions to execute
    /// @param authorizedParams_  Cast params related to execution through owner such as maxFee
    /// @return                   bytes32 digest e.g. for signature or non-sequential nonce
    function _getSigDigestAuthorized(
        CastParams memory params_,
        CastAuthorizedParams memory authorizedParams_
    ) internal view returns (bytes32) {
        return
            _buildSigDigest(
                params_,
                CAST_AUTHORIZED_TYPE_HASH,
                // CastAuthorizedParams hash
                keccak256(
                    abi.encode(
                        CAST_AUTHORIZED_PARAMS_TYPE_HASH,
                        authorizedParams_.maxFee,
                        authorizedParams_.gasPrice,
                        authorizedParams_.validAfter,
                        authorizedParams_.validUntil
                    )
                )
            );
    }

    /// @notice Returns the domain separator for the chain with id `DEFAULT_CHAIN_ID`
    function _domainSeparatorV4() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TYPE_HASH,
                    DOMAIN_SEPARATOR_NAME_HASHED,
                    DOMAIN_SEPARATOR_VERSION_HASHED,
                    DEFAULT_CHAIN_ID,
                    address(this),
                    DOMAIN_SEPARATOR_SALT_HASHED
                )
            );
    }

    /// @dev Get the revert reason from the returnedData (supports Panic, Error & Custom Errors).
    /// Based on https://github.com/superfluid-finance/protocol-monorepo/blob/dev/packages/ethereum-contracts/contracts/libs/CallUtils.sol
    /// This is needed in order to provide some human-readable revert message from a call.
    /// @param returnedData_ revert data of the call
    /// @return reason_      revert reason
    function _getRevertReasonFromReturnedData(
        bytes memory returnedData_
    ) internal pure returns (string memory reason_) {
        if (returnedData_.length < 4) {
            // case 1: catch all
            return "_REASON_NOT_DEFINED";
        }

        bytes4 errorSelector_;
        assembly {
            errorSelector_ := mload(add(returnedData_, 0x20))
        }
        if (errorSelector_ == bytes4(0x4e487b71)) {
            // case 2: Panic(uint256), selector 0x4e487b71 (Defined since 0.8.0)
            // ref: https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require)

            // convert last byte to hex digits -> string to decode the panic code
            bytes memory result_ = new bytes(2);
            result_[0] = _toHexDigit(uint8(returnedData_[returnedData_.length - 1]) / 16);
            result_[1] = _toHexDigit(uint8(returnedData_[returnedData_.length - 1]) % 16);
            reason_ = string.concat("_TARGET_PANICKED: 0x", string(result_));
        } else if (errorSelector_ == bytes4(0x08c379a0)) {
            // case 3: Error(string), selector 0x08c379a0 (Defined at least since 0.7.0)
            // based on https://ethereum.stackexchange.com/a/83577
            assembly {
                returnedData_ := add(returnedData_, 0x04)
            }
            reason_ = string.concat("_", abi.decode(returnedData_, (string)));
        } else {
            // case 4: Custom errors (Defined since 0.8.0)

            // convert bytes4 selector to string, params are ignored...
            // based on https://ethereum.stackexchange.com/a/111876
            bytes memory result_ = new bytes(8);
            for (uint256 i; i < 4; ) {
                // use unchecked as i is < 4 and division. also errorSelector can not underflow
                unchecked {
                    result_[2 * i] = _toHexDigit(uint8(errorSelector_[i]) / 16);
                    result_[2 * i + 1] = _toHexDigit(uint8(errorSelector_[i]) % 16);
                    ++i;
                }
            }
            reason_ = string.concat("_CUSTOM_ERROR: 0x", string(result_));
        }

        {
            // truncate reason_ string to REVERT_REASON_MAX_LENGTH for reserveGas used to ensure Cast event is emitted
            if (bytes(reason_).length > REVERT_REASON_MAX_LENGTH) {
                bytes memory reasonBytes_ = bytes(reason_);
                uint256 maxLength_ = REVERT_REASON_MAX_LENGTH + 1; // cheaper than <= in each loop
                bytes memory truncatedRevertReason_ = new bytes(maxLength_);
                for (uint256 i; i < maxLength_; ) {
                    truncatedRevertReason_[i] = reasonBytes_[i];

                    unchecked {
                        ++i;
                    }
                }
                reason_ = string(truncatedRevertReason_);
            }
        }
    }

    /// @dev used to convert bytes4 selector to string
    function _toHexDigit(uint8 d) internal pure returns (bytes1) {
        // use unchecked as the operations with d can not over / underflow
        unchecked {
            if (d < 10) {
                return bytes1(uint8(bytes1("0")) + d);
            }
            if (d < 16) {
                return bytes1(uint8(bytes1("a")) + d - 10);
            }
        }
        revert AvocadoMultisig__ToHexDigit();
    }
}

