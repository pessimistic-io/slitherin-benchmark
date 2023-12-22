// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IExtension} from "./IExtension.sol";

abstract contract Extension is IExtension {
    constructor() {
        getAllSignatures(); // verify selectors properly synced
    }

    /// @inheritdoc IExtension
    function signatureOf(bytes4 selector) public pure virtual returns (string memory signature) {}

    /// @inheritdoc IExtension
    function getAllSelectors() public pure virtual returns (bytes4[] memory selectors) {}

    /// @inheritdoc IExtension
    function getAllSignatures() public pure returns (string[] memory signatures) {
        bytes4[] memory selectors = getAllSelectors();
        uint256 len = selectors.length;
        signatures = new string[](len);
        for (uint256 i; i < len; i++) {
            bytes4 selector = selectors[i];
            string memory signature = signatureOf(selector);
            require(bytes4(keccak256(abi.encodePacked(signature))) == selector, "SELECTOR_SIGNATURE_MISMATCH");
            signatures[i] = signature;
        }
    }
}

