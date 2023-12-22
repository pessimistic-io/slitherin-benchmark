// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { AvoCoreStructs } from "./AvoCoreStructs.sol";

// @dev base interface without getters for storage variables (to avoid overloads issues)
interface IAvoWalletV3Base is AvoCoreStructs {
    /// @notice        initializer called by AvoFactory after deployment, sets the `owner_` as owner
    /// @param owner_  the owner (immutable) of this smart wallet
    function initialize(address owner_) external;

    /// @notice                   initialize contract same as `initialize()` but also sets a different
    ///                           logic contract implementation address `avoWalletVersion_`
    /// @param owner_             the owner (immutable) of this smart wallet
    /// @param avoWalletVersion_  version of AvoMultisig logic contract to initialize
    function initializeWithVersion(address owner_, address avoWalletVersion_) external;

    /// @notice returns the domainSeparator for EIP712 signature
    function domainSeparatorV4() external view returns (bytes32);

    /// @notice                    returns non-sequential nonce that will be marked as used when the request with the
    ///                            matching `params_` and `authorizedParams_` is executed via `castAuthorized()`.
    /// @param params_             Cast params such as id, avoSafeNonce and actions to execute
    /// @param authorizedParams_   Cast params related to execution through owner such as maxFee
    /// @return                    bytes32 non sequential nonce
    function nonSequentialNonceAuthorized(
        CastParams calldata params_,
        CastAuthorizedParams calldata authorizedParams_
    ) external view returns (bytes32);

    /// @notice               gets the digest (hash) used to verify an EIP712 signature
    ///
    ///                       This is also used as the non-sequential nonce that will be marked as used when the
    ///                       request with the matching `params_` and `forwardParams_` is executed via `cast()`.
    /// @param params_        Cast params such as id, avoSafeNonce and actions to execute
    /// @param forwardParams_ Cast params related to validity of forwarding as instructed and signed
    /// @return               bytes32 digest to verify signature (or used as non-sequential nonce)
    function getSigDigest(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_
    ) external view returns (bytes32);

    /// @notice                 Verify the transaction signature is valid and can be executed.
    ///                         This does not guarantuee that the tx will not revert, simply that the params are valid.
    ///                         Does not revert and returns successfully if the input is valid.
    ///                         Reverts if input params, signature or avoSafeNonce etc. are invalid.
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
    function verify(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_,
        SignatureParams calldata signatureParams_
    ) external view returns (bool);

    /// @notice                 Executes arbitrary `actions_` with valid signature. Only executable by AvoForwarder.
    ///                         If one action fails, the transaction doesn't revert, instead emits the `CastFailed` event.
    ///                         In that case, all previous actions are reverted.
    ///                         On success, emits CastExecuted event.
    /// @dev                    validates EIP712 signature then executes each action via .call or .delegatecall
    /// @param params_          Cast params such as id, avoSafeNonce and actions to execute
    /// @param forwardParams_   Cast params related to validity of forwarding as instructed and signed
    /// @param signatureParams_ struct for signature and signer:
    ///                         - signature: the EIP712 signature, 65 bytes ECDSA signature for a default EOA.
    ///                           For smart contract signatures it must fulfill the requirements for the relevant
    ///                           smart contract `.isValidSignature()` EIP1271 logic
    ///                         - signer: address of the signature signer.
    ///                           Must match the actual signature signer or refer to the smart contract
    ///                           that must be an allowed signer and validates signature via EIP1271
    /// @return success         true if all actions were executed succesfully, false otherwise.
    /// @return revertReason    revert reason if one of the actions fails in the following format:
    ///                         The revert reason will be prefixed with the index of the action.
    ///                         e.g. if action 1 fails, then the reason will be "1_reason".
    ///                         if an action in the flashloan callback fails (or an otherwise nested action),
    ///                         it will be prefixed with with two numbers: "1_2_reason".
    ///                         e.g. if action 1 is the flashloan, and action 2 of flashloan actions fails,
    ///                         the reason will be 1_2_reason.
    function cast(
        CastParams calldata params_,
        CastForwardParams calldata forwardParams_,
        SignatureParams calldata signatureParams_
    ) external payable returns (bool success, string memory revertReason);

    /// @notice                  Executes arbitrary `actions_` through authorized transaction sent by owner.
    ///                          Includes a fee in native network gas token, amount depends on registry `calcFee()`.
    ///                          If one action fails, the transaction doesn't revert, instead emits the `CastFailed` event.
    ///                          In that case, all previous actions are reverted.
    ///                          On success, emits CastExecuted event.
    /// @dev                     executes a .call or .delegateCall for every action (depending on params)
    /// @param params_           Cast params such as id, avoSafeNonce and actions to execute
    /// @param authorizedParams_ Cast params related to execution through owner such as maxFee
    /// @return success          true if all actions were executed succesfully, false otherwise.
    /// @return revertReason     revert reason if one of the actions fails in the following format:
    ///                          The revert reason will be prefixed with the index of the action.
    ///                          e.g. if action 1 fails, then the reason will be "1_reason".
    ///                          if an action in the flashloan callback fails (or an otherwise nested action),
    ///                          it will be prefixed with with two numbers: "1_2_reason".
    ///                          e.g. if action 1 is the flashloan, and action 2 of flashloan actions fails,
    ///                          the reason will be 1_2_reason.
    function castAuthorized(
        CastParams calldata params_,
        CastAuthorizedParams calldata authorizedParams_
    ) external payable returns (bool success, string memory revertReason);

    /// @notice checks if an address `authority_` is an allowed authority (returns true if allowed)
    function isAuthority(address authority_) external view returns (bool);
}

// @dev full interface with some getters for storage variables
interface IAvoWalletV3 is IAvoWalletV3Base {
    /// @notice AvoWallet Owner
    function owner() external view returns (address);

    /// @notice Domain separator name for signatures
    function DOMAIN_SEPARATOR_NAME() external view returns (string memory);

    /// @notice Domain separator version for signatures
    function DOMAIN_SEPARATOR_VERSION() external view returns (string memory);

    /// @notice incrementing nonce for each valid tx executed (to ensure uniqueness)
    function avoSafeNonce() external view returns (uint88);
}

