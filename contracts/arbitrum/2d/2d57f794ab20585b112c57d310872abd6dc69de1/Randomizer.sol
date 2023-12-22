//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AdminableUpgradeable.sol";
import "./IRandomizer.sol";
import "./RandomizerState.sol";

// Single implementation of randomizer. Currently does not use ChainLink VRF as CL is not supported on Arbitrum.
// When CL supports Arbitrum, the goal is to switch this contract to use VRF.
// Open for all to use.
contract Randomizer is IRandomizer, RandomizerState {

    function initialize() external initializer {
        RandomizerState.__RandomizerState_init();
    }

    function setNumBlocksAfterIncrement(uint8 _numBlocksAfterIncrement) external override onlyAdminOrOwner {
        numBlocksAfterIncrement = _numBlocksAfterIncrement;
    }

    function setNumBlocksUntilNextIncrement(uint8 _numBlocksUntilNextIncrement) external onlyAdminOrOwner {
        numBlocksUntilNextIncrement = _numBlocksUntilNextIncrement;
    }

    function incrementCommitId() external override onlyAdminOrOwner {
        require(pendingCommits > 0, "No pending requests");
        _incrementCommitId();
    }

    function addRandomForCommit(uint256 _seed) external override onlyAdminOrOwner {
        require(block.number >= lastIncrementBlockNum + numBlocksAfterIncrement, "No random on same block");
        require(commitId > nextCommitIdToSeed, "Commit id must be higher");

        commitIdToRandomSeed[nextCommitIdToSeed] = _seed;

        emit RandomSeeded(nextCommitIdToSeed);

        nextCommitIdToSeed++;
    }

    function requestRandomNumber() external override returns(uint256) {
        uint256 _requestId = requestIdCur;

        requestIdToCommitId[_requestId] = commitId;

        requestIdCur++;
        pendingCommits++;

        emit RandomRequest(_requestId, commitId);

        // If not caught up on seeding, don't bother pushing the commit id foward.
        // Will save us gas later.
        if(commitId == nextCommitIdToSeed
            && numBlocksUntilNextIncrement > 0
            && lastIncrementBlockNum + numBlocksUntilNextIncrement <= block.number)
        {
            _incrementCommitId();
        }

        return _requestId;
    }

    function _incrementCommitId() private {
        commitId++;
        lastIncrementBlockNum = block.number;
        pendingCommits = 0;
    }

    function revealRandomNumber(uint256 _requestId) external view override returns(uint256) {
        uint256 _commitIdForRequest = requestIdToCommitId[_requestId];
        require(_commitIdForRequest > 0, "Bad request ID");

        uint256 _randomSeed = commitIdToRandomSeed[_commitIdForRequest];
        require(_randomSeed > 0, "Random seed not set");

        // Combine the seed with the request id so each request id on this commit has a different number
        uint256 randomNumber = uint256(keccak256(abi.encode(_randomSeed, _requestId)));

        return randomNumber;
    }

    function isRandomReady(uint256 _requestId) external view override returns(bool) {
        return commitIdToRandomSeed[requestIdToCommitId[_requestId]] != 0;
    }
}
