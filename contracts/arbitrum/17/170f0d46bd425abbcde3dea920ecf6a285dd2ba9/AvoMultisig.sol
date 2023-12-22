// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { ECDSA } from "./ECDSA.sol";
import { Address } from "./Address.sol";
import { IERC1271 } from "./IERC1271.sol";

import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";
import { IAvoSignersList } from "./IAvoSignersList.sol";
import { AvoCore, AvoCoreEIP1271, AvoCoreSelfUpgradeable, AvoCoreProtected } from "./AvoCore.sol";
import { IAvoMultisigV3Base } from "./IAvoMultisigV3.sol";
import { AvoMultisigVariables } from "./AvoMultisigVariables.sol";
import { AvoMultisigEvents } from "./AvoMultisigEvents.sol";
import { AvoMultisigErrors } from "./AvoMultisigErrors.sol";

// --------------------------- DEVELOPER NOTES -----------------------------------------
// @dev IMPORTANT: all storage variables go into AvoMultisigVariables.sol
// -------------------------------------------------------------------------------------

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvoMultisig v3.0.0
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
/// deploys an AvoMultisig if necessary first.
///
/// Upgradeable by calling `upgradeTo` (or `upgradeToAndCall`) through a `cast` / `castAuthorized` call.
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
interface AvoMultisig_V3 {

}

