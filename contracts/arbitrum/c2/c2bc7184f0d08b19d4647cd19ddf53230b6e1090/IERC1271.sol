// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes memory signature)
        external
        view
        returns (bytes4);
}

