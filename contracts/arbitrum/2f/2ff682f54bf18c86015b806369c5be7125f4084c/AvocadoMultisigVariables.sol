// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { SSTORE2 } from "./SSTORE2.sol";

import { IAvoRegistry } from "./IAvoRegistry.sol";
import { IAvoSignersList } from "./IAvoSignersList.sol";
import { IAvoConfigV1 } from "./IAvoConfigV1.sol";
import { IAvocado } from "./Avocado.sol";
import { AvocadoMultisigErrors } from "./AvocadoMultisigErrors.sol";
import { AvocadoMultisigEvents } from "./AvocadoMultisigEvents.sol";

abstract contract AvocadoMultisigConstants is AvocadoMultisigErrors {
    /************************************|
    |               CONSTANTS            |
    |___________________________________*/

    /// @notice overwrite chain id for EIP712 is always set to 63400 for the Avocado RPC / network
    uint256 public constant DEFAULT_CHAIN_ID = 63400;

    // constants for EIP712 values
    string public constant DOMAIN_SEPARATOR_NAME = "Avocado-Multisig";
    string public constant DOMAIN_SEPARATOR_VERSION = "1.0.1";
    // hashed EIP712 values
    bytes32 internal constant DOMAIN_SEPARATOR_NAME_HASHED = keccak256(bytes(DOMAIN_SEPARATOR_NAME));
    bytes32 internal constant DOMAIN_SEPARATOR_VERSION_HASHED = keccak256(bytes(DOMAIN_SEPARATOR_VERSION));

    /// @notice _TYPE_HASH is copied from OpenZeppelin EIP712 but with added salt as last param (we use it for `block.chainid`)
    bytes32 public constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    /// @notice EIP712 typehash for `cast()` calls, including structs
    bytes32 public constant CAST_TYPE_HASH =
        keccak256(
            "Cast(CastParams params,CastForwardParams forwardParams)Action(address target,bytes data,uint256 value,uint256 operation)CastForwardParams(uint256 gas,uint256 gasPrice,uint256 validAfter,uint256 validUntil,uint256 value)CastParams(Action[] actions,uint256 id,int256 avoNonce,bytes32 salt,address source,bytes metadata)"
        );

    /// @notice EIP712 typehash for Action struct
    bytes32 public constant ACTION_TYPE_HASH =
        keccak256("Action(address target,bytes data,uint256 value,uint256 operation)");

    /// @notice EIP712 typehash for CastParams struct
    bytes32 public constant CAST_PARAMS_TYPE_HASH =
        keccak256(
            "CastParams(Action[] actions,uint256 id,int256 avoNonce,bytes32 salt,address source,bytes metadata)Action(address target,bytes data,uint256 value,uint256 operation)"
        );
    /// @notice EIP712 typehash for CastForwardParams struct
    bytes32 public constant CAST_FORWARD_PARAMS_TYPE_HASH =
        keccak256(
            "CastForwardParams(uint256 gas,uint256 gasPrice,uint256 validAfter,uint256 validUntil,uint256 value)"
        );

    /// @notice EIP712 typehash for `castAuthorized()` calls, including structs
    bytes32 public constant CAST_AUTHORIZED_TYPE_HASH =
        keccak256(
            "CastAuthorized(CastParams params,CastAuthorizedParams authorizedParams)Action(address target,bytes data,uint256 value,uint256 operation)CastAuthorizedParams(uint256 maxFee,uint256 gasPrice,uint256 validAfter,uint256 validUntil)CastParams(Action[] actions,uint256 id,int256 avoNonce,bytes32 salt,address source,bytes metadata)"
        );

    /// @notice EIP712 typehash for CastAuthorizedParams struct
    bytes32 public constant CAST_AUTHORIZED_PARAMS_TYPE_HASH =
        keccak256("CastAuthorizedParams(uint256 maxFee,uint256 gasPrice,uint256 validAfter,uint256 validUntil)");

    /// @notice EIP712 typehash for signed hashes used for EIP1271 (`isValidSignature()`)
    bytes32 public constant EIP1271_TYPE_HASH = keccak256("AvocadoHash(bytes32 hash)");

    /// @notice defines the max signers count for the Multisig. This is chosen deliberately very high, as there shouldn't
    /// really be a limit on signers count in practice. It is extremely unlikely that anyone runs into this very high
    /// limit but it helps to implement test coverage within this given limit
    uint256 public constant MAX_SIGNERS_COUNT = 90;

    /// @dev "magic value" according to EIP1271 https://eips.ethereum.org/EIPS/eip-1271#specification
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    /// @dev constants for _transientAllowHash functionality: function selectors
    bytes4 internal constant _CALL_TARGETS_SELECTOR = bytes4(keccak256(bytes("_callTargets()")));
    bytes4 internal constant EXECUTE_OPERATION_SELECTOR = bytes4(keccak256(bytes("executeOpeartion()")));

    /// @dev amount of gas to keep in castAuthorized caller method as reserve for emitting event + paying fee.
    /// the dynamic part is covered with PER_SIGNER_RESERVE_GAS.
    /// use 45_000 as reserve gas for `castAuthorized()`. Usually it will cost less but 45_000 is the maximum amount
    /// with buffer (~32_000 + 1_400 base) pay fee logic etc. could cost on maximum logic execution.
    uint256 internal constant CAST_AUTHORIZED_RESERVE_GAS = 45_000;
    /// @dev amount of gas to keep in cast caller method as reserve for emitting CastFailed / CastExecuted event.
    /// ~7500 gas + ~1400 gas + buffer. the dynamic part is covered with PER_SIGNER_RESERVE_GAS.
    uint256 internal constant CAST_EVENTS_RESERVE_GAS = 10_000;

    /// @dev emitting one byte in an event costs 8 byte see https://github.com/wolflo/evm-opcodes/blob/main/gas.md#a8-log-operations
    uint256 internal constant EMIT_EVENT_COST_PER_BYTE = 8;

    /// @dev maximum length of revert reason, longer will be truncated. necessary to reserve enugh gas for event emit
    uint256 internal constant REVERT_REASON_MAX_LENGTH = 250;

    /// @dev each additional signer costs ~358 gas to emit in the CastFailed / CastExecuted event. this amount must be
    /// factored in dynamically depending on the number of signers (PER_SIGNER_RESERVE_GAS * number of signers)
    uint256 internal constant PER_SIGNER_RESERVE_GAS = 370;

    /************************************|
    |             IMMUTABLES             |
    |___________________________________*/
    // hashed EIP712 value to reduce gas usage
    bytes32 internal immutable DOMAIN_SEPARATOR_SALT_HASHED = keccak256(abi.encodePacked(block.chainid));

    /// @notice  registry holding the valid versions (addresses) for Avocado smart wallet implementation contracts
    ///          The registry is used to verify a valid version before upgrading & to pay fees for `castAuthorized()`
    IAvoRegistry public immutable avoRegistry;

    /// @notice address of the AvoForwarder (proxy) that is allowed to forward tx with valid signatures
    address public immutable avoForwarder;

    /// @notice Signers <> Avocados mapping list contract for easy on-chain tracking
    IAvoSignersList public immutable avoSignersList;

    // backup fee logic
    /// @dev minimum fee for fee charged via `castAuthorized()` to charge if `AvoRegistry.calcFee()` would fail
    uint256 public immutable AUTHORIZED_MIN_FEE;
    /// @dev global maximum for fee charged via `castAuthorized()`. If AvoRegistry returns a fee higher than this,
    /// then MAX_AUTHORIZED_FEE is charged as fee instead (capping)
    uint256 public immutable AUTHORIZED_MAX_FEE;
    /// @dev address that the fee charged via `castAuthorized()` is sent to in the fallback case
    address payable public immutable AUTHORIZED_FEE_COLLECTOR;

    /***********************************|
    |            CONSTRUCTOR            |
    |__________________________________*/

    constructor(
        IAvoRegistry avoRegistry_,
        address avoForwarder_,
        IAvoSignersList avoSignersList_,
        IAvoConfigV1 avoConfigV1_
    ) {
        if (
            address(avoRegistry_) == address(0) ||
            avoForwarder_ == address(0) ||
            address(avoSignersList_) == address(0) ||
            address(avoConfigV1_) == address(0)
        ) {
            revert AvocadoMultisig__InvalidParams();
        }

        avoRegistry = avoRegistry_;
        avoForwarder = avoForwarder_;
        avoSignersList = avoSignersList_;

        // get values from AvoConfigV1 contract
        IAvoConfigV1.AvocadoMultisigConfig memory avoConfig_ = avoConfigV1_.avocadoMultisigConfig();

        // min & max fee settings, fee collector address are required
        if (
            avoConfig_.authorizedMinFee == 0 ||
            avoConfig_.authorizedMaxFee == 0 ||
            avoConfig_.authorizedFeeCollector == address(0) ||
            avoConfig_.authorizedMinFee > avoConfig_.authorizedMaxFee
        ) {
            revert AvocadoMultisig__InvalidParams();
        }

        AUTHORIZED_MIN_FEE = avoConfig_.authorizedMinFee;
        AUTHORIZED_MAX_FEE = avoConfig_.authorizedMaxFee;
        AUTHORIZED_FEE_COLLECTOR = payable(avoConfig_.authorizedFeeCollector);
    }
}

