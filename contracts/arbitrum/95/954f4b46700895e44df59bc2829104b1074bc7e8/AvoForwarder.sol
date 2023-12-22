// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { Address } from "./Address.sol";
import { Initializable } from "./lib_Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import { IAvoFactory } from "./IAvoFactory.sol";
import { IAvoForwarder } from "./IAvoForwarder.sol";
import { IAvoWalletV1 } from "./IAvoWalletV1.sol";
import { IAvoWalletV2 } from "./IAvoWalletV2.sol";
import { IAvoWalletV3 } from "./IAvoWalletV3.sol";
import { IAvoMultisigV3 } from "./IAvoMultisigV3.sol";
import { IAvoSafe } from "./AvoSafe.sol";

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvoForwarder v3.0.0
/// @notice Only compatible with forwarding `cast` calls to Avocado smart wallet contracts.
/// This is not a generic forwarder.
/// This is NOT a "TrustedForwarder" as proposed in EIP-2770, see info in Avocado smart wallet contracts.
///
/// Does not validate the EIP712 signature (instead this is done in the smart wallet itself).
///
/// Upgradeable through AvoForwarderProxy
interface AvoForwarder_V3 {

}

abstract contract AvoForwarderConstants is IAvoForwarder {
    /// @notice AvoFactory (proxy) used to deploy new Avocado smart wallets.
    //
    // @dev     If this changes then the deployment addresses for Avocado smart wallets change too. A more complex
    //          system with versioning would have to be implemented then for most methods.
    IAvoFactory public immutable avoFactory;

    /// @notice cached AvoSafe Bytecode to optimize gas usage.
    //
    // @dev If this changes because of an AvoSafe change (and AvoFactory upgrade),
    // then this variable must be updated through an upgrade deploying a new AvoForwarder!
    bytes32 public immutable avoSafeBytecode;

    /// @notice cached AvoMultiSafe Bytecode to optimize gas usage.
    //
    // @dev If this changes because of an AvoMultiSafe change (and AvoFactory upgrade),
    // then this variable must be updated through an upgrade deploying a new AvoForwarder!
    bytes32 public immutable avoMultiSafeBytecode;

    constructor(IAvoFactory avoFactory_) {
        avoFactory = avoFactory_;

        // get AvoSafe & AvoMultiSafe bytecode from factory.
        // @dev Note if a new AvoFactory is deployed (upgraded), a new AvoForwarder must be deployed
        // to update these bytecodes. See README for more info.
        avoSafeBytecode = avoFactory.avoSafeBytecode();
        avoMultiSafeBytecode = avoFactory.avoMultiSafeBytecode();
    }
}

abstract contract AvoForwarderVariables is AvoForwarderConstants, Initializable, OwnableUpgradeable {
    // @dev variables here start at storage slot 101, before is:
    // - Initializable with storage slot 0:
    // uint8 private _initialized;
    // bool private _initializing;
    // - OwnableUpgradeable with slots 1 to 100:
    // uint256[50] private __gap; (from ContextUpgradeable, slot 1 until slot 50)
    // address private _owner; (at slot 51)
    // uint256[49] private __gap; (slot 52 until slot 100)

    // ---------------- slot 101 -----------------

    /// @notice allowed broadcasters that can call `execute()` methods. allowed if set to `1`
    mapping(address => uint256) public broadcasters;

    // ---------------- slot 102 -----------------

    /// @notice allowed auths. allowed if set to `1`
    mapping(address => uint256) public auths;
}

abstract contract AvoForwarderErrors {
    /// @notice thrown when a method is called with invalid params (e.g. zero address)
    error AvoForwarder__InvalidParams();

    /// @notice thrown when a caller is not authorized to execute a certain action
    error AvoForwarder__Unauthorized();

    /// @notice thrown when trying to execute legacy methods for a not yet deployed Avocado smart wallet
    error AvoForwarder__LegacyVersionNotDeployed();
}

abstract contract AvoForwarderStructs {
    /// @notice struct mapping an address value to a boolean flag.
    //
    // @dev when used as input param, removes need to make sure two input arrays are of same length etc.
    struct AddressBool {
        address addr;
        bool value;
    }
}

