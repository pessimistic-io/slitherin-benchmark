// SPDX-License-Identifier: bsl-1.1

pragma solidity ^0.8.0;

import "./IVersioned.sol";
import "./IProofFeedsCommons.sol";


interface IProofFeeds is IVersioned, IProofFeedsCommons {

    struct CheckedData {
        bytes32[] merkleTreeProof;
        string metricName;
        uint256 metricValue;
        uint32 metricUpdateTs;
    }

    function requireValidProof(
        SignedMerkleTreeRoot memory signedMerkleTreeRoot_,
        CheckedData memory checkedData_
    ) external view;

    function isProofValid(
        SignedMerkleTreeRoot memory signedMerkleTreeRoot_,
        CheckedData memory checkedData_
    ) external view returns (bool);
}