abstract contract AvocadoMultisigVariablesSlot0 {
    /// @notice address of the smart wallet logic / implementation contract.
    //  @dev    IMPORTANT: SAME STORAGE SLOT AS FOR PROXY. DO NOT MOVE THIS VARIABLE.
    //         _avoImpl MUST ALWAYS be the first declared variable here in the logic contract and in the proxy!
    //         When upgrading, the storage at memory address 0x0 is upgraded (first slot).
    //         Note immutable and constants do not take up storage slots so they can come before.
    address internal _avoImpl;

    /// @dev nonce that is incremented for every `cast` / `castAuthorized` transaction (unless it uses a non-sequential nonce)
    uint80 internal _avoNonce;

    /// @dev AvocadoMultisigInitializable.sol variables (modified from OpenZeppelin), see ./lib folder
    /// @dev Indicates that the contract has been initialized.
    uint8 internal _initialized;
    /// @dev Indicates that the contract is in the process of being initialized.
    bool internal _initializing;
}

abstract contract AvocadoMultisigVariablesSlot1 is AvocadoMultisigConstants, AvocadoMultisigEvents {
    /// @dev signers are stored with SSTORE2 to save gas, especially for storage checks at delegateCalls.
    /// getter and setter is implemented below
    address private _signersPointer;

    /// @notice signers count required to reach quorom and be able to execute actions
    uint8 private _requiredSigners;

    /// @notice number of signers currently listed as allowed signers
    //
    // @dev should be updated directly via `_setSigners()`
    uint8 private _signersCount;

    // 10 bytes empty

    /***********************************|
    |      SIGNERS GETTER / SETTER      |
    |__________________________________*/

    /// @dev writes `signers_` to storage with SSTORE2 and updates `signersCount`. uses `requiredSigners_` for sanity checks
    function _setSigners(address[] memory signers_, uint8 requiredSigners_) internal {
        uint256 signersCount_ = signers_.length;

        if (signersCount_ > MAX_SIGNERS_COUNT || signersCount_ == 0) {
            revert AvocadoMultisig__InvalidParams();
        }

        if (signersCount_ == 1) {
            // if signersCount is 1, owner must be the only signer (checked in `removeSigners`)
            // can reset to empty "uninitialized" signer vars state, making subsequent interactions cheaper
            // and even giving a gas refund for clearing out the slot 1
            if (requiredSigners_ != 1) {
                revert AvocadoMultisig__InvalidParams();
            }
            if (_requiredSigners > 1) {
                emit RequiredSignersSet(1);
            }

            assembly {
                sstore(1, 0) // Reset slot 1 (signers related vars) to 0
            }
        } else {
            _signersCount = uint8(signersCount_);

            _signersPointer = SSTORE2.write(abi.encode(signers_));

            // required signers vs signersCount is checked in _setRequiredSigners
            _setRequiredSigners(requiredSigners_);
        }
    }

    /// @dev reads signers from storage with SSTORE2
    function _getSigners() internal view returns (address[] memory signers_) {
        address pointer_ = _signersPointer;
        if (pointer_ == address(0)) {
            // signers not set yet -> only owner is signer currently.
            signers_ = new address[](1);
            signers_[0] = IAvocado(address(this))._owner();
            return signers_;
        }

        return abi.decode(SSTORE2.read(pointer_), (address[]));
    }

    /// @dev sets number of required signers to `requiredSigners_` and emits event RequiredSignersSet, if valid
    function _setRequiredSigners(uint8 requiredSigners_) internal {
        // check if number of actual signers is > `requiredSigners_` because otherwise
        // the multisig would end up in a broken state where no execution is possible anymore
        if (requiredSigners_ == 0 || requiredSigners_ > _getSignersCount()) {
            revert AvocadoMultisig__InvalidParams();
        }

        if (_requiredSigners != requiredSigners_) {
            _requiredSigners = requiredSigners_;

            emit RequiredSignersSet(requiredSigners_);
        }
    }

    /// @dev reads required signers (and returns 1 if it is not set)
    function _getRequiredSigners() internal view returns (uint8 requiredSigners_) {
        requiredSigners_ = _requiredSigners;
        if (requiredSigners_ == 0) {
            requiredSigners_ = 1;
        }
    }

    /// @dev reads signers count (and returns 1 if it is not set)
    function _getSignersCount() internal view returns (uint8 signersCount_) {
        signersCount_ = _signersCount;
        if (signersCount_ == 0) {
            signersCount_ = 1;
        }
    }
}