abstract contract AvoForwarderEvents is AvoForwarderStructs {
    /// @notice emitted when all actions for `cast()` in an `execute()` method are executed successfully
    event Executed(
        address indexed avoSafeOwner,
        address indexed avoSafeAddress,
        address indexed source,
        bytes metadata
    );

    /// @notice emitted if one of the actions for `cast()` in an `execute()` method fails
    event ExecuteFailed(
        address indexed avoSafeOwner,
        address indexed avoSafeAddress,
        address indexed source,
        bytes metadata,
        string reason
    );

    /// @notice emitted if a broadcaster's allowed status is updated
    event BroadcasterUpdated(address indexed broadcaster, bool indexed status);

    /// @notice emitted if an auth's allowed status is updated
    event AuthUpdated(address indexed auth, bool indexed status);
}

abstract contract AvoForwarderCore is
    AvoForwarderConstants,
    AvoForwarderVariables,
    AvoForwarderStructs,
    AvoForwarderEvents,
    AvoForwarderErrors
{
    /***********************************|
    |             MODIFIERS             |
    |__________________________________*/

    /// @dev checks if `msg.sender` is an allowed broadcaster
    modifier onlyBroadcaster() {
        if (broadcasters[msg.sender] != 1) {
            revert AvoForwarder__Unauthorized();
        }
        _;
    }

    /// @dev checks if an address is not the zero address
    modifier validAddress(address _address) {
        if (_address == address(0)) {
            revert AvoForwarder__InvalidParams();
        }
        _;
    }

    /***********************************|
    |            CONSTRUCTOR            |
    |__________________________________*/

    constructor(IAvoFactory avoFactory_) validAddress(address(avoFactory_)) AvoForwarderConstants(avoFactory_) {
        // Ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev gets or if necessary deploys an AvoSafe for owner `from_` and returns the address
    function _getDeployedAvoWallet(address from_) internal returns (address) {
        address computedAvoSafeAddress_ = _computeAvoSafeAddress(from_);
        if (Address.isContract(computedAvoSafeAddress_)) {
            return computedAvoSafeAddress_;
        } else {
            return avoFactory.deploy(from_);
        }
    }

    /// @dev gets or if necessary deploys an AvoMultiSafe for owner `from_` and returns the address
    function _getDeployedAvoMultisig(address from_) internal returns (address) {
        address computedAvoSafeAddress_ = _computeAvoSafeAddressMultisig(from_);
        if (Address.isContract(computedAvoSafeAddress_)) {
            return computedAvoSafeAddress_;
        } else {
            return avoFactory.deployMultisig(from_);
        }
    }

    /// @dev computes the deterministic contract address `computedAddress_` for an AvoSafe deployment for `owner_`
    function _computeAvoSafeAddress(address owner_) internal view returns (address computedAddress_) {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(avoFactory), _getSalt(owner_), avoSafeBytecode)
        );

        // cast last 20 bytes of hash to address via low level assembly
        assembly {
            computedAddress_ := and(hash, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /// @dev computes the deterministic contract address `computedAddress_` for an AvoMultiSafe deployment for `owner_`
    function _computeAvoSafeAddressMultisig(address owner_) internal view returns (address computedAddress_) {
        // replicate Create2 address determination logic
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(avoFactory), _getSaltMultisig(owner_), avoMultiSafeBytecode)
        );

        // cast last 20 bytes of hash to address via low level assembly
        assembly {
            computedAddress_ := and(hash, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /// @dev gets the bytes32 salt used for deterministic deployment for `owner_`
    function _getSalt(address owner_) internal pure returns (bytes32) {
        // only owner is used as salt
        // no extra salt is needed because even if another version of AvoFactory would be deployed,
        // deterministic deployments take into account the deployers address (i.e. the factory address)
        return keccak256(abi.encode(owner_));
    }

    /// @dev gets the bytes32 salt used for deterministic Multisig deployment for `owner_`
    function _getSaltMultisig(address owner_) internal pure returns (bytes32) {
        // only owner is used as salt
        // no extra salt is needed because even if another version of AvoFactory would be deployed,
        // deterministic deployments take into account the deployers address (i.e. the factory address)
        return keccak256(abi.encode(owner_));
    }

    /// @dev gets the *already*  deployed AvoWallet (not Multisig) for legacy versions.
    ///      reverts with `AvoForwarder__LegacyVersionNotDeployed()` it wallet is not yet deployed
    function _getDeployedLegacyAvoWallet(address from_) internal view returns (address) {
        // For legacy versions, AvoWallet must already be deployed
        address computedAvoSafeAddress_ = _computeAvoSafeAddress(from_);
        if (!Address.isContract(computedAvoSafeAddress_)) {
            revert AvoForwarder__LegacyVersionNotDeployed();
        }

        return computedAvoSafeAddress_;
    }
}

abstract contract AvoForwarderViews is AvoForwarderCore {
    /// @notice checks if a `broadcaster_` address is an allowed broadcaster
    function isBroadcaster(address broadcaster_) external view returns (bool) {
        return broadcasters[broadcaster_] == 1;
    }

    /// @notice checks if an `auth_` address is an allowed auth
    function isAuth(address auth_) external view returns (bool) {
        return auths[auth_] == 1;
    }

    /// @notice        Retrieves the current avoSafeNonce of an AvoSafe for `owner_` address.
    ///                Needed for signatures.
    /// @param owner_  AvoSafe owner to retrieve the nonce for.
    /// @return        returns the avoSafeNonce for the owner necessary to sign a meta transaction
    function avoSafeNonce(address owner_) external view returns (uint88) {
        address avoAddress_ = _computeAvoSafeAddress(owner_);
        if (Address.isContract(avoAddress_)) {
            return IAvoWalletV3(avoAddress_).avoSafeNonce();
        }

        // defaults to 0 if not yet deployed
        return 0;
    }

    /// @notice        Retrieves the current AvoWallet implementation name for `owner_` address.
    ///                Needed for signatures.
    /// @param owner_  AvoSafe owner to retrieve the name for.
    /// @return        returns the domain separator name for the `owner_` necessary to sign a meta transaction
    function avoWalletVersionName(address owner_) external view returns (string memory) {
        address avoAddress_ = _computeAvoSafeAddress(owner_);
        if (Address.isContract(avoAddress_)) {
            // if AvoWallet is deployed, return value from deployed contract
            return IAvoWalletV3(avoAddress_).DOMAIN_SEPARATOR_NAME();
        }

        // otherwise return default value for current implementation that will be deployed
        return IAvoWalletV3(avoFactory.avoWalletImpl()).DOMAIN_SEPARATOR_NAME();
    }

    /// @notice       Retrieves the current AvoWallet implementation version for `owner_` address.
    ///               Needed for signatures.
    /// @param owner_ AvoSafe owner to retrieve the version for.
    /// @return       returns the domain separator version for the `owner_` necessary to sign a meta transaction
    function avoWalletVersion(address owner_) external view returns (string memory) {
        address avoAddress_ = _computeAvoSafeAddress(owner_);
        if (Address.isContract(avoAddress_)) {
            // if AvoWallet is deployed, return value from deployed contract
            return IAvoWalletV3(avoAddress_).DOMAIN_SEPARATOR_VERSION();
        }

        // otherwise return default value for current implementation that will be deployed
        return IAvoWalletV3(avoFactory.avoWalletImpl()).DOMAIN_SEPARATOR_VERSION();
    }

    /// @notice Computes the deterministic AvoSafe address for `owner_` based on Create2
    function computeAddress(address owner_) external view returns (address) {
        if (Address.isContract(owner_)) {
            // owner of a AvoSafe must be an EOA, if it's a contract return zero address
            return address(0);
        }
        return _computeAvoSafeAddress(owner_);
    }
}

abstract contract AvoForwarderViewsMultisig is AvoForwarderCore {
    /// @notice        Retrieves the current avoSafeNonce of AvoMultisig for `owner_` address.
    ///                Needed for signatures.
    /// @param owner_  AvoMultisig owner to retrieve the nonce for.
    /// @return        returns the avoSafeNonce for the `owner_` necessary to sign a meta transaction
    function avoSafeNonceMultisig(address owner_) external view returns (uint88) {
        address avoAddress_ = _computeAvoSafeAddressMultisig(owner_);
        if (Address.isContract(avoAddress_)) {
            return IAvoMultisigV3(avoAddress_).avoSafeNonce();
        }

        return 0;
    }

    /// @notice        Retrieves the current AvoMultisig implementation name for `owner_` address.
    ///                Needed for signatures.
    /// @param owner_  AvoMultisig owner to retrieve the name for.
    /// @return        returns the domain separator name for the `owner_` necessary to sign a meta transaction
    function avoMultisigVersionName(address owner_) external view returns (string memory) {
        address avoAddress_ = _computeAvoSafeAddressMultisig(owner_);
        if (Address.isContract(avoAddress_)) {
            // if AvoMultisig is deployed, return value from deployed contract
            return IAvoMultisigV3(avoAddress_).DOMAIN_SEPARATOR_NAME();
        }

        // otherwise return default value for current implementation that will be deployed
        return IAvoMultisigV3(avoFactory.avoMultisigImpl()).DOMAIN_SEPARATOR_NAME();
    }

    /// @notice        Retrieves the current AvoMultisig implementation version for `owner_` address.
    ///                Needed for signatures.
    /// @param owner_  AvoMultisig owner to retrieve the version for.
    /// @return        returns the domain separator version for the `owner_` necessary to sign a meta transaction
    function avoMultisigVersion(address owner_) external view returns (string memory) {
        address avoAddress_ = _computeAvoSafeAddressMultisig(owner_);
        if (Address.isContract(avoAddress_)) {
            // if AvoMultisig is deployed, return value from deployed contract
            return IAvoMultisigV3(avoAddress_).DOMAIN_SEPARATOR_VERSION();
        }

        // otherwise return default value for current implementation that will be deployed
        return IAvoMultisigV3(avoFactory.avoMultisigImpl()).DOMAIN_SEPARATOR_VERSION();
    }

    /// @notice Computes the deterministic AvoMultiSafe address for `owner_` based on Create2
    function computeAddressMultisig(address owner_) external view returns (address) {
        if (Address.isContract(owner_)) {
            // owner of a AvoSafe must be an EOA, if it's a contract return zero address
            return address(0);
        }
        return _computeAvoSafeAddressMultisig(owner_);
    }
}

abstract contract AvoForwarderV1 is AvoForwarderCore {
    /// @notice            Calls `cast` on an already deployed AvoWallet. For AvoWallet version 1.0.0.
    ///                    Only callable by allowed broadcasters.
    /// @param from_       AvoSafe owner who signed the transaction
    /// @param actions_    the actions to execute (target, data, value)
    /// @param validUntil_ As EIP-2770: the highest block number the request can be forwarded in, or 0 if request validity is not time-limited
    ///                    Protects against relayers executing a certain transaction at a later moment not intended by the user, where it might
    ///                    have a completely different effect. (Given that the transaction is not executed right away for some reason)
    /// @param gas_        As EIP-2770: an amount of gas limit to set for the execution
    ///                    Protects against potential gas griefing attacks / the relayer getting a reward without properly executing the tx completely
    ///                    See https://ronan.eth.limo/blog/ethereum-gas-dangers/
    /// @param source_     Source like e.g. referral for this tx
    /// @param metadata_   Optional metadata for future flexibility
    /// @param signature_  the EIP712 signature, see verifySig method
    function executeV1(
        address from_,
        IAvoWalletV1.Action[] calldata actions_,
        uint256 validUntil_,
        uint256 gas_,
        address source_,
        bytes calldata metadata_,
        bytes calldata signature_
    ) public payable onlyBroadcaster {
        IAvoWalletV1 avoWallet_ = IAvoWalletV1(_getDeployedLegacyAvoWallet(from_));

        (bool success_, string memory revertReason_) = avoWallet_.cast{ value: msg.value }(
            actions_,
            validUntil_,
            gas_,
            source_,
            metadata_,
            signature_
        );

        if (success_ == true) {
            emit Executed(from_, address(avoWallet_), source_, metadata_);
        } else {
            emit ExecuteFailed(from_, address(avoWallet_), source_, metadata_, revertReason_);
        }
    }

    /// @notice            Verify the transaction is valid and can be executed. For AvoWallet version 1.0.0
    ///                    IMPORTANT: Expected to be called via callStatic
    ///                    Does not revert and returns successfully if the input is valid.
    ///                    Reverts if any validation has failed. For instance, if params or either signature or avoSafeNonce are incorrect.
    /// @param from_       AvoSafe owner who signed the transaction
    /// @param actions_    the actions to execute (target, data, value)
    /// @param validUntil_ As EIP-2770: the highest block number the request can be forwarded in, or 0 if request validity is not time-limited
    ///                    Protects against relayers executing a certain transaction at a later moment not intended by the user, where it might
    ///                    have a completely different effect. (Given that the transaction is not executed right away for some reason)
    /// @param gas_        As EIP-2770: an amount of gas limit to set for the execution
    ///                    Protects against potential gas griefing attacks / the relayer getting a reward without properly executing the tx completely
    ///                    See https://ronan.eth.limo/blog/ethereum-gas-dangers/
    /// @param source_     Source like e.g. referral for this tx
    /// @param metadata_   Optional metadata for future flexibility
    /// @param signature_  the EIP712 signature, see verifySig method
    //
    /// @return            returns true if everything is valid, otherwise reverts
    // @dev                 not marked as view because it did potentially state by deploying the AvoWallet for `from_`
    //                      if it does not exist yet. Keeping things as was for legacy version methods.
    function verifyV1(
        address from_,
        IAvoWalletV1.Action[] calldata actions_,
        uint256 validUntil_,
        uint256 gas_,
        address source_,
        bytes calldata metadata_,
        bytes calldata signature_
    ) public returns (bool) {
        IAvoWalletV1 avoWallet_ = IAvoWalletV1(_getDeployedLegacyAvoWallet(from_));

        return avoWallet_.verify(actions_, validUntil_, gas_, source_, metadata_, signature_);
    }

    /***********************************|
    |      LEGACY DEPRECATED FOR V1     |
    |__________________________________*/

    /// @dev    DEPRECATED: Use executeV1() instead. Will be removed in the next version
    /// @notice             see executeV1() for details
    function execute(
        address from_,
        IAvoWalletV1.Action[] calldata actions_,
        uint256 validUntil_,
        uint256 gas_,
        address source_,
        bytes calldata metadata_,
        bytes calldata signature_
    ) external payable onlyBroadcaster {
        return executeV1(from_, actions_, validUntil_, gas_, source_, metadata_, signature_);
    }

    /// @dev    DEPRECATED: Use executeV1() instead. Will be removed in the next version
    /// @notice             see verifyV1() for details
    function verify(
        address from_,
        IAvoWalletV1.Action[] calldata actions_,
        uint256 validUntil_,
        uint256 gas_,
        address source_,
        bytes calldata metadata_,
        bytes calldata signature_
    ) external returns (bool) {
        return verifyV1(from_, actions_, validUntil_, gas_, source_, metadata_, signature_);
    }
}

abstract contract AvoForwarderV2 is AvoForwarderCore {
    /// @notice             Calls `cast` on an already deployed AvoWallet. For AvoWallet version ~2.
    ///                     Only callable by allowed broadcasters.
    /// @param from_        AvoSafe owner who signed the transaction
    /// @param actions_     the actions to execute (target, data, value, operation)
    /// @param params_      Cast params: validUntil, gas, source, id and metadata
    /// @param signature_   the EIP712 signature, see verifySig method
    function executeV2(
        address from_,
        IAvoWalletV2.Action[] calldata actions_,
        IAvoWalletV2.CastParams calldata params_,
        bytes calldata signature_
    ) external payable onlyBroadcaster {
        IAvoWalletV2 avoWallet_ = IAvoWalletV2(_getDeployedLegacyAvoWallet(from_));

        (bool success_, string memory revertReason_) = avoWallet_.cast{ value: msg.value }(
            actions_,
            params_,
            signature_
        );

        if (success_ == true) {
            emit Executed(from_, address(avoWallet_), params_.source, params_.metadata);
        } else {
            (address(avoWallet_)).call(abi.encodeWithSelector(bytes4(0xb92e87fa), new IAvoWalletV2.Action[](0), 0));

            emit ExecuteFailed(from_, address(avoWallet_), params_.source, params_.metadata, revertReason_);
        }
    }

    /// @notice             Verify the transaction is valid and can be executed. For deployed AvoWallet version ~2
    ///                     IMPORTANT: Expected to be called via callStatic
    ///                     Returns true if valid, reverts otherwise:
    ///                     e.g. if input params, signature or avoSafeNonce etc. are invalid.
    /// @param from_        AvoSafe owner who signed the transaction
    /// @param actions_     the actions to execute (target, data, value, operation)
    /// @param params_      Cast params: validUntil, gas, source, id and metadata
    /// @param signature_   the EIP712 signature, see verifySig method
    /// @return             returns true if everything is valid, otherwise reverts
    //
    // @dev                 not marked as view because it did potentially state by deploying the AvoWallet for `from_`
    //                      if it does not exist yet. Keeping things as was for legacy version methods.
    function verifyV2(
        address from_,
        IAvoWalletV2.Action[] calldata actions_,
        IAvoWalletV2.CastParams calldata params_,
        bytes calldata signature_
    ) external returns (bool) {
        IAvoWalletV2 avoWallet_ = IAvoWalletV2(_getDeployedLegacyAvoWallet(from_));

        return avoWallet_.verify(actions_, params_, signature_);
    }
}

abstract contract AvoForwarderV3 is AvoForwarderCore {
    /// @notice                 Deploys AvoSafe for owner if necessary and calls `cast()` on it. For AvoWallet version ~3.
    ///                         Only callable by allowed broadcasters.
    /// @param from_            AvoSafe owner. Not the one who signed the signature, but rather the owner of the AvoSafe
    ///                         (signature might also be from an authority).
    /// @param params_          Cast params such as id, avoSafeNonce and actions to execute
    /// @param forwardParams_   Cast params related to validity of forwarding as instructed and signed
    /// @param signatureParams_ struct for signature and signer:
    ///                         - signature: the EIP712 signature, 65 bytes ECDSA signature for a default EOA.
    ///                           For smart contract signatures it must fulfill the requirements for the relevant
    ///                           smart contract `.isValidSignature()` EIP1271 logic
    ///                         - signer: address of the signature signer.
    ///                           Must match the actual signature signer or refer to the smart contract
    ///                           that must be an allowed signer and validates signature via EIP1271
    function executeV3(
        address from_,
        IAvoWalletV3.CastParams calldata params_,
        IAvoWalletV3.CastForwardParams calldata forwardParams_,
        IAvoWalletV3.SignatureParams calldata signatureParams_
    ) external payable onlyBroadcaster {
        // `_getDeployedAvoWallet()` automatically checks if AvoSafe has to be deployed
        // or if it already exists and simply returns the address in that case
        IAvoWalletV3 avoWallet_ = IAvoWalletV3(_getDeployedAvoWallet(from_));

        (bool success_, string memory revertReason_) = avoWallet_.cast{ value: msg.value }(
            params_,
            forwardParams_,
            signatureParams_
        );

        if (success_ == true) {
            emit Executed(from_, address(avoWallet_), params_.source, params_.metadata);
        } else {
            emit ExecuteFailed(from_, address(avoWallet_), params_.source, params_.metadata, revertReason_);
        }
    }

    /// @notice                 Verify the transaction is valid and can be executed. For AvoWallet version ~3.
    ///                         IMPORTANT: Expected to be called via callStatic.
    ///
    ///                         Returns true if valid, reverts otherwise:
    ///                         e.g. if input params, signature or avoSafeNonce etc. are invalid.
    /// @param from_            AvoSafe owner. Not the one who signed the signature, but rather the owner of the AvoSafe
    ///                         (signature might also be from an authority).
    /// @param params_          Cast params such as id, avoSafeNonce and actions to execute
    /// @param forwardParams_   Cast params related to validity of forwarding as instructed and signed
    /// @param signatureParams_ struct for signature and signer:
    ///                         - signature: the EIP712 signature, 65 bytes ECDSA signature for a default EOA.
    ///                           For smart contract signatures it must fulfill the requirements for the relevant
    ///                           smart contract `.isValidSignature()` EIP1271 logic
    ///                         - signer: address of the signature signer.
    ///                           Must match the actual signature signer or refer to the smart contract
    ///                           that must be an allowed signer and validates signature via EIP1271
    /// @return                 returns true if everything is valid, otherwise reverts
    //
    // @dev can not be marked as view because it does potentially modify state by deploying the
    //      AvoWallet for `from_` if it does not exist yet. Thus expected to be called via callStatic.
    function verifyV3(
        address from_,
        IAvoWalletV3.CastParams calldata params_,
        IAvoWalletV3.CastForwardParams calldata forwardParams_,
        IAvoWalletV3.SignatureParams calldata signatureParams_
    ) external returns (bool) {
        // `_getDeployedAvoWallet()` automatically checks if AvoSafe has to be deployed
        // or if it already exists and simply returns the address
        IAvoWalletV3 avoWallet_ = IAvoWalletV3(_getDeployedAvoWallet(from_));

        return avoWallet_.verify(params_, forwardParams_, signatureParams_);
    }
}

abstract contract AvoForwarderMultisig is AvoForwarderCore {
    /// @notice                  Deploys AvoMultiSafe for owner if necessary and calls `cast()` on it.
    ///                          For AvoMultisig version ~3.
    ///                          Only callable by allowed broadcasters.
    /// @param from_             AvoMultisig owner
    /// @param params_           Cast params such as id, avoSafeNonce and actions to execute
    /// @param forwardParams_    Cast params related to validity of forwarding as instructed and signed
    /// @param signaturesParams_ SignatureParams structs array for signature and signer:
    ///                          - signature: the EIP712 signature, 65 bytes ECDSA signature for a default EOA.
    ///                            For smart contract signatures it must fulfill the requirements for the relevant
    ///                            smart contract `.isValidSignature()` EIP1271 logic
    ///                          - signer: address of the signature signer.
    ///                            Must match the actual signature signer or refer to the smart contract
    ///                            that must be an allowed signer and validates signature via EIP1271
    function executeMultisigV3(
        address from_,
        IAvoMultisigV3.CastParams calldata params_,
        IAvoMultisigV3.CastForwardParams calldata forwardParams_,
        IAvoMultisigV3.SignatureParams[] calldata signaturesParams_
    ) external payable onlyBroadcaster {
        // `_getDeployedAvoMultisig()` automatically checks if AvoMultiSafe has to be deployed
        // or if it already exists and simply returns the address in that case
        IAvoMultisigV3 avoMultisig_ = IAvoMultisigV3(_getDeployedAvoMultisig(from_));

        (bool success_, string memory revertReason_) = avoMultisig_.cast{ value: msg.value }(
            params_,
            forwardParams_,
            signaturesParams_
        );

        if (success_ == true) {
            emit Executed(from_, address(avoMultisig_), params_.source, params_.metadata);
        } else {
            emit ExecuteFailed(from_, address(avoMultisig_), params_.source, params_.metadata, revertReason_);
        }
    }

    /// @notice                  Verify the transaction is valid and can be executed.
    ///                          IMPORTANT: Expected to be called via callStatic.
    ///
    ///                          Returns true if valid, reverts otherwise:
    ///                          e.g. if input params, signature or avoSafeNonce etc. are invalid.
    /// @param from_             AvoMultiSafe owner
    /// @param params_           Cast params such as id, avoSafeNonce and actions to execute
    /// @param forwardParams_    Cast params related to validity of forwarding as instructed and signed
    /// @param signaturesParams_ SignatureParams structs array for signature and signer:
    ///                          - signature: the EIP712 signature, 65 bytes ECDSA signature for a default EOA.
    ///                            For smart contract signatures it must fulfill the requirements for the relevant
    ///                            smart contract `.isValidSignature()` EIP1271 logic
    ///                          - signer: address of the signature signer.
    ///                            Must match the actual signature signer or refer to the smart contract
    ///                            that must be an allowed signer and validates signature via EIP1271
    /// @return                  returns true if everything is valid, otherwise reverts.
    //
    // @dev can not be marked as view because it does potentially modify state by deploying the
    //      AvoMultisig for `from_` if it does not exist yet. Thus expected to be called via callStatic
    function verifyMultisigV3(
        address from_,
        IAvoMultisigV3.CastParams calldata params_,
        IAvoMultisigV3.CastForwardParams calldata forwardParams_,
        IAvoMultisigV3.SignatureParams[] calldata signaturesParams_
    ) external returns (bool) {
        // `_getDeployedAvoMultisig()` automatically checks if AvoMultiSafe has to be deployed
        // or if it already exists and simply returns the address in that case
        IAvoMultisigV3 avoMultisig_ = IAvoMultisigV3(_getDeployedAvoMultisig(from_));

        return avoMultisig_.verify(params_, forwardParams_, signaturesParams_);
    }
}

abstract contract AvoForwarderOwnerActions is AvoForwarderCore {
    /// @dev modifier checks if `msg.sender` is either owner or allowed auth, reverts if not.
    modifier onlyAuthOrOwner() {
        if (!(msg.sender == owner() || auths[msg.sender] == 1)) {
            revert AvoForwarder__Unauthorized();
        }

        _;
    }

    /// @notice updates allowed status for broadcasters based on `broadcastersStatus_` and emits `BroadcastersUpdated`.
    /// Executable by allowed auths or owner only.
    function updateBroadcasters(AddressBool[] calldata broadcastersStatus_) external onlyAuthOrOwner {
        uint256 length_ = broadcastersStatus_.length;
        for (uint256 i; i < length_; ) {
            if (broadcastersStatus_[i].addr == address(0)) {
                revert AvoForwarder__InvalidParams();
            }

            broadcasters[broadcastersStatus_[i].addr] = broadcastersStatus_[i].value ? 1 : 0;

            emit BroadcasterUpdated(broadcastersStatus_[i].addr, broadcastersStatus_[i].value);

            unchecked {
                i++;
            }
        }
    }

    /// @notice updates allowed status for a auths based on `authsStatus_` and emits `AuthsUpdated`.
    /// Executable by allowed auths or owner only (auths can only remove themselves).
    function updateAuths(AddressBool[] calldata authsStatus_) external onlyAuthOrOwner {
        uint256 length_ = authsStatus_.length;

        bool isMsgSenderOwner = msg.sender == owner();

        for (uint256 i; i < length_; ) {
            if (authsStatus_[i].addr == address(0)) {
                revert AvoForwarder__InvalidParams();
            }

            uint256 setStatus_ = authsStatus_[i].value ? 1 : 0;

            // if `msg.sender` is auth, then operation must be remove and address to be removed must be auth itself
            if (!(isMsgSenderOwner || (setStatus_ == 0 && msg.sender == authsStatus_[i].addr))) {
                revert AvoForwarder__Unauthorized();
            }

            auths[authsStatus_[i].addr] = setStatus_;

            emit AuthUpdated(authsStatus_[i].addr, authsStatus_[i].value);

            unchecked {
                i++;
            }
        }
    }
}

contract AvoForwarder is
    AvoForwarderCore,
    AvoForwarderViews,
    AvoForwarderViewsMultisig,
    AvoForwarderV1,
    AvoForwarderV2,
    AvoForwarderV3,
    AvoForwarderMultisig,
    AvoForwarderOwnerActions
{
    /// @notice constructor sets the immutable `avoFactory` (proxy) address and cached bytecodes derived from it
    constructor(IAvoFactory avoFactory_) AvoForwarderCore(avoFactory_) {}

    /// @notice initializes the contract, setting `owner_` as owner
    function initialize(address owner_) public validAddress(owner_) initializer {
        _transferOwnership(owner_);
    }

    /// @notice reinitiliaze to set `owner`, configuring OwnableUpgradeable added in version 3.0.0.
    ///         Also sets initial allowed broadcasters to `allowedBroadcasters_`.
    ///         Skips setting `owner` if it is already set.
    ///         for fresh deployments, `owner` set in initialize() could not be overwritten
    /// @param owner_                address of owner_ allowed to executed auth limited methods
    /// @param allowedBroadcasters_  initial list of allowed broadcasters to be enabled right away
    function reinitialize(
        address owner_,
        address[] calldata allowedBroadcasters_
    ) public validAddress(owner_) reinitializer(2) {
        if (owner() == address(0)) {
            // only set owner if it's not already set but do not revert so initializer storage var is set to `2` always
            _transferOwnership(owner_);
        }

        // set initial allowed broadcasters
        uint256 length_ = allowedBroadcasters_.length;
        for (uint256 i; i < length_; ) {
            if (allowedBroadcasters_[i] == address(0)) {
                revert AvoForwarder__InvalidParams();
            }

            broadcasters[allowedBroadcasters_[i]] = 1;

            emit BroadcasterUpdated(allowedBroadcasters_[i], true);

            unchecked {
                i++;
            }
        }
    }
}

