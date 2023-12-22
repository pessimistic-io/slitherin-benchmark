// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { AvoCoreErrors } from "./AvoCoreErrors.sol";
import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";
import { IAvoAuthoritiesList } from "./IAvoAuthoritiesList.sol";

// --------------------------- DEVELOPER NOTES -----------------------------------------
// @dev IMPORTANT: Contracts using AvoCore must inherit this contract and define the immutables
// -------------------------------------------------------------------------------------
abstract contract AvoCoreConstantsOverride is AvoCoreErrors {
    // @dev: MUST SET DOMAIN_SEPARATOR_NAME & DOMAIN_SEPARATOR_VERSION IN CONTRACTS USING AvoCore.
    // Solidity offers no good way to create this inheritance or forcing implementation without increasing gas cost:
    // strings are not supported as immutable.
    // string public constant DOMAIN_SEPARATOR_NAME = "Avocado-Safe";
    // string public constant DOMAIN_SEPARATOR_VERSION = "3.0.0";

    // hashed EIP712 values
    bytes32 internal immutable DOMAIN_SEPARATOR_NAME_HASHED;
    bytes32 internal immutable DOMAIN_SEPARATOR_VERSION_HASHED;

    /// @dev amount of gas to keep in castAuthorized caller method as reserve for emitting event + paying fee
    uint256 internal immutable CAST_AUTHORIZED_RESERVE_GAS;
    /// @dev amount of gas to keep in cast caller method as reserve for emitting CastFailed / CastExecuted event
    uint256 internal immutable CAST_EVENTS_RESERVE_GAS;

    /// @dev flag for internal use to detect if current AvoCore is multisig logic
    bool internal immutable IS_MULTISIG;

    /// @dev minimum fee for fee charged via `castAuthorized()` to charge if `AvoVersionsRegistry.calcFee()` would fail
    uint256 public immutable AUTHORIZED_MIN_FEE;
    /// @dev global maximum for fee charged via `castAuthorized()`. If AvoVersionsRegistry returns a fee higher than this,
    /// then MAX_AUTHORIZED_FEE is charged as fee instead (capping)
    uint256 public immutable AUTHORIZED_MAX_FEE;
    /// @dev address that the fee charged via `castAuthorized()` is sent to in the fallback case
    address payable public immutable AUTHORIZED_FEE_COLLECTOR;

    constructor(
        string memory domainSeparatorName_,
        string memory domainSeparatorVersion_,
        uint256 castAuthorizedReserveGas_,
        uint256 castEventsReserveGas_,
        uint256 authorizedMinFee_,
        uint256 authorizedMaxFee_,
        address authorizedFeeCollector_,
        bool isMultisig
    ) {
        DOMAIN_SEPARATOR_NAME_HASHED = keccak256(bytes(domainSeparatorName_));
        DOMAIN_SEPARATOR_VERSION_HASHED = keccak256(bytes(domainSeparatorVersion_));

        CAST_AUTHORIZED_RESERVE_GAS = castAuthorizedReserveGas_;
        CAST_EVENTS_RESERVE_GAS = castEventsReserveGas_;

        // min & max fee settings, fee collector adress are required
        if (
            authorizedMinFee_ == 0 ||
            authorizedMaxFee_ == 0 ||
            authorizedFeeCollector_ == address(0) ||
            authorizedMinFee_ > authorizedMaxFee_
        ) {
            revert AvoCore__InvalidParams();
        }

        AUTHORIZED_MIN_FEE = authorizedMinFee_;
        AUTHORIZED_MAX_FEE = authorizedMaxFee_;
        AUTHORIZED_FEE_COLLECTOR = payable(authorizedFeeCollector_);

        IS_MULTISIG = isMultisig;
    }
}

