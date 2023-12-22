// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./BscVerifier.sol";
import "./BscLubanVerifier.sol";
import "./IBlockUpdater.sol";

contract BscBlockUpdater is IBlockUpdater, BscVerifier, Initializable, OwnableUpgradeable, BscLubanVerifier {
    event ImportValidator(uint256 indexed epoch, uint256 indexed blockNumber, bytes32 blockHash, bytes32 receiptHash);
    event ModBlockConfirmation(uint256 oldBlockConfirmation, uint256 newBlockConfirmation);

    struct ParsedInput {
        uint256 blockNumber;
        uint256 epochValidatorCount;
        uint256 blockConfirmation;
        bytes32 blockHash;
        bytes32 receiptHash;
        bytes32 signingValidatorSetHash;
        bytes32 epochValidatorSetHash;
    }

    struct ZkProof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[11] inputs;
    }

    uint256 public currentEpoch;

    uint256 public minBlockConfirmation;

    uint256 public  regularValidatorCount;

    // epoch=>validatorHash
    mapping(uint256 => bytes32) public validatorHashes;

    // epoch=>validatorCount
    mapping(uint256 => uint256) private validatorCounts;

    // blockHash=>receiptsRoot =>BlockConfirmation
    mapping(bytes32 => mapping(bytes32 => uint256)) public blockInfos;

    IBlockUpdater public oldBlockUpdater;

    uint256 public  lubanBlockNumber;

    function initialize(
        uint256 _epoch,
        uint256 _validatorCount,
        uint256 _preValidatorCount,
        bytes32 _epochValidatorSetHash,
        bytes32 _preEpochValidatorSetHash,
        bytes32 _blockHash,
        bytes32 _receiptHash,
        uint256 _minBlockConfirmation,
        uint256 _regularValidatorCount) public initializer {
        __Ownable_init();
        currentEpoch = _epoch;
        validatorHashes[_epoch] = _epochValidatorSetHash;
        validatorHashes[_epoch - 1] = _preEpochValidatorSetHash;
        validatorCounts[_epoch] = _validatorCount;
        _setValidatorCount(_epoch, _validatorCount);
        _setValidatorCount(_epoch - 1, _preValidatorCount);
        blockInfos[_blockHash][_receiptHash] = _minBlockConfirmation;
        minBlockConfirmation = _minBlockConfirmation;
        regularValidatorCount = _regularValidatorCount;
    }

    function importNextValidatorSet(bytes calldata _proof) external {
        _importNextValidatorSet(_proof);
    }

    function BatchImportNextValidatorSet(bytes[] calldata _proof) external {
        for (uint256 i = 0; i < _proof.length; i++) {
            _importNextValidatorSet(_proof[i]);
        }
    }

    function importBlock(bytes calldata _proof) external {
        _importBlock(_proof);
    }

    function BatchImportBlock(bytes[] calldata _proof) external {
        for (uint256 i = 0; i < _proof.length; i++) {
            _importBlock(_proof[i]);
        }
    }

    function checkBlock(bytes32 _blockHash, bytes32 _receiptHash) external view returns (bool) {
        (bool exist,) = _checkBlock(_blockHash, _receiptHash);
        if (!exist && address(oldBlockUpdater) != address(0)) {
            exist = oldBlockUpdater.checkBlock(_blockHash, _receiptHash);
        }
        return exist;
    }

    function checkBlockConfirmation(bytes32 _blockHash, bytes32 _receiptHash) external view returns (bool, uint256) {
        (bool exist,uint256 blockConfirmation) = _checkBlock(_blockHash, _receiptHash);
        if (!exist && address(oldBlockUpdater) != address(0)) {
            exist = oldBlockUpdater.checkBlock(_blockHash, _receiptHash);
            blockConfirmation = minBlockConfirmation;
        }
        return (exist, blockConfirmation);
    }

    function _checkBlock(bytes32 _blockHash, bytes32 _receiptHash) internal view returns (bool, uint256) {
        uint256 blockConfirmation = blockInfos[_blockHash][_receiptHash];
        if (blockConfirmation > 0) {
            return (true, blockConfirmation);
        }
        return (false, blockConfirmation);
    }

    function _setValidatorCount(uint256 _epoch, uint256 _validatorCount) internal {
        if (_validatorCount != regularValidatorCount) {
            validatorCounts[_epoch] = _validatorCount;
        }
    }

    function getValidatorCount(uint256 _epoch) public view returns (uint256) {
        if (validatorCounts[_epoch] != 0) {
            return validatorCounts[_epoch];
        }
        return regularValidatorCount;
    }

    function _importNextValidatorSet(bytes memory _proof) internal {
        ZkProof memory proofData;
        (proofData.a, proofData.b, proofData.c, proofData.inputs) = abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2], uint256[11]));
        ParsedInput memory parsedInput = _parseInput(proofData.inputs);
        uint256 epoch = _computeEpoch(parsedInput.blockNumber);
        uint256 preEpoch = epoch - 1;
        require(parsedInput.epochValidatorSetHash != bytes32(0), "invalid epochValidatorSetHash");
        require(parsedInput.signingValidatorSetHash != bytes32(0), "invalid signingValidatorSetHash");
        require(parsedInput.blockConfirmation >= minBlockConfirmation, "Not enough block confirmations");
        require(validatorHashes[epoch] == bytes32(0), "epoch already exist");
        if (parsedInput.blockNumber % 200 <= getValidatorCount(preEpoch) / 2) {
            require(parsedInput.signingValidatorSetHash == validatorHashes[preEpoch], "invalid preEpochValidatorSetHash");
        } else {
            require(parsedInput.signingValidatorSetHash == parsedInput.epochValidatorSetHash, "invalid epochValidatorSetHash");
        }
        uint256[1] memory compressInput;
        compressInput[0] = _hashInput(proofData.inputs);
        if (lubanBlockNumber != 0 && block.number >= lubanBlockNumber) {
            require(verifyLubanProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");
        } else {
            require(verifyProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");
        }
        validatorHashes[epoch] = parsedInput.epochValidatorSetHash;
        _setValidatorCount(epoch, parsedInput.epochValidatorCount);
        currentEpoch = epoch;
        blockInfos[parsedInput.blockHash][parsedInput.receiptHash] = parsedInput.blockConfirmation;
        emit ImportValidator(epoch, parsedInput.blockNumber, parsedInput.blockHash, parsedInput.receiptHash);
    }

    function _importBlock(bytes memory _proof) internal {
        ZkProof memory proofData;
        (proofData.a, proofData.b, proofData.c, proofData.inputs) = abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2], uint256[11]));
        ParsedInput memory parsedInput = _parseInput(proofData.inputs);

        require(parsedInput.blockConfirmation >= minBlockConfirmation, "Not enough block confirmations");
        (bool exist,uint256 blockConfirmation) = _checkBlock(parsedInput.blockHash, parsedInput.receiptHash);
        if (exist && parsedInput.blockConfirmation <= blockConfirmation) {
            revert("already exist");
        }
        uint256 epoch = _computeEpoch(parsedInput.blockNumber);
        uint256 preEpoch = epoch - 1;
        require(validatorHashes[epoch] != bytes32(0), "epoch no upload");

        if (parsedInput.blockNumber % 200 <= getValidatorCount(preEpoch) / 2) {
            require(parsedInput.signingValidatorSetHash == validatorHashes[preEpoch], "invalid preEpochValidatorSetHash");
        } else {
            require(parsedInput.signingValidatorSetHash == validatorHashes[epoch], "invalid epochValidatorSetHash");
        }

        uint256[1] memory compressInput;
        compressInput[0] = _hashInput(proofData.inputs);
        if (lubanBlockNumber != 0 && block.number >= lubanBlockNumber) {
            require(verifyLubanProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");
        } else {
            require(verifyProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");
        }
        blockInfos[parsedInput.blockHash][parsedInput.receiptHash] = parsedInput.blockConfirmation;
        emit ImportBlock(parsedInput.blockNumber, parsedInput.blockHash, parsedInput.receiptHash);
    }

    function _parseInput(uint256[11] memory _inputs) internal pure returns (ParsedInput memory)    {
        ParsedInput memory result;
        result.blockNumber = _inputs[0];
        result.blockHash = bytes32((_inputs[2] << 128) | _inputs[1]);
        result.receiptHash = bytes32((_inputs[4] << 128) | _inputs[3]);
        result.signingValidatorSetHash = bytes32((_inputs[6] << 128) | _inputs[5]);
        result.epochValidatorSetHash = bytes32((_inputs[8] << 128) | _inputs[7]);
        result.epochValidatorCount = _inputs[9];
        result.blockConfirmation = _inputs[10];
        return result;
    }

    function _hashInput(uint256[11] memory _inputs) internal pure returns (uint256) {
        uint256 computedHash = uint256(keccak256(abi.encodePacked(_inputs[0], _inputs[1], _inputs[2],
            _inputs[3], _inputs[4], _inputs[5], _inputs[6], _inputs[7], _inputs[8], _inputs[9], _inputs[10])));
        return computedHash / 256;
    }

    function _computeEpoch(uint256 blockNumber) internal pure returns (uint256) {
        return blockNumber / 200;
    }

    //----------------------------------------------------------------------------------
    // onlyOwner
    function setBlockConfirmation(uint256 _minBlockConfirmation) external onlyOwner {
        emit ModBlockConfirmation(minBlockConfirmation, _minBlockConfirmation);
        minBlockConfirmation = _minBlockConfirmation;
    }

    function setOldBlockUpdater(address _oldBlockUpdater) external onlyOwner {
        oldBlockUpdater = IBlockUpdater(_oldBlockUpdater);
    }

    function setLubanBlockNumber(uint256 _lubanBlockNumber) external onlyOwner {
        lubanBlockNumber = _lubanBlockNumber;
    }

}
