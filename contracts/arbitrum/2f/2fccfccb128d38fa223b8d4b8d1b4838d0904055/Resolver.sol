// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {SchemaResolver} from "./SchemaResolver.sol";
import {Attestation, IEAS} from "./IEAS.sol";
import "./ERC20.sol";

contract Resolver is SchemaResolver {
    /// @notice Stores the address of a whitelisted attester
    address public attester;

    struct BuilderStruct {
        string username;
        address wallet_address;
    }

    struct StickerStruct {
        string name;
        uint8 quantity;
    }

    error ValueMismatch();

    constructor(IEAS eas) SchemaResolver(eas) {
        attester = msg.sender;
    }

    /// @notice Updates the attester for future
    /// @param newAttester The new attester address to be set in the contract state.

    function updateAttester(address newAttester) external {
        if (msg.sender != attester) revert();
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
        uint256 value
    ) internal virtual override returns (bool) {
        if (attestation.attester != attester) revert();

        /// @notice Decode the attestation data
        (
            string memory project_uuid,
            string memory user_uuid,
            string memory project_contribution_uuid,
            BuilderStruct[] memory builders,
            string memory message,
            StickerStruct[] memory stickers,
            address token_address,
            uint256 attestation_value
        ) = abi.decode(
                attestation.data,
                (
                    string,
                    string,
                    string,
                    BuilderStruct[],
                    string,
                    StickerStruct[],
                    address,
                    uint256
                )
            );

        /// @notice Variables used to split the tokens amonst the
        /// builders
        address recipient = attestation.recipient;
        uint length = builders.length;
        uint amount = attestation_value / length;
        /// @notice This variable is used to return any remaining ETH
        /// back to the sender
        uint unused = attestation_value;

        if (token_address == address(0)) {
            /// @notice If the value does not match the attestation value
            /// revert with an error
            if (value != attestation_value) revert ValueMismatch();

            for (uint i = 0; i < length; ) {
                /// @notice Transfer the ether to the wallet addresses of the
                /// of the builders
                ///
                /// This is the cheapest way to transfer the ETH
                ///
                /// @reference https://solidity-by-example.org/sending-ether/
                (bool s, ) = address(builders[i].wallet_address).call{
                    value: amount
                }("");
                if (!s) revert();

                unused -= amount;

                unchecked {
                    i++;
                }
            }

            /// @notice Return unused ETH back to the sender
            if (unused > 0) payable(recipient).transfer(unused);
        } else {
            ERC20 token = ERC20(token_address);

            for (uint i = 0; i < length; ) {
                /// @notice Send the token amount to the builders
                token.transferFrom(
                    recipient,
                    builders[i].wallet_address,
                    amount
                );

                unchecked {
                    i++;
                }
            }
        }

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

    function owner() external view returns (address) {
        return attester;
    }

    function isPayable() public pure virtual override returns (bool) {
        return true;
    }
}

