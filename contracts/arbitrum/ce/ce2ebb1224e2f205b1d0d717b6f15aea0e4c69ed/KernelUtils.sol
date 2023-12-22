// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

error TargetNotAContract(address target_);
error InvalidKeycode(bytes5 keycode_);
error InvalidRole(bytes32 role_);

function ensureContract(address target_) view {
    if (target_.code.length == 0) revert TargetNotAContract(target_);
}

function ensureValidKeycode(bytes5 keycode_) pure {
    for (uint256 i = 0; i < 5; ) {
        bytes1 char = keycode_[i];

        if (char < 0x41 || char > 0x5A) revert InvalidKeycode(keycode_); // A-Z only

        unchecked {
            i++;
        }
    }
}

function ensureValidRole(bytes32 role_) pure {
    for (uint256 i = 0; i < 32; ) {
        bytes1 char = role_[i];
        if ((char < 0x61 || char > 0x7A) && char != 0x00) {
            revert InvalidRole(role_); // a-z only
        }
        unchecked {
            i++;
        }
    }
}

