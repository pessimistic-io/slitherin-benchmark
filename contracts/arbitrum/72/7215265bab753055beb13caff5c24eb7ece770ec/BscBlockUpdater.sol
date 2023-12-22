// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./BscVerifier.sol";

contract BscBlockUpdater is BscVerifier, Initializable, OwnableUpgradeable {
    event ImportValidator(uint256 indexed epoch, uint256 blockNumber, bytes32 blockHash, bytes32 receiptHash);
    event ImportBlock(uint256 indexed epoch, uint256 blockNumber, bytes32 blockHash, bytes32 receiptHash);

    struct ParsedInput {
        uint256 blockNumber;
        uint256 epochValidatorCount;
        bytes32 blockHash;
        bytes32 receiptHash;
        bytes32 signingValidatorSetHash;
        bytes32 epochValidatorSetHash;
    }

    struct ValidatorData {
        uint256 validatorCount;
        bytes32 validatorHash;
    }

    uint256 public currentEpoch;

    // epoch=>validatorHash
    mapping(uint256 => ValidatorData) public validatorDatas;

    // blockHash=>receiptsRoot
    mapping(bytes32 => bytes32) public blockInfos;

    function initialize(
        uint256 epoch,
        uint256 validatorCount,
        uint256 preValidatorCount,
        bytes32 epochValidatorSetHash,
        bytes32 preEpochValidatorSetHash,
        bytes32 blockHash,
        bytes32 receiptHash) public initializer {
        currentEpoch = epoch;
        validatorDatas[epoch] = ValidatorData(validatorCount, epochValidatorSetHash);
        validatorDatas[epoch - 1] = ValidatorData(preValidatorCount, preEpochValidatorSetHash);
        blockInfos[blockHash] = receiptHash;
        __Ownable_init();
    }

    function importNextValidatorSet(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[10] calldata inputs
    ) external {
        ParsedInput memory parsedInput = _parseInput(inputs);
        uint256 epoch = parsedInput.blockNumber / 200;
        uint256 preEpoch = epoch - 1;
        require(parsedInput.epochValidatorSetHash != bytes32(0), "invalid epochValidatorSetHash");
        require(parsedInput.signingValidatorSetHash != bytes32(0), "invalid signingValidatorSetHash");
        require(validatorDatas[epoch].validatorHash == bytes32(0), "epoch already exist");

        if (parsedInput.blockNumber % 200 < validatorDatas[preEpoch].validatorCount / 2) {
            require(parsedInput.signingValidatorSetHash == validatorDatas[preEpoch].validatorHash);
        } else {
            require(parsedInput.signingValidatorSetHash == parsedInput.epochValidatorSetHash);
        }
        uint256[1] memory compressInput;
        compressInput[0] = hashInput(inputs);
        require(verifyProof(a, b, c, compressInput), "invalid proof");
        validatorDatas[epoch] = ValidatorData(parsedInput.epochValidatorCount, parsedInput.epochValidatorSetHash);
        currentEpoch = epoch;
        blockInfos[parsedInput.blockHash] = parsedInput.receiptHash;
        emit ImportValidator(epoch, parsedInput.blockNumber, parsedInput.blockHash, parsedInput.receiptHash);
    }

    function importBlock(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[10] calldata inputs
    ) external {
        ParsedInput memory parsedInput = _parseInput(inputs);
        uint256 epoch = parsedInput.blockNumber / 200;
        uint256 preEpoch = epoch - 1;
        require(validatorDatas[epoch].validatorHash != bytes32(0), "epoch no upload");
        if (parsedInput.blockNumber % 200 < validatorDatas[preEpoch].validatorCount / 2) {
            require(parsedInput.signingValidatorSetHash == validatorDatas[preEpoch].validatorHash, "invalid preEpochValidatorSetHash");
        } else {
            require(parsedInput.signingValidatorSetHash == validatorDatas[epoch].validatorHash, "invalid epochValidatorSetHash");
        }

        uint256[1] memory compressInput;
        compressInput[0] = hashInput(inputs);
        require(verifyProof(a, b, c, compressInput), "invalid proof");
        blockInfos[parsedInput.blockHash] = parsedInput.receiptHash;
        emit ImportBlock(epoch, parsedInput.blockNumber, parsedInput.blockHash, parsedInput.receiptHash);
    }

    function checkBlock(bytes32 blockHash, bytes32 receiptHash) external view returns (bool) {
        bytes32 _receiptHash = blockInfos[blockHash];
        if (_receiptHash != bytes32(0) && _receiptHash == receiptHash) {
            return true;
        }
        return false;
    }

    function _parseInput(uint256[10] memory inputs) internal pure returns (ParsedInput memory)    {
        ParsedInput memory result;
        result.blockNumber = inputs[0];
        result.blockHash = bytes32((inputs[2] << 128) | inputs[1]);
        result.receiptHash = bytes32((inputs[4] << 128) | inputs[3]);
        result.signingValidatorSetHash = bytes32((inputs[6] << 128) | inputs[5]);
        result.epochValidatorSetHash = bytes32((inputs[8] << 128) | inputs[7]);
        result.epochValidatorCount = inputs[9];
        return result;
    }

    function hashInput(uint256[10] memory inputs) internal pure returns (uint256) {
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
}

