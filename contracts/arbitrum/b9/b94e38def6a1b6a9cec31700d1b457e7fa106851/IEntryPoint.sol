// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;

struct UserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

interface IAggregator {
    function validateSignatures(UserOperation[] calldata userOps, bytes calldata signature) external view;
    function validateUserOpSignature(UserOperation calldata userOp) external view returns (bytes memory sigForUserOp);
    function aggregateSignatures(UserOperation[] calldata userOps) external view returns (bytes memory aggregatedSignature);
}

interface IEntryPoint {
    struct UserOpsPerAggregator {
        UserOperation[] userOps;
        IAggregator aggregator;
        bytes signature;
    }

    struct ReturnInfo {
        uint256 preOpGas;
        uint256 prefund;
        bool sigFailed;
        uint48 validAfter;
        uint48 validUntil;
        bytes paymasterContext;
    }

    struct StakeInfo {
        uint256 stake;
        uint256 unstakeDelaySec;
    }

    struct AggregatorStakeInfo {
        address actualAggregator;
        StakeInfo stakeInfo;
    }

    receive() external payable;

    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external;
    function handleAggregatedOps(UserOpsPerAggregator[] calldata opsPerAggregator, address payable beneficiary) external;
    function simulateValidation(UserOperation calldata userOp) external;
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
    function getUserOpHash(UserOperation calldata userOp) external view returns (bytes32 userOpHash);
    function incrementNonce(uint192 key) external;

    error ValidationResult(ReturnInfo returnInfo,StakeInfo senderInfo, StakeInfo factoryInfo, StakeInfo paymasterInfo);
    error ValidationResultWithAggregation(ReturnInfo returnInfo, StakeInfo senderInfo, StakeInfo factoryInfo, StakeInfo paymasterInfo, AggregatorStakeInfo aggregatorInfo);
}

