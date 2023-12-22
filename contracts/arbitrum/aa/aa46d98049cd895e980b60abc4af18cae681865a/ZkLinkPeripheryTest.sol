pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT OR Apache-2.0



import "./ZkLinkPeriphery.sol";

contract ZkLinkPeripheryTest is ZkLinkPeriphery {

    function setGovernor(address governor) external {
        networkGovernor = governor;
    }

    function setAcceptor(uint32 accountId, bytes32 hash, address acceptor) external {
        accepts[accountId][hash] = acceptor;
    }

    function getAcceptor(uint32 accountId, bytes32 hash) external view returns (address) {
        return accepts[accountId][hash];
    }

    function mockProveBlock(StoredBlockInfo memory storedBlockInfo) external {
        storedBlockHashes[storedBlockInfo.blockNumber] = hashStoredBlockInfo(storedBlockInfo);
        totalBlocksProven = storedBlockInfo.blockNumber;
    }

    function getAuthFact(address account, uint32 nonce) external view returns (bytes32) {
        return authFacts[account][nonce];
    }

    function setTotalOpenPriorityRequests(uint64 _totalOpenPriorityRequests) external {
        totalOpenPriorityRequests = _totalOpenPriorityRequests;
    }

    function setSyncProgress(bytes32 syncHash, uint256 progress) external {
        synchronizedChains[syncHash] = progress;
    }
}

