// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./CeloVerifier.sol";
import "./IBlockUpdater.sol";

contract CeloBlockUpdater is IBlockUpdater, Initializable, OwnableUpgradeable, CeloVerifier {
    event ImportValidator(uint256 indexed epoch, uint256 indexed blockNumber, bytes32 blockHash, bytes32 receiptHash);
    event ModBlockConfirmation(uint256 oldBlockConfirmation, uint256 newBlockConfirmation);

    struct ParsedInput {
        uint256 blockNumber;
        uint256 blockConfirmation;
        bytes32 blockHash;
        bytes32 receiptHash;
        bytes32 signingValidatorSetHash;
        bytes32 nextValidatorSetHash;
    }

    struct ZkProof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[8] inputs;
    }

    uint256 public currentEpoch;

    uint256 public minBlockConfirmation;

    // epoch=>validatorHash
    mapping(uint256 => bytes32) public validatorHashes;

    // blockHash=>receiptsRoot =>BlockConfirmation
    mapping(bytes32 => mapping(bytes32 => uint256)) public blockInfos;

    function initialize(
        uint256 _epoch,
        bytes32 _epochValidatorSetHash,
        uint256 _minBlockConfirmation) public initializer {
        __Ownable_init();
        validatorHashes[_epoch] = _epochValidatorSetHash;
        minBlockConfirmation = _minBlockConfirmation;
        currentEpoch = _epoch;
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
        return exist;
    }

    function checkBlockConfirmation(bytes32 _blockHash, bytes32 _receiptHash) external view returns (bool, uint256) {
        (bool exist,uint256 blockConfirmation) = _checkBlock(_blockHash, _receiptHash);
        return (exist, blockConfirmation);
    }

    function _checkBlock(bytes32 _blockHash, bytes32 _receiptHash) internal view returns (bool, uint256) {
        uint256 blockConfirmation = blockInfos[_blockHash][_receiptHash];
        if (blockConfirmation > 0) {
            return (true, blockConfirmation);
        }
        return (false, blockConfirmation);
    }


    function _importNextValidatorSet(bytes memory _proof) internal {
        ZkProof memory proofData;
        (proofData.a, proofData.b, proofData.c, proofData.inputs) = abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2], uint256[8]));
        ParsedInput memory parsedInput = _parseInput(proofData.inputs);
        uint256 epoch = _computeEpoch(parsedInput.blockNumber);
        uint256 nextEpoch = epoch + 1;
        require(parsedInput.nextValidatorSetHash != bytes32(0), "invalid nextValidatorSetHash");
        require(parsedInput.signingValidatorSetHash != bytes32(0), "invalid signingValidatorSetHash");
        require(parsedInput.blockConfirmation >= minBlockConfirmation, "Not enough block confirmations");
        require(validatorHashes[epoch] != bytes32(0), "epoch no upload");
        require(validatorHashes[nextEpoch] == bytes32(0), "epoch already exist");
        uint256[1] memory compressInput;
        compressInput[0] = _hashInput(proofData.inputs);
        require(verifyProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");
        validatorHashes[nextEpoch] = parsedInput.nextValidatorSetHash;
        currentEpoch = nextEpoch;
        blockInfos[parsedInput.blockHash][parsedInput.receiptHash] = parsedInput.blockConfirmation;
        emit ImportValidator(nextEpoch, parsedInput.blockNumber, parsedInput.blockHash, parsedInput.receiptHash);
    }

    function _importBlock(bytes memory _proof) internal {
        ZkProof memory proofData;
        (proofData.a, proofData.b, proofData.c, proofData.inputs) = abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2], uint256[8]));
        ParsedInput memory parsedInput = _parseInput(proofData.inputs);

        require(parsedInput.blockConfirmation >= minBlockConfirmation, "Not enough block confirmations");
        (bool exist,uint256 blockConfirmation) = _checkBlock(parsedInput.blockHash, parsedInput.receiptHash);
        if (exist && parsedInput.blockConfirmation <= blockConfirmation) {
            revert("already exist");
        }
        uint256 epoch = _computeEpoch(parsedInput.blockNumber);
        require(validatorHashes[epoch] == parsedInput.signingValidatorSetHash, "epoch no upload");

        uint256[1] memory compressInput;
        compressInput[0] = _hashInput(proofData.inputs);
        require(verifyProof(proofData.a, proofData.b, proofData.c, compressInput), "invalid proof");
        blockInfos[parsedInput.blockHash][parsedInput.receiptHash] = parsedInput.blockConfirmation;
        emit ImportBlock(parsedInput.blockNumber, parsedInput.blockHash, parsedInput.receiptHash);
    }

    function _parseInput(uint256[8] memory _inputs) internal pure returns (ParsedInput memory)    {
        ParsedInput memory result;
        result.blockNumber = _inputs[0];
        result.blockHash = bytes32((_inputs[2] << 128) | _inputs[1]);
        result.receiptHash = bytes32((_inputs[4] << 128) | _inputs[3]);
        result.signingValidatorSetHash = bytes32(_inputs[5]);
        result.nextValidatorSetHash = bytes32(_inputs[6]);
        result.blockConfirmation = _inputs[7];
        return result;
    }

    function _hashInput(uint256[8] memory _inputs) internal pure returns (uint256) {
        uint256 computedHash = uint256(keccak256(abi.encodePacked(_inputs[0], _inputs[1], _inputs[2],
            _inputs[3], _inputs[4], _inputs[5], _inputs[6], _inputs[7])));
        return computedHash / 256;
    }

    function _computeEpoch(uint256 blockNumber) internal pure returns (uint256) {
        return (blockNumber + 17280 - 1) / 17280;
    }

    //----------------------------------------------------------------------------------
    // onlyOwner
    function setBlockConfirmation(uint256 _minBlockConfirmation) external onlyOwner {
        emit ModBlockConfirmation(minBlockConfirmation, _minBlockConfirmation);
        minBlockConfirmation = _minBlockConfirmation;
    }
}
