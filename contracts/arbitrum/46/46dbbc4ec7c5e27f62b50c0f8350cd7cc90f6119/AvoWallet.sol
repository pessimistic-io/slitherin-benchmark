// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { ECDSA } from "./ECDSA.sol";
import { Address } from "./Address.sol";
import { IERC1271 } from "./IERC1271.sol";

import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";
import { AvoCore, AvoCoreEIP1271, AvoCoreSelfUpgradeable, AvoCoreProtected } from "./AvoCore.sol";
import { IAvoAuthoritiesList } from "./IAvoAuthoritiesList.sol";
import { IAvoWalletV3Base } from "./IAvoWalletV3.sol";
import { AvoWalletVariables } from "./AvoWalletVariables.sol";
import { AvoWalletEvents } from "./AvoWalletEvents.sol";
import { AvoWalletErrors } from "./AvoWalletErrors.sol";

// --------------------------- DEVELOPER NOTES -----------------------------------------
// @dev IMPORTANT: all storage variables go into AvoWalletVariables.sol
// -------------------------------------------------------------------------------------

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvoWallet v3.0.0
/// @notice Smart wallet enabling meta transactions through a EIP712 signature.
///
/// Supports:
/// - Executing arbitrary actions
/// - Receiving NFTs (ERC721)
/// - Receiving ERC1155 tokens
/// - ERC1271 smart contract signatures
/// - Instadapp Flashloan callbacks
///
/// The `cast` method allows the AvoForwarder (relayer) to execute multiple arbitrary actions authorized by signature.
/// Broadcasters are expected to call the AvoForwarder contract `execute()` method, which also automatically
/// deploys an Avocado smart wallet if necessary first.
///
/// Upgradeable by calling `upgradeTo` (or `upgradeToAndCall`) through a `cast` / `castAuthorized` call.
///
/// The `castAuthorized` method allows the owner of the wallet to execute multiple arbitrary actions directly
/// without the AvoForwarder in between, to guarantee the smart wallet is truly non-custodial.
///
/// _@dev Notes:_
/// - This contract implements parts of EIP-2770 in a minimized form. E.g. domainSeparator is immutable etc.
/// - This contract does not implement ERC2771, because trusting an upgradeable "forwarder" bears a security
/// risk for this non-custodial wallet.
/// - Signature related logic is based off of OpenZeppelin EIP712Upgradeable.
/// - All signatures are validated for defaultChainId of `63400` instead of `block.chainid` from opcode (EIP-1344).
/// - For replay protection, the current `block.chainid` instead is used in the EIP-712 salt.
interface AvoWallet_V3 {

}

