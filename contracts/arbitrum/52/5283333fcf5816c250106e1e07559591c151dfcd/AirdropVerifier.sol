// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./MerkleProof.sol";

abstract contract AirdropVerifier {
    bytes32 immutable private airdropRoot_;

    constructor(bytes32 _root) {
        // Not able to change anymore after deploying
        airdropRoot_ = _root;
    }

    function _airdropVerify(
        bytes32[] memory proof,
        address addr
    )
        internal
        virtual
        view
    {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        require(MerkleProof.verify(proof, airdropRoot_, leaf), "Invalid proof");
    }
}
