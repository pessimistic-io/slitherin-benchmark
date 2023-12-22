// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IVerifier.sol";
import "./IExtensionVerifier10.sol";

contract ExtensionVerifier10x02 is IVerifier {
    IExtensionVerifier10 public immutable extensionVerifier10;
    uint16 constant inputAmount = 22;

    constructor(address extensionVerifier10Instance) {
        extensionVerifier10 = IExtensionVerifier10(extensionVerifier10Instance);
    }

    function verifyProof(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[] memory input,
        uint256
    ) external view returns (bool) {
        uint256[inputAmount] memory fixedInput;
        for (uint16 i = 0; i < input.length; i++) {
            fixedInput[i] = input[i];
        }
        return extensionVerifier10.verifyProof(a, b, c, fixedInput);
    }
}