abstract contract AvoMultisigCore is
    AvoMultisigErrors,
    AvoMultisigVariables,
    AvoCore,
    AvoMultisigEvents,
    IAvoMultisigV3Base
{
    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    constructor(
        IAvoVersionsRegistry avoVersionsRegistry_,
        address avoForwarder_,
        IAvoSignersList avoSignersList_,
        uint256 authorizedMinFee_,
        uint256 authorizedMaxFee_,
        address authorizedFeeCollector_
    )
        AvoMultisigVariables(
            avoVersionsRegistry_,
            avoForwarder_,
            avoSignersList_,
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

    /// @dev sets the initial state of the Multisig for `owner_` as owner and first and only required signer
    function _initialize(address owner_) internal {
        _initializeOwner(owner_);

        // set initial signers state
        requiredSigners = 1;
        address[] memory signers_ = new address[](1);
        signers_[0] = owner_;
        _setSigners(signers_); // also updates signersCount

        emit SignerAdded(owner_);

        // add owner as signer at AvoSignersList
        avoSignersList.syncAddAvoSignerMappings(address(this), signers_);
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
    /// @param  isNonSequentialNonce_ flag to sginal verify with non sequential nonce or not
    /// @return isValid_              true if the signature is valid, false otherwise
    /// @return recoveredSigners_     recovered valid signer addresses of the signatures. In case that `isValid_` is
    ///                               false, the last element in the array with a value is the invalid signer
    function _verifySig(
        bytes32 digest_,
        SignatureParams[] memory signaturesParams_,
        bool isNonSequentialNonce_
    ) internal view returns (bool isValid_, address[] memory recoveredSigners_) {
        uint256 signaturesLength_ = signaturesParams_.length;

        if (
            // enough signatures must be submitted to reach quorom of `requiredSigners`
            signaturesLength_ < requiredSigners ||
            // for non sequential nonce, if nonce is already used, the signature has already been used and is invalid
            (isNonSequentialNonce_ && nonSequentialNonces[digest_] == 1)
        ) {
            revert AvoMultisig__InvalidParams();
        }

        // fill recovered signers array for use in event emit
        recoveredSigners_ = new address[](signaturesLength_);

        // get current signers from storage
        address[] memory allowedSigners_ = _getSigners(); // includes owner
        uint256 allowedSignersLength_ = allowedSigners_.length;
        // track last allowed signer index for loop performance improvements
        uint256 lastAllowedSignerIndex_;

        bool isContract_; // keeping this variable outside the loop so it is not re-initialized in each loop -> cheaper
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
                    revert AvoMultisig__InvalidParams();
                }
            }

            bool isAllowedSigner_;
            // because signers in storage and signers from signatures input params must be ordered ascending,
            // the for loop can be optimized each new cycle to start from the position where the last signer
            // has been found.
            // this also ensures that input params signers must be ordered ascending off-chain
            // (which again is used to improve performance and simplifies ensuring unique signers)
            for (uint256 j = lastAllowedSignerIndex_; j < allowedSignersLength_; ) {
                if (allowedSigners_[j] == recoveredSigners_[i]) {
                    isAllowedSigner_ = true;
                    lastAllowedSignerIndex_ = j + 1; // set to j+1 so that next cycle starts at next array position
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
}

abstract contract AvoMultisigEIP1271 is AvoCoreEIP1271, AvoMultisigCore {
    /// @inheritdoc IERC1271
    /// @param signature This can be one of the following:
    ///         - empty: `hash` must be a previously signed message in storage then.
    ///         - a multiple of 85 bytes, through grouping of 65 bytes signature + 20 bytes signer address each.
    ///           To signal decoding this way, the signature bytes must be prefixed with `0xDEC0DE6520`.
    ///         - the `abi.encode` result for `SignatureParams` struct array.
    /// @dev reverts with `AvoCore__InvalidEIP1271Signature` or `AvoMultisig__InvalidParams` if signature is invalid.
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
            // decode signaturesParams_ from bytes signature
            SignatureParams[] memory signaturesParams_;

            uint256 signatureLength_ = signature.length;

            if (signatureLength_ < 90) {
                revert AvoCore__InvalidEIP1271Signature();
            }

            // check if signature is prefixed with "0xDEC0DE6520" (appending 000000 to get to bytes8)
            if (bytes8(signature[0:5]) == bytes8(uint64(0xdec0de6520000000))) {
                // signature after the prefix should be divisible by 85
                // (65 bytes signature and 20 bytes signer address) each

                uint256 signaturesCount_ = (signatureLength_ - 5) / 85; // -5 to not count prefix
                signaturesParams_ = new SignatureParams[](signaturesCount_);

                for (uint256 i; i < signaturesCount_; ) {
                    uint256 signerOffset_ = (i * 85) + 65 + 5; // +5 to start after prefix

                    bytes memory signerBytes_ = signature[signerOffset_:signerOffset_ + 20];
                    address signer_;
                    // cast bytes to address in the easiest way via assembly
                    assembly {
                        signer_ := shr(96, mload(add(signerBytes_, 0x20)))
                    }

                    signaturesParams_[i] = SignatureParams({
                        signature: signature[(signerOffset_ - 65):signerOffset_],
                        signer: signer_
                    });

                    unchecked {
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
                revert AvoCore__InvalidEIP1271Signature();
            }
        }

        return EIP1271_MAGIC_VALUE;
    }
}

/// @dev See contract AvoCoreSelfUpgradeable
abstract contract AvoMultisigSelfUpgradeable is AvoCoreSelfUpgradeable {
    /// @inheritdoc AvoCoreSelfUpgradeable
    function upgradeTo(address avoImplementation_) public override onlySelf {
        avoVersionsRegistry.requireValidAvoMultisigVersion(avoImplementation_);

        _avoImplementation = avoImplementation_;
        emit Upgraded(avoImplementation_);
    }
}

abstract contract AvoMultisigProtected is AvoCoreProtected {}

abstract contract AvoMultisigSigners is AvoMultisigCore {
    /// @inheritdoc IAvoMultisigV3Base
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

    /// @notice adds `addSigners_` to allowed signers
    /// Note the `addSigners_` to be added must:
    ///     - NOT be duplicates (already present in current allowed signers)
    ///     - NOT be the zero address
    ///     - be sorted ascending
    function addSigners(address[] calldata addSigners_) external onlySelf {
        uint256 addSignersLength_ = addSigners_.length;

        // check array length and make sure signers can not be zero address
        // (only check for first elem needed, rest is checked through sort)
        if (addSignersLength_ == 0 || addSigners_[0] == address(0)) {
            revert AvoMultisig__InvalidParams();
        }

        address[] memory currentSigners_ = _getSigners();
        uint256 currentSignersLength_ = currentSigners_.length;

        uint256 newSignersLength_ = currentSignersLength_ + addSignersLength_;
        if (newSignersLength_ > MAX_SIGNERS_COUNT) {
            revert AvoMultisig__InvalidParams();
        }
        address[] memory newSigners_ = new address[](newSignersLength_);

        uint256 currentSignersPos_; // index of position of loop in currentSigners_ array
        uint256 addedCount_; // keep track of number of added signers of current signers array
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
                revert AvoMultisig__InvalidParams();
            }

            unchecked {
                ++i;
            }
        }

        // update values in storage
        _setSigners(newSigners_); // automatically updates `signersCount`

        // sync mappings at AvoSignersList -> must happen *after* storage write update
        avoSignersList.syncAddAvoSignerMappings(address(this), addSigners_);
    }

    /// @notice removes `removeSigners_` from allowed signers
    /// Note the `removeSigners_` to be removed must:
    ///     - NOT be the owner
    ///     - be sorted ascending
    ///     - be present in current allowed signers
    function removeSigners(address[] calldata removeSigners_) external onlySelf {
        uint256 removeSignersLength_ = removeSigners_.length;
        if (removeSignersLength_ == 0) {
            revert AvoMultisig__InvalidParams();
        }

        address[] memory currentSigners_ = _getSigners();
        uint256 currentSignersLength_ = currentSigners_.length;

        uint256 newSignersLength_ = currentSignersLength_ - removeSignersLength_;
        if (newSignersLength_ < requiredSigners) {
            // ensure contract can not end up in an invalid state where requiredSigners > signersCount
            revert AvoMultisig__InvalidParams();
        }

        address owner_ = owner;

        address[] memory newSigners_ = new address[](newSignersLength_);

        uint256 currentInsertPos_; // index of position of loop in `newSigners_` array
        uint256 removedCount_; // keep track of number of removed signers of current signers array
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
                    revert AvoMultisig__InvalidParams();
                }
            } else {
                // remove signer, i.e. do not insert the current signer in the newSigners_ array

                // make sure signer to be removed is not the owner
                if (removeSigners_[removedCount_] == owner_) {
                    revert AvoMultisig__InvalidParams();
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
            revert AvoMultisig__InvalidParams();
        }

        // update values in storage
        _setSigners(newSigners_); // automatically updates `signersCount`

        // sync mappings at AvoSignersList -> must happen *after* storage write update
        avoSignersList.syncRemoveAvoSignerMappings(address(this), removeSigners_);
    }

    /// @notice sets number of required signers for a valid request to `requiredSigners_`
    function setRequiredSigners(uint8 requiredSigners_) external onlySelf {
        // check if number of actual signers is > `requiredSigners_` because otherwise
        // the multisig would end up in a broken state where no execution is possible anymore
        if (requiredSigners_ == 0 || requiredSigners_ > signersCount) {
            revert AvoMultisig__InvalidParams();
        }

        requiredSigners = requiredSigners_;

        emit RequiredSignersSet(requiredSigners_);
    }
}

