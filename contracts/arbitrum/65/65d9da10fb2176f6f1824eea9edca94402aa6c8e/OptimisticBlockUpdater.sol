// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IBlockUpdater.sol";
import "./ICircuitVerifier.sol";

contract OptimisticBlockUpdater is IBlockUpdater, Initializable, OwnableUpgradeable {
    event ImportSyncCommitteeRoot(uint64 indexed period, bytes32 indexed syncCommitteeRoot);
    event ModBlockConfirmation(uint256 oldBlockConfirmation, uint256 newBlockConfirmation);

    struct SyncCommitteeInput {
        uint64 period;
        bytes32 syncCommitteeRoot;
        bytes32 nextSyncCommitteeRoot;
    }

    struct BlockInput {
        uint256[16] blockNumber;
        uint256 blockConfirmation;
        bytes32 syncCommitteeRoot;
        bytes32[16] receiptHash;
        bytes32[16] blockHash;
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
        uint256[] inputs;
    }

    // period=>syncCommitteeRoot
    mapping(uint256 => bytes32) public syncCommitteeRoots;

    // blockHash=>receiptsRoot =>BlockConfirmation
    mapping(bytes32 => mapping(bytes32 => uint256)) public blockInfos;

    ICircuitVerifier public blockVerifier;

    ICircuitVerifier public committeeVerifier;

    uint256 public minBlockConfirmation;

    uint64 public currentPeriod;

    function initialize(uint64 period, bytes32 syncCommitteeRoot, uint256 _minBlockConfirmation) public initializer {
        __Ownable_init();
        currentPeriod = period;
        syncCommitteeRoots[period] = syncCommitteeRoot;
        minBlockConfirmation = _minBlockConfirmation;
    }

    function importNextSyncCommittee(bytes calldata _proof) external {
        require(address(committeeVerifier) != address(0), "Not set committeeVerifier");
        SyncCommitteeProof memory proofData;
        (proofData.a, proofData.b, proofData.c, proofData.inputs) = abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2], uint256[3]));
        SyncCommitteeInput memory input = _parseSyncCommitteeInput(proofData.inputs);

        uint64 nextPeriod = input.period + 1;
        require(syncCommitteeRoots[input.period] == input.syncCommitteeRoot, "invalid syncCommitteeRoot");
        require(syncCommitteeRoots[nextPeriod] == bytes32(0), "nextSyncCommitteeRoot already exist");

        uint256[1] memory compressInput;
        compressInput[0] = _hashSyncCommitteeInput(proofData.inputs);
        require(committeeVerifier.verifyProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");
        syncCommitteeRoots[nextPeriod] = input.nextSyncCommitteeRoot;
        currentPeriod = nextPeriod;
        emit ImportSyncCommitteeRoot(nextPeriod, input.nextSyncCommitteeRoot);
    }

    function importBlock(bytes calldata _proof) external {
        require(address(blockVerifier) != address(0), "Not set blockVerifier");
        BlockProof memory proofData;
        (proofData.a, proofData.b, proofData.c, proofData.inputs) = abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2], uint256[]));
        BlockInput memory parsedInput = _parseBlockInput(proofData.inputs);
        require(parsedInput.blockConfirmation >= minBlockConfirmation, "Not enough block confirmations");
        uint256 blockSize = (proofData.inputs.length - 2) / 5;
        for (uint256 i = 0; i < blockSize; i++) {
            (bool exist,uint256 blockConfirmation) = _checkBlock(parsedInput.blockHash[i], parsedInput.receiptHash[i]);
            if (exist && parsedInput.blockConfirmation <= blockConfirmation) {
                revert("already exist");
            }
        }
        uint256 period = _computePeriod(parsedInput.blockNumber[0]);
        require(syncCommitteeRoots[period] == parsedInput.syncCommitteeRoot, "invalid committeeRoot");

        uint256[1] memory compressInput;
        compressInput[0] = _hashBlockInput(proofData.inputs);
        require(blockVerifier.verifyProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");

        for (uint256 i = 0; i < blockSize; i++) {
            blockInfos[parsedInput.blockHash[i]][parsedInput.receiptHash[i]] = parsedInput.blockConfirmation;
            emit ImportBlock(parsedInput.blockNumber[i], parsedInput.blockHash[i], parsedInput.receiptHash[i]);
        }
    }

    function checkBlock(bytes32 _blockHash, bytes32 _receiptHash) external view returns (bool) {
        (bool exist,) = _checkBlock(_blockHash, _receiptHash);
        return exist;
    }

    function checkBlockConfirmation(bytes32 _blockHash, bytes32 _receiptHash) external view returns (bool, uint256) {
        return _checkBlock(_blockHash, _receiptHash);
    }

    function _checkBlock(bytes32 _blockHash, bytes32 _receiptHash) internal view returns (bool, uint256) {
        uint256 blockConfirmation = blockInfos[_blockHash][_receiptHash];
        if (blockConfirmation > 0) {
            return (true, blockConfirmation);
        }
        return (false, blockConfirmation);
    }

    function _parseSyncCommitteeInput(uint256[3] memory _inputs) internal pure returns (SyncCommitteeInput memory) {
        SyncCommitteeInput memory result;
        result.syncCommitteeRoot = bytes32(_inputs[0]);
        result.nextSyncCommitteeRoot = bytes32(_inputs[1]);
        result.period = uint64(_inputs[2]);
        return result;
    }

    function _parseBlockInput(uint256[] memory _inputs) internal pure returns (BlockInput memory result) {
        require(_inputs.length <= 82, "invalid public input");
        uint256 blockSize = (_inputs.length - 2) / 5;
        require(_inputs.length == blockSize * 5 + 2, "invalid public input");

        uint256 index = 0;
        for (uint256 i = 0; i < blockSize; i++) {
            result.blockNumber[i] = _inputs[index];
            index++;
        }

        result.syncCommitteeRoot = bytes32(_inputs[index]);
        index++;

        for (uint256 i = 0; i < blockSize; i++) {
            result.receiptHash[i] = bytes32((_inputs[index] << 128) | _inputs[index + 1]);
            index += 2;
        }

        for (uint256 i = 0; i < blockSize; i++) {
            result.blockHash[i] = bytes32((_inputs[index] << 128) | _inputs[index + 1]);
            index += 2;
        }

        result.blockConfirmation = _inputs[index];
        return result;
    }

    function _hashSyncCommitteeInput(uint256[3] memory _inputs) internal pure returns (uint256) {
        uint256 computedHash = uint256(keccak256(abi.encodePacked(_inputs[0], _inputs[1], _inputs[2])));
        return computedHash / 256;
    }

    function _hashBlockInput(uint256[] memory _inputs) internal pure returns (uint256) {
        uint256[82] memory inputs = _fillInput(_inputs);
        uint256 n = inputs.length;
        uint256 inputLength = n * 32;
        bytes memory packedInputs;
        assembly {
            packedInputs := mload(0x40) // Get the free memory pointer
            mstore(0x40, add(packedInputs, add(inputLength, 0x20))) // Update the free memory pointer

            let inputOffset := packedInputs
            mstore(inputOffset, inputLength) // Store the length of the concatenated inputs
            inputOffset := add(inputOffset, 0x20) // Move the pointer to the start of the concatenated inputs

            for {let i := 0} lt(i, n) {i := add(i, 1)} {
                let inputValue := mload(add(inputs, mul(i, 0x20))) // Load the input value
                mstore(inputOffset, inputValue) // Store the input value at the current offset
                inputOffset := add(inputOffset, 0x20) // Move the pointer to the next position
            }
        }
        uint256 computedHash = uint256(keccak256(packedInputs));
        return computedHash / 256;
    }


    function _fillInput(uint256[] memory _inputs) internal pure returns (uint256[82] memory inputs) {
        uint256 inIndex = 0;
        uint256 outIndex = 0;
        uint256 blockSize = (_inputs.length - 2) / 5;

        for (uint256 i = 0; i < blockSize; i++) {
            inputs[outIndex] = _inputs[inIndex];
            inIndex++;
            outIndex++;
        }
        outIndex += 16 - blockSize;


        inputs[outIndex] = _inputs[inIndex];
        inIndex++;
        outIndex++;

        for (uint256 i = 0; i < blockSize * 2; i++) {
            inputs[outIndex] = _inputs[inIndex];
            inIndex++;
            outIndex++;
        }
        outIndex += 32 - blockSize * 2;

        for (uint256 i = 0; i < blockSize * 2; i++) {
            inputs[outIndex] = _inputs[inIndex];
            inIndex++;
            outIndex++;
        }
        outIndex += 32 - blockSize * 2;

        inputs[outIndex] = _inputs[inIndex];
    }


    function _computePeriod(uint256 blockNumber) internal pure returns (uint256) {
        return blockNumber / 86400;
    }

    //----------------------------------------------------------------------------------
    // onlyOwner
    function setBlockConfirmation(uint256 _minBlockConfirmation) external onlyOwner {
        emit ModBlockConfirmation(minBlockConfirmation, _minBlockConfirmation);
        minBlockConfirmation = _minBlockConfirmation;
    }

    function setBlockVerifier(address _blockVerifier) external onlyOwner {
        require(_blockVerifier != address(0), "Zero address");
        blockVerifier = ICircuitVerifier(_blockVerifier);
    }

    function setCommitteeVerifier(address _committeeVerifier) external onlyOwner {
        require(_committeeVerifier != address(0), "Zero address");
        committeeVerifier = ICircuitVerifier(_committeeVerifier);
    }
}

