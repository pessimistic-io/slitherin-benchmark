// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./IVerifierFacade.sol";

contract VerifierFacade is IVerifierFacade, Ownable {
    mapping(uint256 => IVerifier) public verifierMap;

    constructor() {
    }

    function registerVerifier(uint256 verifierId, address verifierAddress) external onlyOwner {
        verifierMap[verifierId] = IVerifier(verifierAddress);
        emit VerifierRegistered(
            verifierId,
            verifierAddress
        );
    }

    function removeVerifier(uint256 verifierId) external onlyOwner {
        delete verifierMap[verifierId];
        emit VerifierRemoved(verifierId);
    }

    function verifyProof(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[] memory input,
        uint256 verifierId
    ) external view returns (bool) {
        IVerifier verifier = verifierMap[verifierId];
        require(address(verifier) != address(0), "Cannot find appropriate verifier");
        return verifier.verifyProof(a, b, c, input, verifierId);
    }
}

