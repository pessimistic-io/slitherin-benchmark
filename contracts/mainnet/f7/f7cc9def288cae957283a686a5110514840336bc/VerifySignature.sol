// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ECDSA.sol";
import "./MerkleProof.sol";
import "./YeyeTrait.sol";

library VerifySignature {
    using ECDSA for bytes32;

    function verify(address signer, bytes32 hash, bytes calldata signature) internal pure returns (bool) {
        return hash.toEthSignedMessageHash().recover(signature) == signer;
    }

    function redeem(uint256 _oldId, uint256 _newId, uint256 _base, YeyeTrait.TraitKey[] calldata _traits, uint _total, uint ticketID, address _signer, bytes calldata sig) internal pure returns (bool) {
        bytes32 hash = keccak256(abi.encode(_oldId, _newId, _base, _traits, _total, ticketID));
        return verify(_signer, hash, sig);
    }

    function equip(uint256 _oldId, uint256 _newId, uint256 _base, uint256[] calldata _traits, uint256[] calldata _untraits, address _signer, bytes calldata sig) internal pure returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(_oldId, _newId, _base, _traits, _untraits));
        return verify(_signer, hash, sig);
    }
}