abstract contract AvoMultisigCast is AvoMultisigCore {
    /// @inheritdoc IAvoMultisigV3Base
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

    /// @inheritdoc IAvoMultisigV3Base
    function verify(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_,
        SignatureParams[] calldata signaturesParams_
    ) external view returns (bool) {
        _validateParams(
            params_.actions.length,
            params_.avoSafeNonce,
            forwardParams_.validAfter,
            forwardParams_.validUntil
        );

        (bool validSignature_, ) = _verifySig(
            getSigDigest(params_, forwardParams_),
            signaturesParams_,
            params_.avoSafeNonce == -1
        );

        // signature must be valid
        if (!validSignature_) {
            revert AvoMultisig__InvalidSignature();
        }

        return true;
    }

    /// @inheritdoc IAvoMultisigV3Base
    function cast(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_,
        SignatureParams[] memory signaturesParams_
    ) external payable returns (bool success_, string memory revertReason_) {
        {
            if (msg.sender != avoForwarder) {
                // sender must be the allowed AvoForwarder
                revert AvoMultisig__Unauthorized();
            }

            // compare actual sent gas to user instructed gas, adding 500 to `gasleft()` for approx. already used gas
            if ((gasleft() + 500) < forwardParams_.gas) {
                // relayer has not sent enough gas to cover gas limit as user instructed.
                // this error should not be blamed on the user but rather on the relayer
                revert AvoMultisig__InsufficientGasSent();
            }

            _validateParams(
                params_.actions.length,
                params_.avoSafeNonce,
                forwardParams_.validAfter,
                forwardParams_.validUntil
            );
        }

        bytes32 digest_ = getSigDigest(params_, forwardParams_);
        address[] memory signers_;
        {
            bool validSignature_;
            (validSignature_, signers_) = _verifySig(digest_, signaturesParams_, params_.avoSafeNonce == -1);

            // signature must be valid
            if (!validSignature_) {
                revert AvoMultisig__InvalidSignature();
            }
        }

        (success_, revertReason_) = _executeCast(
            params_,
            // the gas usage for the emitting the CastExecuted/CastFailed events depends on the signers count
            // the cost per signer is PER_SIGNER_RESERVE_GAS. We calculate this dynamically to ensure
            // enough reserve gas is reserved in Multisigs with a higher signersCount
            CAST_EVENTS_RESERVE_GAS + (PER_SIGNER_RESERVE_GAS * signers_.length),
            params_.avoSafeNonce == -1 ? digest_ : bytes32(0)
        );

        // @dev on changes in the code below this point, measure the needed reserve gas via `gasleft()` anew
        // and update the reserve gas constant amounts
        if (success_ == true) {
            emit CastExecuted(params_.source, msg.sender, signers_, params_.metadata);
        } else {
            emit CastFailed(params_.source, msg.sender, signers_, revertReason_, params_.metadata);
        }
        // @dev ending point for measuring reserve gas should be here. Also see comment in `AvoCore._executeCast()`
    }
}