abstract contract AvoWalletCore is AvoWalletErrors, AvoWalletVariables, AvoCore, AvoWalletEvents, IAvoWalletV3Base {
    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    constructor(
        IAvoVersionsRegistry avoVersionsRegistry_,
        address avoForwarder_,
        IAvoAuthoritiesList avoAuthoritiesList_,
        uint256 authorizedMinFee_,
        uint256 authorizedMaxFee_,
        address authorizedFeeCollector_
    )
        AvoWalletVariables(
            avoVersionsRegistry_,
            avoForwarder_,
            avoAuthoritiesList_,
            authorizedMinFee_,
            authorizedMaxFee_,
            authorizedFeeCollector_
        )
    {
        // Ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /***********************************|
    |               INTERNAL            |
    |__________________________________*/

    /// @dev                          Verifies a EIP712 signature, returning valid status in `isValid_` or reverting
    ///                               in case the params for the signature / digest are wrong
    /// @param digest_                the EIP712 digest for the signature
    /// @param signatureParams_       struct for signature and signer:
    ///                               - signature: the EIP712 signature, 65 bytes ECDSA signature for a default EOA.
    ///                                 For smart contract signatures it must fulfill the requirements for the relevant
    ///                                 smart contract `.isValidSignature()` EIP1271 logic
    ///                               - signer: address of the signature signer.
    ///                                 Must match the actual signature signer or refer to the smart contract
    ///                                 that must be an allowed signer and validates signature via EIP1271
    /// @param  isNonSequentialNonce_ flag to sginal verify with non sequential nonce or not
    /// @param  recoveredSigner_      optional recovered signer from signature for gas optimization
    /// @return isValid_              true if the signature is valid, false otherwise
    /// @return recoveredSigner_      recovered signer address of the `signatureParams_.signature`
    function _verifySig(
        bytes32 digest_,
        SignatureParams memory signatureParams_,
        bool isNonSequentialNonce_,
        address recoveredSigner_
    ) internal view returns (bool isValid_, address) {
        // for non sequential nonce, if nonce is already used, the signature has already been used and is invalid
        if (isNonSequentialNonce_ && nonSequentialNonces[digest_] == 1) {
            revert AvoWallet__InvalidParams();
        }

        if (Address.isContract(signatureParams_.signer)) {
            recoveredSigner_ = signatureParams_.signer;

            // recovered signer must be owner or allowed authority
            // but no need to check for owner as owner can only be EOA
            if (authorities[recoveredSigner_] == 1) {
                // signer is an allowed contract authority -> validate via EIP1271
                return (
                    IERC1271(signatureParams_.signer).isValidSignature(digest_, signatureParams_.signature) ==
                        EIP1271_MAGIC_VALUE,
                    signatureParams_.signer
                );
            } else {
                // signature is for different digest (params) or by an unauthorized signer
                return (false, signatureParams_.signer);
            }
        } else {
            // if signer is not a contract, then it must match the recovered signer from signature
            if (recoveredSigner_ == address(0)) {
                // only recover signer if it is not passed in already
                recoveredSigner_ = ECDSA.recover(digest_, signatureParams_.signature);
            }

            if (signatureParams_.signer != recoveredSigner_) {
                // signer does not match recovered signer. Either signer param is wrong or params used to
                // build digest are not the same as for the signature
                revert AvoWallet__InvalidParams();
            }
        }

        return (
            // recovered signer must be owner or allowed authority
            recoveredSigner_ == owner || authorities[recoveredSigner_] == 1,
            recoveredSigner_
        );
    }
}

abstract contract AvoWalletEIP1271 is AvoCoreEIP1271, AvoWalletCore {
    /// @inheritdoc IERC1271
    /// @param signature This can be one of the following:
    ///         - empty: `hash` must be a previously signed message in storage then.
    ///         - one signature of length 65 bytes (ECDSA), only works for EOA.
    ///         - 85 bytes combination of 65 bytes signature + 20 bytes signer address.
    ///         - the `abi.encode` result for `SignatureParams` struct.
    /// @dev It is better for gas usage to pass 85 bytes with signature + signer instead of 65 bytes signature only.
    /// @dev reverts with `AvoCore__InvalidEIP1271Signature` or `AvoWallet__InvalidParams` if signature is invalid.
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view override(AvoCoreEIP1271, IERC1271) returns (bytes4 magicValue) {
        // @dev function params without _ for inheritdoc
        if (signature.length == 0) {
            // must be pre-allow-listed via `signMessage` method
            if (_signedMessages[hash] != 1) {
                revert AvoCore__InvalidEIP1271Signature();
            }
        } else {
            // validate via normal signature verification. retrieve SignatureParams:
            SignatureParams memory signatureParams_;
            // recoveredSigner is ONLY set when ECDSA.recover is used, optimization skips that step then in verifySig
            address recoveredSigner_;
            if (signature.length == 65) {
                // only ECDSA signature is given -> recover signer from signature (only EOA supported)
                signatureParams_ = SignatureParams({ signature: signature, signer: ECDSA.recover(hash, signature) });
                recoveredSigner_ = signatureParams_.signer;
            } else if (signature.length == 85) {
                // signature is 65 bytes signature and 20 bytes signer address
                bytes memory signerBytes_ = signature[65:65 + 20];
                address signer_;
                // cast bytes to address in the easiest way via assembly
                assembly {
                    signer_ := shr(96, mload(add(signerBytes_, 0x20)))
                }

                signatureParams_ = SignatureParams({ signature: signature[0:65], signer: signer_ });
            } else {
                // signature is present that should form `SignatureParams` through abi.decode.
                // Note that even for the extreme case of signature = "0x" and a signer encode result, length is > 128
                // @dev this will fail and revert if invalid typed data is passed in
                signatureParams_ = abi.decode(signature, (SignatureParams));
            }

            (bool validSignature_, ) = _verifySig(
                hash,
                signatureParams_,
                // we have no way to know nonce type, so make sure validity test covers everything.
                // setting this flag true will check that the digest is not a used non-sequential nonce.
                // unfortunately, for sequential nonces it adds unneeded verification and gas cost,
                // because the check will always pass, but there is no way around it.
                true,
                recoveredSigner_
            );

            if (!validSignature_) {
                revert AvoCore__InvalidEIP1271Signature();
            }
        }

        return EIP1271_MAGIC_VALUE;
    }
}

abstract contract AvoWalletAuthorities is AvoWalletCore {
    /// @inheritdoc IAvoWalletV3Base
    function isAuthority(address authority_) public view returns (bool) {
        return authorities[authority_] == 1;
    }

    /// @notice adds `authorities_` to allowed authorities
    function addAuthorities(address[] calldata authorities_) external onlySelf {
        uint256 authoritiesLength_ = authorities_.length;

        for (uint256 i; i < authoritiesLength_; ) {
            if (authorities_[i] == address(0)) {
                revert AvoWallet__InvalidParams();
            }

            if (authorities[authorities_[i]] != 1) {
                authorities[authorities_[i]] = 1;

                emit AuthorityAdded(authorities_[i]);
            }

            unchecked {
                ++i;
            }
        }

        // sync mappings at AvoAuthoritiesList
        avoAuthoritiesList.syncAvoAuthorityMappings(address(this), authorities_);
    }

    /// @notice removes `authorities_` from allowed authorities.
    function removeAuthorities(address[] calldata authorities_) external onlySelf {
        uint256 authoritiesLength_ = authorities_.length;

        for (uint256 i; i < authoritiesLength_; ) {
            if (authorities[authorities_[i]] != 0) {
                authorities[authorities_[i]] = 0;

                emit AuthorityRemoved(authorities_[i]);
            }

            unchecked {
                ++i;
            }
        }

        // sync mappings at AvoAuthoritiesList
        avoAuthoritiesList.syncAvoAuthorityMappings(address(this), authorities_);
    }
}

/// @dev See contract AvoCoreSelfUpgradeable
abstract contract AvoWalletSelfUpgradeable is AvoCoreSelfUpgradeable {
    /// @inheritdoc AvoCoreSelfUpgradeable
    function upgradeTo(address avoImplementation_) public override onlySelf {
        avoVersionsRegistry.requireValidAvoWalletVersion(avoImplementation_);

        _avoImplementation = avoImplementation_;
        emit Upgraded(avoImplementation_);
    }
}

abstract contract AvoWalletProtected is AvoCoreProtected {}

abstract contract AvoWalletCast is AvoWalletCore {
    /// @inheritdoc IAvoWalletV3Base
    function getSigDigest(
        CastParams memory params_,
        CastForwardParams memory forwardParams_
    ) public view returns (bytes32) {
        return
            _getSigDigest(
                params_,
                CAST_TYPE_HASH,
                // CastForwardParams hash
                keccak256(
                    abi.encode(
                        CAST_FORWARD_PARAMS_TYPE_HASH,
                        forwardParams_.gas,
                        forwardParams_.gasPrice,
                        forwardParams_.validAfter,
                        forwardParams_.validUntil
                    )
                )
            );
    }

    /// @inheritdoc IAvoWalletV3Base
    function verify(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_,
        SignatureParams calldata signatureParams_
    ) external view returns (bool) {
        _validateParams(
            params_.actions.length,
            params_.avoSafeNonce,
            forwardParams_.validAfter,
            forwardParams_.validUntil
        );

        (bool validSignature_, ) = _verifySig(
            getSigDigest(params_, forwardParams_),
            signatureParams_,
            params_.avoSafeNonce == -1,
            address(0)
        );

        // signature must be valid
        if (!validSignature_) {
            revert AvoWallet__InvalidSignature();
        }

        return true;
    }

    /// @inheritdoc IAvoWalletV3Base
    function cast(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_,
        SignatureParams memory signatureParams_
    ) external payable returns (bool success_, string memory revertReason_) {
        {
            if (msg.sender != avoForwarder) {
                // sender must be allowed forwarder
                revert AvoWallet__Unauthorized();
            }

            // compare actual sent gas to user instructed gas, adding 500 to `gasleft()` for approx. already used gas
            if ((gasleft() + 500) < forwardParams_.gas) {
                // relayer has not sent enough gas to cover gas limit as user instructed
                revert AvoWallet__InsufficientGasSent();
            }

            _validateParams(
                params_.actions.length,
                params_.avoSafeNonce,
                forwardParams_.validAfter,
                forwardParams_.validUntil
            );
        }

        bytes32 digest_ = getSigDigest(params_, forwardParams_);
        {
            bool validSignature_;
            (validSignature_, signatureParams_.signer) = _verifySig(
                digest_,
                signatureParams_,
                params_.avoSafeNonce == -1,
                address(0)
            );

            // signature must be valid
            if (!validSignature_) {
                revert AvoWallet__InvalidSignature();
            }
        }

        (success_, revertReason_) = _executeCast(
            params_,
            CAST_EVENTS_RESERVE_GAS,
            params_.avoSafeNonce == -1 ? digest_ : bytes32(0)
        );

        // @dev on changes in the code below this point, measure the needed reserve gas via gasleft() anew
        // and update reserve gas constant amounts
        if (success_ == true) {
            emit CastExecuted(params_.source, msg.sender, signatureParams_.signer, params_.metadata);
        } else {
            emit CastFailed(params_.source, msg.sender, signatureParams_.signer, revertReason_, params_.metadata);
        }
        // @dev ending point for measuring reserve gas should be here. Also see comment in `AvoCore._executeCast()`
    }
}

abstract contract AvoWalletCastAuthorized is AvoWalletCore {
    /// @inheritdoc IAvoWalletV3Base
    function nonSequentialNonceAuthorized(
        CastParams memory params_,
        CastAuthorizedParams memory authorizedParams_
    ) public view returns (bytes32) {
        return
            _getSigDigest(
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

    /// @inheritdoc IAvoWalletV3Base
    function castAuthorized(
        CastParams calldata params_,
        CastAuthorizedParams calldata authorizedParams_
    ) external payable returns (bool success_, string memory revertReason_) {
        uint256 gasSnapshot_ = gasleft();

        address owner_ = owner;
        {
            if (msg.sender != owner_) {
                // sender must be owner
                revert AvoWallet__Unauthorized();
            }

            // make sure actions are defined and nonce is valid:
            // must be -1 to use a non-sequential nonce or otherwise it must match the avoSafeNonce
            if (
                !(params_.actions.length > 0 &&
                    (params_.avoSafeNonce == -1 || uint256(params_.avoSafeNonce) == avoSafeNonce))
            ) {
                revert AvoWallet__InvalidParams();
            }
        }

        {
            bytes32 nonSequentialNonce_;
            if (params_.avoSafeNonce == -1) {
                // create a non-sequential nonce based on input params
                nonSequentialNonce_ = nonSequentialNonceAuthorized(params_, authorizedParams_);

                // for non sequential nonce, if nonce is already used, the signature has already been used and is invalid
                if (nonSequentialNonces[nonSequentialNonce_] == 1) {
                    revert AvoWallet__InvalidParams();
                }
            }

            (success_, revertReason_) = _executeCast(params_, CAST_AUTHORIZED_RESERVE_GAS, nonSequentialNonce_);

            // @dev on changes in the code below this point, measure the needed reserve gas via gasleft() anew
            // and update reserve gas constant amounts
            if (success_ == true) {
                emit CastExecuted(params_.source, msg.sender, owner_, params_.metadata);
            } else {
                emit CastFailed(params_.source, msg.sender, owner_, revertReason_, params_.metadata);
            }
        }

        // @dev `_payAuthorizedFee()` costs ~24k gas for if a fee is configured and maxFee is set
        _payAuthorizedFee(gasSnapshot_, authorizedParams_.maxFee);

        // @dev ending point for measuring reserve gas should be here. Also see comment in `AvoCore._executeCast()`
    }
}

contract AvoWallet is
    AvoWalletCore,
    AvoWalletSelfUpgradeable,
    AvoWalletProtected,
    AvoWalletEIP1271,
    AvoWalletAuthorities,
    AvoWalletCast,
    AvoWalletCastAuthorized
{
    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    /// @notice                        constructor sets multiple immutable values for contracts and payFee fallback logic.
    /// @param avoVersionsRegistry_    address of the avoVersionsRegistry (proxy) contract
    /// @param avoForwarder_           address of the avoForwarder (proxy) contract
    ///                                to forward tx with valid signatures. must be valid version in AvoVersionsRegistry.
    /// @param avoAuthoritiesList_     address of the AvoAuthoritiesList (proxy) contract
    /// @param authorizedMinFee_       minimum for fee charged via `castAuthorized()` to charge if
    ///                                `AvoVersionsRegistry.calcFee()` would fail.
    /// @param authorizedMaxFee_       maximum for fee charged via `castAuthorized()`. If AvoVersionsRegistry
    ///                                returns a fee higher than this, then `authorizedMaxFee_` is charged as fee instead.
    /// @param authorizedFeeCollector_ address that the fee charged via `castAuthorized()` is sent to in the fallback case.
    constructor(
        IAvoVersionsRegistry avoVersionsRegistry_,
        address avoForwarder_,
        IAvoAuthoritiesList avoAuthoritiesList_,
        uint256 authorizedMinFee_,
        uint256 authorizedMaxFee_,
        address authorizedFeeCollector_
    )
        AvoWalletCore(
            avoVersionsRegistry_,
            avoForwarder_,
            avoAuthoritiesList_,
            authorizedMinFee_,
            authorizedMaxFee_,
            authorizedFeeCollector_
        )
    {}

    /// @inheritdoc IAvoWalletV3Base
    function initialize(address owner_) public initializer {
        _initializeOwner(owner_);
    }

    /// @inheritdoc IAvoWalletV3Base
    function initializeWithVersion(address owner_, address avoWalletVersion_) public initializer {
        _initializeOwner(owner_);

        // set current avo implementation logic address
        _avoImplementation = avoWalletVersion_;
    }

    /// @notice storage cleanup from earlier AvoWallet Versions that filled storage slots for deprecated uses
    function reinitialize() public reinitializer(2) {
        // clean up storage slot 2 and 3, which included EIP712Upgradeable hashes in earlier versions. See Variables files
        assembly {
            // load content from storage slot 1, except for last 80 bits. Loading: 176 bit (42 * 8)
            let slot1Data_ := and(sload(0x1), 0xffffffffffffffffffffffffffffffffffffffffffff)
            sstore(0x1, slot1Data_) // overwrite last 80 bit in storage slot 1 with 0
            sstore(0x2, 0) // overwrite storage slot 2 completely
            sstore(0x3, 0) // overwrite storage slot 3 completely
        }
    }

    /***********************************|
    |            PUBLIC API             |
    |__________________________________*/

    receive() external payable {}

    /// @inheritdoc IAvoWalletV3Base
    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }
}

