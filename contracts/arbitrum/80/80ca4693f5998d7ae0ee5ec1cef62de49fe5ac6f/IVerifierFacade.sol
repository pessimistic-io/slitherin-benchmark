// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import "./IVerifier.sol";

interface IVerifierFacade is IVerifier {
    event VerifierRegistered(uint256 verifierId, address verifierAddress);
    event VerifierRemoved(uint256 verifierId);
    function registerVerifier(uint256 verifierId, address verifierAddress) external;
    function removeVerifier(uint256 verifierId) external;
}