abstract contract AvoMultisigCastAuthorized is AvoMultisigCore {
    /// @inheritdoc IAvoMultisigV3Base
    function getSigDigestAuthorized(
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

    /// @inheritdoc IAvoMultisigV3Base
    function verifyAuthorized(
        CastParams calldata params_,
        CastAuthorizedParams calldata authorizedParams_,
        SignatureParams[] calldata signaturesParams_
    ) external view returns (bool) {
        {
            // make sure actions are defined and nonce is valid
            _validateParams(
                params_.actions.length,
                params_.avoSafeNonce,
                authorizedParams_.validAfter,
                authorizedParams_.validUntil
            );
        }

        (bool validSignature_, ) = _verifySig(
            getSigDigestAuthorized(params_, authorizedParams_),
            signaturesParams_,
            params_.avoSafeNonce == -1
        );

        // signature must be valid
        if (!validSignature_) {
            revert AvoMultisig__InvalidSignature();
        }

        return true;
    }

    /// @inheritdoc IAvoMultisigV3Base
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
                params_.avoSafeNonce,
                authorizedParams_.validAfter,
                authorizedParams_.validUntil
            );
        }

        bytes32 digest_ = getSigDigestAuthorized(params_, authorizedParams_);
        address[] memory signers_;
        {
            bool validSignature_;
            (validSignature_, signers_) = _verifySig(digest_, signaturesParams_, params_.avoSafeNonce == -1);

            // signature must be valid
            if (!validSignature_) {
                revert AvoMultisig__InvalidSignature();
            }
        }

        {
            (success_, revertReason_) = _executeCast(
                params_,
                // the gas usage for the emitting the CastExecuted/CastFailed events depends on the signers count
                // the cost per signer is PER_SIGNER_RESERVE_GAS. We calculate this dynamically to ensure
                // enough reserve gas is reserved in Multisigs with a higher signersCount
                CAST_AUTHORIZED_RESERVE_GAS + (PER_SIGNER_RESERVE_GAS * signers_.length),
                params_.avoSafeNonce == -1 ? digest_ : bytes32(0)
            );

            // @dev on changes in the code below this point, measure the needed reserve gas via `gasleft()` anew
            // and update reserve gas constant amounts
            if (success_ == true) {
                emit CastExecuted(params_.source, msg.sender, signers_, params_.metadata);
            } else {
                emit CastFailed(params_.source, msg.sender, signers_, revertReason_, params_.metadata);
            }
        }

        // @dev `_payAuthorizedFee()` costs ~24k gas for if a fee is configured and maxFee is set
        _payAuthorizedFee(gasSnapshot_, authorizedParams_.maxFee);

        // @dev ending point for measuring reserve gas should be here. Also see comment in `AvoCore._executeCast()`
    }
}

contract AvoMultisig is
    AvoMultisigCore,
    AvoMultisigSelfUpgradeable,
    AvoMultisigProtected,
    AvoMultisigEIP1271,
    AvoMultisigSigners,
    AvoMultisigCast,
    AvoMultisigCastAuthorized
{
    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    /// @notice                        constructor sets multiple immutable values for contracts and payFee fallback logic.
    /// @param avoVersionsRegistry_    address of the avoVersionsRegistry (proxy) contract
    /// @param avoForwarder_           address of the avoForwarder (proxy) contract
    ///                                to forward tx with valid signatures. must be valid version in AvoVersionsRegistry.
    /// @param avoSignersList_         address of the AvoSignersList (proxy) contract
    /// @param authorizedMinFee_       minimum for fee charged via `castAuthorized()` to charge if
    ///                                `AvoVersionsRegistry.calcFee()` would fail.
    /// @param authorizedMaxFee_       maximum for fee charged via `castAuthorized()`. If AvoVersionsRegistry
    ///                                returns a fee higher than this, then `authorizedMaxFee_` is charged as fee instead.
    /// @param authorizedFeeCollector_ address that the fee charged via `castAuthorized()` is sent to in the fallback case.
    constructor(
        IAvoVersionsRegistry avoVersionsRegistry_,
        address avoForwarder_,
        IAvoSignersList avoSignersList_,
        uint256 authorizedMinFee_,
        uint256 authorizedMaxFee_,
        address authorizedFeeCollector_
    )
        AvoMultisigCore(
            avoVersionsRegistry_,
            avoForwarder_,
            avoSignersList_,
            authorizedMinFee_,
            authorizedMaxFee_,
            authorizedFeeCollector_
        )
    {}

    /// @inheritdoc IAvoMultisigV3Base
    function initialize(address owner_) public initializer {
        _initialize(owner_);
    }

    /// @inheritdoc IAvoMultisigV3Base
    function initializeWithVersion(address owner_, address avoMultisigVersion_) public initializer {
        _initialize(owner_);

        // set current avo implementation logic address
        _avoImplementation = avoMultisigVersion_;
    }

    /***********************************|
    |            PUBLIC API             |
    |__________________________________*/

    receive() external payable {}

    /// @inheritdoc IAvoMultisigV3Base
    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IAvoMultisigV3Base
    function signers() public view returns (address[] memory signers_) {
        return _getSigners();
    }
}

