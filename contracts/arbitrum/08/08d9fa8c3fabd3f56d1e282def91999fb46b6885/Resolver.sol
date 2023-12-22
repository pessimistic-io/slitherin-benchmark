// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SchemaResolver} from "./SchemaResolver.sol";
import {Attestation, IEAS} from "./IEAS.sol";
import {OnChainCredential} from "./Credential.sol";

contract Resolver is SchemaResolver {
    /// @notice Stores the address of a whitelisted attester
    address public attester;
    address public owner;

    error ValueMismatch();
    error InvalidCaller();

    constructor(IEAS eas) SchemaResolver(eas) {
        attester = msg.sender;
        owner = msg.sender;
    }

    /// @notice Updates the attester for future
    /// @param newAttester The new attester address to be set in the contract state.

    function updateAttester(address newAttester) external {
        if (msg.sender != owner) revert InvalidCaller();
        attester = newAttester;
    }

    function getEAS() external view returns (IEAS) {
        return _eas;
    }

    /// @notice Called by EAS Contracts if a schema has resolver set while attesting.
    /// @param attestation The attestation calldata forwarded by EAS Contracts.
    /// @return returns bool to have custom logic to accept or reject an attestation.

    function onAttest(
        Attestation calldata attestation,
        uint256 /**value**/
    ) internal virtual override returns (bool) {
        if (attestation.attester != attester) revert InvalidCaller();
        (
            string memory nft_metadata_ipfs_url,
            string memory user_uuid,
            string memory credential_uuid,
            string memory hackathon_uuid,
            string memory user_hackathon_credential_uuid,
            address nft_contract
        ) = abi.decode(
                attestation.data,
                (string, string, string, string, string, address)
            );

        OnChainCredential credential_contract = OnChainCredential(nft_contract);

        credential_contract.mint(nft_metadata_ipfs_url, attestation.recipient);

        return true;
    }

    /// @notice Called by EAS Contracts if a schema has resolver set while revoking attestations.
    /// @param attestation The attestation calldata forwarded by EAS Contracts.
    /// @return returns bool to have custom logic to accept or reject a revoke request.

    function onRevoke(
        Attestation calldata attestation,
        uint256 /*value*/
    ) internal virtual override returns (bool) {
        return attestation.attester == attester;
    }

    function isPayable() public pure virtual override returns (bool) {
        return false;
    }

    function updateOwner(address newOwner) external {
        if (msg.sender != owner) revert InvalidCaller();
        owner = newOwner;
    }
}

