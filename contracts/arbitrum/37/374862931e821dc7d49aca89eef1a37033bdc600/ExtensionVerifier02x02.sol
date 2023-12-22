// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IVerifier.sol";
import "./IExtensionVerifier2.sol";

contract ExtensionVerifier02x02 is IVerifier {
    IExtensionVerifier2 public immutable extensionVerifier2;
    uint16 constant inputAmount = 14;

    constructor(address extensionVerifier2Instance) {
        extensionVerifier2 = IExtensionVerifier2(extensionVerifier2Instance);
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
        return extensionVerifier2.verifyProof(a, b, c, fixedInput);
    }
}

