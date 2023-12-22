// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IBlockUpdater.sol";
import "./ScaleCodec.sol";
import "./MerkleProof.sol";
import "./EthBlockVerifier.sol";
import "./EthSyncCommitteeVerifier.sol";

contract EthBlockUpdater is IBlockUpdater, EthBlockVerifier, EthSyncCommitteeVerifier, MerkleProof, Initializable, OwnableUpgradeable {
    event ImportSyncCommitteeRoot(uint64 indexed period, bytes32 indexed syncCommitteeRoot);
    event ModBlockConfirmation(uint256 oldBlockConfirmation, uint256 newBlockConfirmation);

    struct SyncCommitteeInput {
        uint64 period;
        bytes32 syncCommitteeRoot;
        bytes32 nextSyncCommitteeRoot;
    }

    struct BlockInput {
        uint64 slot;
        bytes32 syncCommitteeRoot;
        bytes32 receiptHash;
        bytes32 blockHash;
        uint256 blockConfirmation;
    }

    struct SyncCommitteeProof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[3] inputs;
    }

    struct BlockProof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[7] inputs;
    }

    struct Chain {
        uint64 slot;
        uint64 proposerIndex;
        bytes32 parentRoot;
        bytes32 stateRoot;
        bytes32 bodyRoot;
        bytes32 domain;
        bytes32 blockHash;
        bytes32 receiptRoot;
        bytes32 payloadHash;
        bytes32[] receiptBranch;
        bytes32[] payloadBranch;
        bytes32[] bodyBranch;
        bytes32[] headerBranch;
        bytes32[] blockHashBranch;
    }

    // period=>syncCommitteeRoot
    mapping(uint64 => bytes32) public syncCommitteeRoots;

    // blockHash=>receiptsRoot =>BlockConfirmation
    mapping(bytes32 => mapping(bytes32 => uint256)) public blockInfos;

    uint256 public minBlockConfirmation;

    uint64 public currentPeriod;

    function initialize(uint64 period, bytes32 syncCommitteeRoot, uint256 _minBlockConfirmation) public initializer {
        __Ownable_init();
        currentPeriod = period;
        syncCommitteeRoots[period] = syncCommitteeRoot;
        minBlockConfirmation = _minBlockConfirmation;
    }

    function importNextSyncCommittee(bytes calldata _proof) external {
        SyncCommitteeProof memory proofData;
        (proofData.a, proofData.b, proofData.c, proofData.inputs) = abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2], uint256[3]));
        SyncCommitteeInput memory input = _parseInput(proofData.inputs);

        uint64 nextPeriod = input.period + 1;
        require(syncCommitteeRoots[input.period] == input.syncCommitteeRoot, "invalid syncCommitteeRoot");
        require(syncCommitteeRoots[nextPeriod] == bytes32(0), "nextSyncCommitteeRoot already exist");

        uint256[1] memory compressInput;
        compressInput[0] = _hashInput(proofData.inputs);
        require(verifyCommitteeProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");
        syncCommitteeRoots[nextPeriod] = input.nextSyncCommitteeRoot;
        currentPeriod = nextPeriod;
        emit ImportSyncCommitteeRoot(nextPeriod, input.nextSyncCommitteeRoot);
    }

    function importBlock(bytes calldata _proof) external {
        BlockProof memory proofData;
        (proofData.a, proofData.b, proofData.c, proofData.inputs) = abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2], uint256[7]));
        BlockInput memory parsedInput = _parseInput(proofData.inputs);

        require(parsedInput.blockConfirmation >= minBlockConfirmation, "Not enough block confirmations");
        (bool exist,uint256 blockConfirmation) = _checkBlock(parsedInput.blockHash, parsedInput.receiptHash);
        if (exist && parsedInput.blockConfirmation <= blockConfirmation) {
            revert("already exist");
        }
        uint64 period = _computeSyncCommitteePeriod(parsedInput.slot);
        require(syncCommitteeRoots[period] == parsedInput.syncCommitteeRoot, "invalid committeeRoot");

        uint256[1] memory compressInput;
        compressInput[0] = _hashInput(proofData.inputs);
        require(verifyBlockProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");

        blockInfos[parsedInput.blockHash][parsedInput.receiptHash] = parsedInput.blockConfirmation;
        emit ImportBlock(parsedInput.slot, parsedInput.blockHash, parsedInput.receiptHash);
    }

    function checkBlock(bytes32 _blockHash, bytes32 _receiptHash) external view returns (bool) {
        (bool exist,) =  _checkBlock(_blockHash, _receiptHash);
        return exist;
    }

    function checkBlockConfirmation(bytes32 _blockHash, bytes32 _receiptHash) external view returns (bool, uint256) {
        return _checkBlock(_blockHash, _receiptHash);
    }

    function submitBlockChain(Chain[] calldata blockChains) external {
        require(blockChains.length > 1, "invalid chain length");
        uint256 firstBlockConfirmation;
        for (uint i = 0; i < blockChains.length; i++) {
            Chain memory blockChain = blockChains[i];
            bytes32[] memory leaves = new bytes32[](5);
            leaves[0] = bytes32(_toLittleEndian64(blockChain.slot));
            leaves[1] = bytes32(_toLittleEndian64(blockChain.proposerIndex));
            leaves[2] = blockChain.parentRoot;
            leaves[3] = blockChain.stateRoot;
            leaves[4] = blockChain.bodyRoot;
            bytes32 headerHash = merkleRoot(leaves);
            if (i == 0) {
                (bool exist,uint256 blockConfirmation) = _checkBlock(blockChain.blockHash, blockChain.receiptRoot);
                require(exist, "invalid proof");
                firstBlockConfirmation = blockConfirmation;
            } else {
                require(headerHash == blockChains[i - 1].parentRoot, "invalid proof");
            }
            require(isValidMerkleBranch(blockChain.receiptBranch, blockChain.receiptRoot, blockChain.payloadHash, 3, 4), "invalid receiptBranch");
            require(isValidMerkleBranch(blockChain.payloadBranch, blockChain.payloadHash, blockChain.bodyRoot, 9, 4), "invalid payloadBranch");
            require(isValidMerkleBranch(blockChain.blockHashBranch, blockChain.blockHash, blockChain.payloadHash, 12, 4), "invalid headerBranch");
            if (i != 0) {
                blockInfos[blockChain.blockHash][blockChain.receiptRoot] = firstBlockConfirmation + i;
                emit ImportBlock(blockChain.slot, blockChain.blockHash, blockChain.receiptRoot);
            }
        }
    }

    function _checkBlock(bytes32 _blockHash, bytes32 _receiptHash) internal view returns (bool, uint256) {
        uint256 blockConfirmation = blockInfos[_blockHash][_receiptHash];
        if (blockConfirmation > 0) {
            return (true, blockConfirmation);
        }
        return (false, blockConfirmation);
    }

    function _toLittleEndian64(uint64 value) internal pure returns (bytes8) {
        return ScaleCodec.encode64(value);
    }

    function _parseInput(uint256[3] memory _inputs) internal pure returns (SyncCommitteeInput memory) {
        SyncCommitteeInput memory result;
        result.syncCommitteeRoot = bytes32(_inputs[0]);
        result.nextSyncCommitteeRoot = bytes32(_inputs[1]);
        result.period = uint64(_inputs[2]);
        return result;
    }

    function _parseInput(uint256[7] memory _inputs) internal pure returns (BlockInput memory) {
        BlockInput memory result;
        result.slot = uint64(_inputs[0]);
        result.syncCommitteeRoot = bytes32(_inputs[1]);
        result.receiptHash = bytes32((_inputs[2] << 128) | _inputs[3]);
        result.blockHash = bytes32((_inputs[4] << 128) | _inputs[5]);
        result.blockConfirmation = _inputs[6];
        return result;
    }

    function _hashInput(uint256[3] memory _inputs) internal pure returns (uint256) {
        uint256 computedHash = uint256(keccak256(abi.encodePacked(_inputs[0], _inputs[1], _inputs[2])));
        return computedHash / 256;
    }

    function _hashInput(uint256[7] memory _inputs) internal pure returns (uint256) {
        uint256 computedHash = uint256(keccak256(abi.encodePacked(_inputs[0], _inputs[1], _inputs[2], _inputs[3], _inputs[4], _inputs[5], _inputs[6])));
        return computedHash / 256;
    }

    function _computeSyncCommitteePeriod(uint64 slot) internal pure returns (uint64) {
        return slot / 32 / 256;
    }

    //----------------------------------------------------------------------------------
    // onlyOwner
    function setBlockConfirmation(uint256 _minBlockConfirmation) external onlyOwner {
        emit ModBlockConfirmation(minBlockConfirmation, _minBlockConfirmation);
        minBlockConfirmation = _minBlockConfirmation;
    }
}

