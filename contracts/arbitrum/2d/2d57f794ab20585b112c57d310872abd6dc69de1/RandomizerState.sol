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
    // The number of blocks after the increment ID was incremeneted that the seed must be supplied after
    uint8 public numBlocksAfterIncrement;
    // The number of blocks between the last increment and the next time the commit will be incremented.
    // This only applies to other contracts requesting a random, and us piggy backing of of
    // their request to increment the ID.
    uint8 public numBlocksUntilNextIncrement;

    function __RandomizerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        numBlocksAfterIncrement = 1;
        requestIdCur = 1;
        nextCommitIdToSeed = 1;
        commitId = 1;
        numBlocksUntilNextIncrement = 0;
    }
}
