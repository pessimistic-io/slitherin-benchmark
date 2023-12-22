// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdminableUpgradeable.sol";

contract RandomizerState is Initializable, AdminableUpgradeable {

    event RandomRequest(uint256 indexed _requestId, uint256 indexed _commitId);
    event RandomSeeded(uint256 indexed _commitId);

    // RandomIds that are a part of this commit.
    mapping(uint256 => uint256) internal commitIdToRandomSeed;
    mapping(uint256 => uint256) internal requestIdToCommitId;

    uint256 public lastIncrementBlockNum;
    uint256 public commitId;
    uint256 public requestIdCur;
    uint256 public nextCommitIdToSeed;
    uint256 public pendingCommits;
    uint8 public numBlocksAfterIncrement;

    function __RandomizerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        numBlocksAfterIncrement = 1;
        requestIdCur = 1;
        nextCommitIdToSeed = 1;
        commitId = 1;
    }
}
