// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeStorageV1} from "./OrangeStorageV1.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {IOrangeAlphaParameters} from "./IOrangeAlphaParameters.sol";
import {ErrorsV1} from "./ErrorsV1.sol";

abstract contract OrangeValidationChecker is OrangeStorageV1 {
    using SafeERC20 for IERC20;

    /* ========== MODIFIER ========== */
    modifier Allowlisted(bytes32[] calldata merkleProof) {
        _validateSenderAllowlisted(msg.sender, merkleProof);
        _;
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _validateSenderAllowlisted(address _account, bytes32[] calldata _merkleProof) internal view {
        if (params.allowlistEnabled()) {
            if (!MerkleProof.verify(_merkleProof, params.merkleRoot(), keccak256(abi.encodePacked(_account)))) {
                revert(ErrorsV1.MERKLE_ALLOWLISTED);
            }
        }
    }
}

