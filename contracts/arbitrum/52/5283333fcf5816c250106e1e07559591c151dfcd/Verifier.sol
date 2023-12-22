// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./MerkleProof.sol";

abstract contract Verifier {
    bytes32 immutable private root_;

    constructor(bytes32 _root) {
        // Not able to change anymore after deploying
        root_ = _root;
    }

    function _verify(
        bytes32[] memory proof,
        address addr,
        uint256 amount
    )
        internal
        virtual
        view
    {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr, amount))));
        require(MerkleProof.verify(proof, root_, leaf), "Invalid proof");
    }
}
