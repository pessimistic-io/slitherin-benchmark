// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ECDSAUpgradeable.sol";

library Signature {
    using ECDSAUpgradeable for bytes32;

    function validateSignature(
        bytes32 hash,
        bytes calldata signature,
        address signer
    ) internal pure {
        bool isValid = hash.recover(signature) == signer;
        require(isValid, "Signature: invalid");
    }

    /**
     * @dev Wraps a message hash into the ERC191 standard.
     * @param hash The message hash to parse.
     */
    function getERC191Message(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    bytes1(0x19),
                    bytes1("E"),
                    bytes("thereum Signed Message:\n32"),
                    hash
                )
            );
    }
}

