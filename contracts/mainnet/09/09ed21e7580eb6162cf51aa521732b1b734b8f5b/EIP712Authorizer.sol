// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./draft-EIP712.sol";
import "./ECDSA.sol";
import "./AuthorizeAccess.sol";

/** @title EIP712Authorizer.
 */
contract EIP712Authorizer is AuthorizeAccess, EIP712 {
    using ECDSA for bytes32;

    constructor(string memory eipName_, string memory eipVersion_) EIP712(eipName_, eipVersion_) {}

    /**
     * @notice verifify signature is valid for `structHash` and signers is a member of role `AUTHORIZER_ROLE`
     * @param structHash: hash of the structure to verify the signature against
     */
    function isAuthorized(bytes32 structHash, bytes memory signature) internal view returns (bool) {
        bytes32 hash = _hashTypedDataV4(structHash);
        (address recovered, ECDSA.RecoverError error) = ECDSA.tryRecover(hash, signature);
        if (error == ECDSA.RecoverError.NoError && hasRole(AUTHORIZER_ROLE, recovered)) {
            return true;
        }

        return false;
    }
}

