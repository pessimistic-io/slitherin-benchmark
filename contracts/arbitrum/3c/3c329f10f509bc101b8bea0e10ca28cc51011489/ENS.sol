// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Ownable} from "./Ownable.sol";
import "./IENSRegistry.sol";

contract ENS is Ownable {
    string public ensName;
    bytes32 ensNameHash;
    address public ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

    constructor(string memory _ensName) {
        ensName = _ensName;
        ensNameHash = computeNamehash(_ensName);
    }

    function computeNamehash(string memory _name) public pure returns (bytes32 namehash) {
        namehash = 0x0000000000000000000000000000000000000000000000000000000000000000;
        namehash = keccak256(
            abi.encodePacked(namehash, keccak256(abi.encodePacked('eth')))
        );
        namehash = keccak256(
            abi.encodePacked(namehash, keccak256(abi.encodePacked(_name)))
        );
    }

    function _grantSubdomain(string memory _subName, address recipient) internal {
        bytes32 subName = keccak256(abi.encodePacked(_subName));
        IENSRegistry(ENS_REGISTRY).setSubnodeOwner(ensNameHash, subName, recipient);
    }

    function setEnsName(string memory _newEnsName) external onlyOwner {
        ensName = _newEnsName;
        ensNameHash = computeNamehash(_newEnsName);
    }

    function transferOwner(address _newOwner) external onlyOwner {
        IENSRegistry(ENS_REGISTRY).setOwner(ensNameHash, _newOwner);
    }
}
