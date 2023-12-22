// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { ECDSA } from "./ECDSA.sol";
import { Address } from "./Address.sol";
import { Strings } from "./Strings.sol";
import { ERC721Holder } from "./ERC721Holder.sol";
import { IERC1271 } from "./IERC1271.sol";
import { ERC1155Holder } from "./ERC1155Holder.sol";

import { InstaFlashReceiverInterface } from "./InstaFlashReceiverInterface.sol";
import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";
import { Initializable } from "./Initializable.sol";
import { AvoCoreVariables } from "./AvoCoreVariables.sol";
import { AvoCoreEvents } from "./AvoCoreEvents.sol";
import { AvoCoreErrors } from "./AvoCoreErrors.sol";
import { AvoCoreStructs } from "./AvoCoreStructs.sol";

abstract contract AvoCore is
    AvoCoreErrors,
    AvoCoreVariables,
    AvoCoreEvents,
    AvoCoreStructs,
    Initializable,
    ERC721Holder,
    ERC1155Holder,
    InstaFlashReceiverInterface,
    IERC1271
{
    /// @dev ensures the method can only be called by the same contract itself.
    modifier onlySelf() {
        _requireSelfCalled();
        _;
    }

    /// @dev internal method for modifier logic to reduce bytecode size of contract.
    function _requireSelfCalled() internal view {
        if (msg.sender != address(this)) {
            revert AvoCore__Unauthorized();
        }
    }

    /// @dev sets the initial state of the contract for `owner_` as owner
    function _initializeOwner(address owner_) internal {
        // owner must be EOA
        if (Address.isContract(owner_) || owner_ == address(0)) {
            revert AvoCore__InvalidParams();
        }

        owner = owner_;
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
        // set status verified to 1 for call to _callTargets to avoid having to check signature etc. again
        _status = 1;

        // nonce must be used *always* if signature is valid
        if (nonSequentialNonce_ == bytes32(0)) {
            // use sequential nonce, already validated in `_validateParams()`
            avoSafeNonce++;
        } else {
            // use non-sequential nonce, already validated in `_verifySig()`
            nonSequentialNonces[nonSequentialNonce_] = 1;
        }

        // execute _callTargets via a low-level call to create a separate execution frame
        // this is used to revert all the actions if one action fails without reverting the whole transaction
        bytes memory calldata_ = abi.encodeCall(AvoCoreProtected._callTargets, (params_.actions, params_.id));
        bytes memory result_;
        // using inline assembly for delegatecall to define custom gas amount that should stay here in caller
        assembly {
            success_ := delegatecall(
                // reserve some gas to make sure we can emit CastFailed event even for out of gas cases
                // and execute fee paying logic for `castAuthorized()`
                sub(gas(), reserveGas_),
                sload(_avoImplementation.slot),
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

        // reset _status flag to 0 in all cases. cost 200 gas
        _status = 0;

        // @dev starting point for measuring reserve gas should be here right after actions execution.
        // on changes in code after execution (below here or below `_executeCast()` call in calling method),
        // measure the needed reserve gas via `gasleft()` anew and update `CAST_AUTHORIZED_RESERVE_GAS`
        // and `CAST_EVENTS_RESERVE_GAS` accordingly. use a method that forces maximum logic execution,
        // e.g. `castAuthorized()` with failing action in gas-usage-report.
        if (!success_) {
            if (result_.length == 0) {
                // @dev this case might be caused by edge-case out of gas errors that we were unable to catch,
                // but could potentially also have other reasons
                revertReason_ = "AVO__REASON_NOT_DEFINED";
            } else if (bytes4(result_) == bytes4(0x30e4191c)) {
                // 0x30e4191c = selector for custom error AvoCore__OutOfGas()
                revertReason_ = "AVO__OUT_OF_GAS";
            } else {
                assembly {
                    result_ := add(result_, 0x04)
                }
                revertReason_ = abi.decode(result_, (string));
            }
        }
    }

    /// @dev executes `actions_` with respective target, calldata, operation etc.
    /// IMPORTANT: Validation of `id_` and `_status` is expected to happen in `executeOperation()` and `_callTargets()`.
    /// catches out of gas errors (as well as possible), reverting with `AvoCore__OutOfGas()`.
    /// reverts with action index + error code in case of failure (e.g. "1_SOME_ERROR").
    function _executeActions(Action[] memory actions_, uint256 id_, bool isFlashloanCallback_) internal {
        // reset status immediately to avert reentrancy etc.
        _status = 0;

        uint256 storageSlot0Snapshot_;
        uint256 storageSlot1Snapshot_;
        uint256 storageSlot54Snapshot_;
        // delegate call = ids 1 and 21
        if (id_ == 1 || id_ == 21) {
            // store values before execution to make sure core storage vars are not modified by a delegatecall.
            // this ensures the smart wallet does not end up in a corrupted state.
            // for mappings etc. it is hard to protect against storage changes, so we must rely on the owner / signer
            // to know what is being triggered and the effects of a tx
            assembly {
                storageSlot0Snapshot_ := sload(0x0) // avoImpl, nonce, status
                storageSlot1Snapshot_ := sload(0x1) // owner, _initialized, _initializing
            }

            if (IS_MULTISIG) {
                assembly {
                    storageSlot54Snapshot_ := sload(0x36) // storage slot 54 related variables such as signers for Multisig
                }
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

                (success_, result_) = action_.target.call{ value: action_.value }(action_.data);
            } else if (action_.operation == 1 && storageSlot0Snapshot_ > 0) {
                // delegatecall (operation = 1 & id = mixed(1 / 21))
                unchecked {
                    // store amount of gas that stays with caller, according to EIP150 to detect out of gas errors
                    // -> as close as possible to actual call
                    actionMinGasLeft_ = gasleft() / 64;
                }

                // storageSlot0Snapshot_ is only set if id is set for a delegateCall
                (success_, result_) = action_.target.delegatecall(action_.data);
            } else if (action_.operation == 2 && (id_ == 20 || id_ == 21)) {
                // flashloan (operation = 2 & id = flashloan(20 / 21))
                if (isFlashloanCallback_) {
                    revert(string.concat(Strings.toString(i), "_AVO__NO_FLASHLOAN_IN_FLASHLOAN"));
                }
                // flashloan is always executed via .call, flashloan aggregator uses `msg.sender`, so .delegatecall
                // wouldn't send funds to this contract but rather to the original sender.

                // store `id_` temporarily as `_status` as flag to allow the flashloan callback (`executeOperation()`)
                _status = uint8(id_);

                unchecked {
                    // store amount of gas that stays with caller, according to EIP150 to detect out of gas errors
                    // -> as close as possible to actual call
                    actionMinGasLeft_ = gasleft() / 64;
                }

                (success_, result_) = action_.target.call{ value: action_.value }(action_.data);

                // reset _status flag to 0 in all cases. cost 200 gas
                _status = 0;
            } else {
                // either operation does not exist or the id was not set according to what the action wants to execute
                if (action_.operation > 2) {
                    revert(string.concat(Strings.toString(i), "_AVO__OPERATION_NOT_EXIST"));
                } else {
                    // enforce that id must be set according to operation
                    revert(string.concat(Strings.toString(i), "_AVO__ID_ACTION_MISMATCH"));
                }
            }

            if (!success_) {
                if (gasleft() < actionMinGasLeft_) {
                    // action ran out of gas, trigger revert with specific custom error
                    revert AvoCore__OutOfGas();
                }

                revert(string.concat(Strings.toString(i), _getRevertReasonFromReturnedData(result_)));
            }

            unchecked {
                ++i;
            }
        }

        // if actions include delegatecall (if snapshot is set), make sure storage was not modified
        if (storageSlot0Snapshot_ > 0) {
            uint256 storageSlot0_;
            uint256 storageSlot1_;
            assembly {
                storageSlot0_ := sload(0x0)
                storageSlot1_ := sload(0x1)
            }

            uint256 storageSlot54_;
            if (IS_MULTISIG) {
                assembly {
                    storageSlot54_ := sload(0x36) // storage slot 54 related variables such as signers for Multisig
                }
            }

            if (
                !(storageSlot0_ == storageSlot0Snapshot_ &&
                    storageSlot1_ == storageSlot1Snapshot_ &&
                    storageSlot54_ == storageSlot54Snapshot_)
            ) {
                revert("AVO__MODIFIED_STORAGE");
            }
        }
    }

    /// @dev                   Validates input params, reverts on invalid values.
    /// @param actionsLength_  the length of the actions array to execute
    /// @param avoSafeNonce_   the avoSafeNonce from input CastParams
    /// @param validAfter_     timestamp after which the request is valid
    /// @param validUntil_     timestamp before which the request is valid
    function _validateParams(
        uint256 actionsLength_,
        int256 avoSafeNonce_,
        uint256 validAfter_,
        uint256 validUntil_
    ) internal view {
        // make sure actions are defined and nonce is valid:
        // must be -1 to use a non-sequential nonce or otherwise it must match the avoSafeNonce
        if (!(actionsLength_ > 0 && (avoSafeNonce_ == -1 || uint256(avoSafeNonce_) == avoSafeNonce))) {
            revert AvoCore__InvalidParams();
        }

        // make sure request is within valid timeframe
        if ((validAfter_ > 0 && validAfter_ > block.timestamp) || (validUntil_ > 0 && validUntil_ < block.timestamp)) {
            revert AvoCore__InvalidTiming();
        }
    }

    /// @dev pays the fee for `castAuthorized()` calls via the AvoVersionsRegistry (or fallback)
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

            // Using a low-level function call to prevent reverts (making sure the contract is truly non-custodial)
            (bool success_, bytes memory result_) = address(avoVersionsRegistry).staticcall(
                abi.encodeWithSignature("calcFee(uint256)", gasUsed_)
            );

            if (success_) {
                (feeAmount_, feeCollector_) = abi.decode(result_, (uint256, address));
                if (feeAmount_ > AUTHORIZED_MAX_FEE) {
                    // make sure AvoVersionsRegistry fee is capped
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
                revert AvoCore__MaxFee(feeAmount_, maxFee_);
            }

            // sending fee based on OZ Address.sendValue, but modified to properly act based on actual error case
            // (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.8/contracts/utils/Address.sol#L60)
            if (address(this).balance < feeAmount_) {
                revert AvoCore__InsufficientBalance(feeAmount_);
            }

            // send along enough gas (22_000) to make any gas griefing attacks impossible. This should be enough for any
            // normal transfer to an EOA or an Avocado Multisig
            (bool success_, ) = feeCollector_.call{ value: feeAmount_, gas: 22_000 }("");

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

    /// @notice                  gets the digest (hash) used to verify an EIP712 signature
    /// @param params_           Cast params such as id, avoSafeNonce and actions to execute
    /// @param functionTypeHash_ whole function type hash, e.g. CAST_TYPE_HASH or CAST_AUTHORIZED_TYPE_HASH
    /// @param customStructHash_ struct hash added after CastParams hash, e.g. CastForwardParams or CastAuthorizedParams hash
    /// @return                  bytes32 digest e.g. for signature or non-sequential nonce
    function _getSigDigest(
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
                                params_.avoSafeNonce,
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
                    keccak256(abi.encodePacked(block.chainid)) // in salt: ensure tx replay is not possible
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
        } else {
            bytes4 errorSelector;
            assembly {
                errorSelector := mload(add(returnedData_, 0x20))
            }
            if (errorSelector == bytes4(0x4e487b71) /* `seth sig "Panic(uint256)"` */) {
                // case 2: Panic(uint256) (Defined since 0.8.0)
                // ref: https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require)
                reason_ = "_TARGET_PANICKED: 0x__";
                uint256 errorCode;
                assembly {
                    errorCode := mload(add(returnedData_, 0x24))
                    let reasonWord := mload(add(reason_, 0x20))
                    // [0..9] is converted to ['0'..'9']
                    // [0xa..0xf] is not correctly converted to ['a'..'f']
                    // but since panic code doesn't have those cases, we will ignore them for now!
                    let e1 := add(and(errorCode, 0xf), 0x30)
                    let e2 := shl(8, add(shr(4, and(errorCode, 0xf0)), 0x30))
                    reasonWord := or(
                        and(reasonWord, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000),
                        or(e2, e1)
                    )
                    mstore(add(reason_, 0x20), reasonWord)
                }
            } else {
                if (returnedData_.length > 68) {
                    // case 3: Error(string) (Defined at least since 0.7.0)
                    assembly {
                        returnedData_ := add(returnedData_, 0x04)
                    }
                    reason_ = string.concat("_", abi.decode(returnedData_, (string)));
                } else {
                    // case 4: Custom errors (Defined since 0.8.0)

                    // convert bytes4 selector to string
                    // based on https://ethereum.stackexchange.com/a/111876
                    bytes memory result = new bytes(10);
                    result[0] = bytes1("0");
                    result[1] = bytes1("x");
                    for (uint256 i; i < 4; ) {
                        result[2 * i + 2] = _toHexDigit(uint8(errorSelector[i]) / 16);
                        result[2 * i + 3] = _toHexDigit(uint8(errorSelector[i]) % 16);

                        unchecked {
                            ++i;
                        }
                    }

                    reason_ = string.concat("_CUSTOM_ERROR:", string(result));
                }
            }
        }
    }

    /// @dev used to convert bytes4 selector to string
    function _toHexDigit(uint8 d) internal pure returns (bytes1) {
        if (0 <= d && d <= 9) {
            return bytes1(uint8(bytes1("0")) + d);
        } else if (10 <= uint8(d) && uint8(d) <= 15) {
            return bytes1(uint8(bytes1("a")) + d - 10);
        }
        revert();
    }
}

abstract contract AvoCoreEIP1271 is AvoCore {
    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) external view virtual returns (bytes4 magicValue);

    /// @notice Marks a bytes32 `message_` (signature digest) as signed, making it verifiable by EIP-1271 `isValidSignature()`.
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param message_ data hash to be allow-listed as signed
    function signMessage(bytes32 message_) external onlySelf {
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

/// @dev Simple contract to upgrade the implementation address stored at storage slot 0x0.
///      Mostly based on OpenZeppelin ERC1967Upgrade contract, adapted with onlySelf etc.
///      IMPORTANT: For any new implementation, the upgrade method MUST be in the implementation itself,
///      otherwise it can not be upgraded anymore!
abstract contract AvoCoreSelfUpgradeable is AvoCore {
    /// @notice upgrade the contract to a new implementation address.
    ///         - Must be a valid version at the AvoVersionsRegistry.
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param avoImplementation_   New contract address
    function upgradeTo(address avoImplementation_) public virtual;

    /// @notice upgrade the contract to a new implementation address and call a function afterwards.
    ///         - Must be a valid version at the AvoVersionsRegistry.
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param avoImplementation_   New contract address
    /// @param data_                callData for function call on avoImplementation_ after upgrading
    /// @param forceCall_           optional flag to force send call even if callData (data_) is empty
    function upgradeToAndCall(
        address avoImplementation_,
        bytes calldata data_,
        bool forceCall_
    ) external payable virtual onlySelf {
        upgradeTo(avoImplementation_);
        if (data_.length > 0 || forceCall_) {
            Address.functionDelegateCall(avoImplementation_, data_);
        }
    }
}

abstract contract AvoCoreProtected is AvoCore {
    /***********************************|
    |             ONLY SELF             |
    |__________________________________*/

    /// @notice occupies the sequential `avoSafeNonces_` in storage. This can be used to cancel / invalidate
    ///         a previously signed request(s) because the nonce will be "used" up.
    ///         - Can only be self-called (authorization same as for `cast` methods).
    /// @param  avoSafeNonces_ sequential ascending ordered nonces to be occupied in storage.
    ///         E.g. if current AvoSafeNonce is 77 and txs are queued with avoSafeNonces 77, 78 and 79,
    ///         then you would submit [78, 79] here because 77 will be occupied by the tx executing
    ///         `occupyAvoSafeNonces()` as an action itself. If executing via non-sequential nonces, you would
    ///         submit [77, 78, 79].
    ///         - Maximum array length is 5.
    ///         - gap from the current avoSafeNonce will revert (e.g. [79, 80] if current one is 77)
    function occupyAvoSafeNonces(uint88[] calldata avoSafeNonces_) external onlySelf {
        uint256 avoSafeNoncesLength_ = avoSafeNonces_.length;
        if (avoSafeNoncesLength_ == 0) {
            // in case to cancel just one nonce via normal sequential nonce execution itself
            return;
        }

        if (avoSafeNoncesLength_ > 5) {
            revert AvoCore__InvalidParams();
        }

        uint256 nextAvoSafeNonce_ = avoSafeNonce;

        for (uint256 i; i < avoSafeNoncesLength_; ) {
            if (avoSafeNonces_[i] == nextAvoSafeNonce_) {
                // nonce to occupy is valid -> must match the current avoSafeNonce
                emit AvoSafeNonceOccupied(nextAvoSafeNonce_);
                nextAvoSafeNonce_++;
            } else if (avoSafeNonces_[i] > nextAvoSafeNonce_) {
                // input nonce is not smaller or equal current nonce -> invalid sorted ascending input params
                revert AvoCore__InvalidParams();
            }
            // else while nonce to occupy is < current nonce, skip ahead

            unchecked {
                ++i;
            }
        }

        avoSafeNonce = uint88(nextAvoSafeNonce_);
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
        uint256 status_ = _status;

        // @dev using the valid case inverted via one ! instead of invalid case with 3 ! to optimize gas usage
        if (!((status_ == 20 || status_ == 21) && initiator_ == address(this))) {
            revert AvoCore__Unauthorized();
        }

        _executeActions(
            // decode actions to be executed after getting the flashloan
            abi.decode(data_, (Action[])),
            // _status is set to `CastParams.id` pre-flashloan trigger in `_executeActions()`
            status_,
            true
        );

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
        // status must be verified or 0x000000000000000000000000000000000000dEaD used for backend gas estimations
        if (!(_status == 1 || tx.origin == 0x000000000000000000000000000000000000dEaD)) {
            revert AvoCore__Unauthorized();
        }

        _executeActions(actions_, id_, false);
    }
}