abstract contract AvoCoreConstants is AvoCoreErrors {
    /***********************************|
    |              CONSTANTS            |
    |__________________________________*/

    /// @notice overwrite chain id for EIP712 is always set to 63400 for the Avocado RPC / network
    uint256 public constant DEFAULT_CHAIN_ID = 63400;

    /// @notice _TYPE_HASH is copied from OpenZeppelin EIP712 but with added salt as last param (we use it for `block.chainid`)
    bytes32 public constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    /// @notice EIP712 typehash for `cast()` calls, including structs
    bytes32 public constant CAST_TYPE_HASH =
        keccak256(
            "Cast(CastParams params,CastForwardParams forwardParams)Action(address target,bytes data,uint256 value,uint256 operation)CastForwardParams(uint256 gas,uint256 gasPrice,uint256 validAfter,uint256 validUntil)CastParams(Action[] actions,uint256 id,int256 avoSafeNonce,bytes32 salt,address source,bytes metadata)"
        );

    /// @notice EIP712 typehash for Action struct
    bytes32 public constant ACTION_TYPE_HASH =
        keccak256("Action(address target,bytes data,uint256 value,uint256 operation)");

    /// @notice EIP712 typehash for CastParams struct
    bytes32 public constant CAST_PARAMS_TYPE_HASH =
        keccak256(
            "CastParams(Action[] actions,uint256 id,int256 avoSafeNonce,bytes32 salt,address source,bytes metadata)Action(address target,bytes data,uint256 value,uint256 operation)"
        );
    /// @notice EIP712 typehash for CastForwardParams struct
    bytes32 public constant CAST_FORWARD_PARAMS_TYPE_HASH =
        keccak256("CastForwardParams(uint256 gas,uint256 gasPrice,uint256 validAfter,uint256 validUntil)");

    /// @dev "magic value" according to EIP1271 https://eips.ethereum.org/EIPS/eip-1271#specification
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice EIP712 typehash for `castAuthorized()` calls, including structs
    bytes32 public constant CAST_AUTHORIZED_TYPE_HASH =
        keccak256(
            "CastAuthorized(CastParams params,CastAuthorizedParams authorizedParams)Action(address target,bytes data,uint256 value,uint256 operation)CastAuthorizedParams(uint256 maxFee,uint256 gasPrice,uint256 validAfter,uint256 validUntil)CastParams(Action[] actions,uint256 id,int256 avoSafeNonce,bytes32 salt,address source,bytes metadata)"
        );

    /// @notice EIP712 typehash for CastAuthorizedParams struct
    bytes32 public constant CAST_AUTHORIZED_PARAMS_TYPE_HASH =
        keccak256("CastAuthorizedParams(uint256 maxFee,uint256 gasPrice,uint256 validAfter,uint256 validUntil)");

    /***********************************|
    |             IMMUTABLES            |
    |__________________________________*/

    /// @notice  registry holding the valid versions (addresses) for Avocado smart wallet implementation contracts
    ///          The registry is used to verify a valid version before upgrading & to pay fees for `castAuthorized()`
    IAvoVersionsRegistry public immutable avoVersionsRegistry;

    /// @notice address of the AvoForwarder (proxy) that is allowed to forward tx with valid signatures
    address public immutable avoForwarder;

    /***********************************|
    |            CONSTRUCTOR            |
    |__________________________________*/

    constructor(IAvoVersionsRegistry avoVersionsRegistry_, address avoForwarder_) {
        if (address(avoVersionsRegistry_) == address(0)) {
            revert AvoCore__InvalidParams();
        }
        avoVersionsRegistry = avoVersionsRegistry_;

        avoVersionsRegistry.requireValidAvoForwarderVersion(avoForwarder_);
        avoForwarder = avoForwarder_;
    }
}

abstract contract AvoCoreVariablesSlot0 {
    /// @notice address of the smart wallet logic / implementation contract.
    //  @dev    IMPORTANT: SAME STORAGE SLOT AS FOR PROXY. DO NOT MOVE THIS VARIABLE.
    //         _avoImplementation MUST ALWAYS be the first declared variable here in the logic contract and in the proxy!
    //         When upgrading, the storage at memory address 0x0 is upgraded (first slot).
    //         Note immutable and constants do not take up storage slots so they can come before.
    address internal _avoImplementation;

    /// @notice nonce that is incremented for every `cast` / `castAuthorized` transaction (unless it uses a non-sequential nonce)
    uint88 public avoSafeNonce;

    /// @dev flag set temporarily to signal various cases:
    /// 0 -> default state
    /// 1 -> triggered request had valid signatures, `_callTargets` can be executed
    /// 20 / 21 -> flashloan receive can be executed (set to original `CastParams.id` input param)
    uint8 internal _status;
}

abstract contract AvoCoreVariablesSlot1 {
    /// @notice owner of the Avocado smart wallet
    //  @dev theoretically immutable, can only be set in initialize (at proxy clone AvoFactory deployment)
    address public owner;

    /// @dev Initializable.sol variables (modified from OpenZeppelin), see ./lib folder
    /// @dev Indicates that the contract has been initialized.
    uint8 internal _initialized;
    /// @dev Indicates that the contract is in the process of being initialized.
    bool internal _initializing;

    // 10 bytes empty
}

abstract contract AvoCoreVariablesSlot2 {
    // contracts deployed before V2 contain two more variables from EIP712Upgradeable: hashed domain separator
    // name and version which were set at initialization (Now we do this in logic contract at deployment as constant)
    // https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/utils/cryptography/EIP712Upgradeable.sol#L32

    // BEFORE VERSION 2.0.0:
    // bytes32 private _HASHED_NAME;

    /// @dev allow-listed signed messages, e.g. for Permit2 Uniswap interaction
    /// mappings are not in sequential storage slot, thus not influenced by previous storage variables
    /// (but consider the slot number in calculating the hash of the key to store).
    mapping(bytes32 => uint256) internal _signedMessages;
}

abstract contract AvoCoreVariablesSlot3 {
    // BEFORE VERSION 2.0.0:
    // bytes32 private _HASHED_VERSION; see comment in storage slot 2

    /// @notice used non-sequential nonces (which can not be used again)
    mapping(bytes32 => uint256) public nonSequentialNonces;
}

abstract contract AvoCoreSlotGaps {
    // create some storage slot gaps for future expansion of AvoCore variables before the customized variables
    // of AvoWallet & AvoMultisig
    uint256[50] private __gaps;
}

abstract contract AvoCoreVariables is
    AvoCoreConstants,
    AvoCoreConstantsOverride,
    AvoCoreVariablesSlot0,
    AvoCoreVariablesSlot1,
    AvoCoreVariablesSlot2,
    AvoCoreVariablesSlot3,
    AvoCoreSlotGaps
{}

