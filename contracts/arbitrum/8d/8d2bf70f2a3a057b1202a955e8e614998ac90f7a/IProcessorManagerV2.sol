// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IProcessorManagerV2 {
    struct ProcessorManagerInitParams {
        uint256 baseFee;
        uint128 variableFee;
        uint8 maxFeeWithdrawalBatchSize;
    }

    function processorBalances(address processor_, address token_)
        external
        returns (uint256 balance);

    function maxFeeWithdrawalBatchSize() external returns (uint8 batchSize);

    function withdrawProcessorFees(address[] calldata tokens_) external;

    function updateMaxFeeWithdrawalBatchSize(uint8 newBatchSize_) external;

    function updateBaseFee(uint256 newBaseFee_) external;

    function updateVariableFee(uint128 newVariableFee_) external;
}

