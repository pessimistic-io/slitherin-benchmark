// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ITerm, IAgreementManager} from "./ITerm.sol";

/// @notice Signature lines for Agreement.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/Signatures.sol)
interface ISignatures is ITerm {
    struct SignatureLine {
        IAgreementManager manager;
        uint256 tokenId;
        bytes32 agreementHash;
    }

    error Signatures__Duplicate();
    error Signatures__NotSigner();
    error Signatures__AlreadySigned();
    error Signatures__InvalidSignature();

    event Signed(
        IAgreementManager indexed manager,
        uint256 indexed tokenId,
        address indexed signer,
        SignatureLine signatureLine,
        bytes signature,
        string note
    );

    function signed(
        IAgreementManager manager,
        uint256 tokenId,
        address signer
    ) external view returns (bool);

    /// @notice Sign agreement
    /// @dev Can be called by any account
    function submitSignature(
        address signer,
        SignatureLine calldata signatureLine,
        bytes calldata signature,
        string calldata note
    ) external;

    /// @notice Hash agreement struct
    function hashSignatureLine(SignatureLine calldata signatureLine) external view returns (bytes32);
}