abstract contract AvocadoMultisigVariablesSlot2 {
    /// @dev allow-listed signed messages, e.g. for Permit2 Uniswap interaction
    /// mappings are not in sequential storage slot, thus not influenced by previous storage variables
    /// (but consider the slot number in calculating the hash of the key to store).
    mapping(bytes32 => uint256) internal _signedMessages;
}

abstract contract AvocadoMultisigVariablesSlot3 {
    /// @notice used non-sequential nonces (which can not be used again)
    mapping(bytes32 => uint256) public nonSequentialNonces;
}

abstract contract AvocadoMultisigSlotGaps {
    // slots 4 to 53

    // create some storage slot gaps for future expansion before the transient storage slot
    uint256[50] private __gaps;
}

abstract contract AvocadoMultisigTransient {
    // slot 54

    /// @dev transient allow hash used to signal allowing certain entry into methods such as _callTargets etc.
    bytes31 internal _transientAllowHash;
    /// @dev transient id used for passing id to flashloan callback
    uint8 internal _transientId;
}

/// @notice Defines storage variables for AvocadoMultisig
abstract contract AvocadoMultisigVariables is
    AvocadoMultisigConstants,
    AvocadoMultisigVariablesSlot0,
    AvocadoMultisigVariablesSlot1,
    AvocadoMultisigVariablesSlot2,
    AvocadoMultisigVariablesSlot3,
    AvocadoMultisigSlotGaps,
    AvocadoMultisigTransient
{
    constructor(
        IAvoRegistry avoRegistry_,
        address avoForwarder_,
        IAvoSignersList avoSignersList_,
        IAvoConfigV1 avoConfigV1_
    ) AvocadoMultisigConstants(avoRegistry_, avoForwarder_, avoSignersList_, avoConfigV1_) {}

    /// @dev resets transient storage to default value (1). 1 is better than 0 for optimizing gas refunds
    function _resetTransientStorage() internal {
        assembly {
            sstore(54, 1) // Store 1 in the transient storage 54
        }
    }
}

