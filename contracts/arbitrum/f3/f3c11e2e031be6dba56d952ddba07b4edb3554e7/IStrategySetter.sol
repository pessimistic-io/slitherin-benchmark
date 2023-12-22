// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategySetter {
    function setTransactionDeadlineDuration(
        uint256 _transactionDeadlineDuration
    ) external;

    function setTickSpread(int24 _tickSpread) external;

    function setTickEndurance(int24 _tickEndurance) external;

    function setBuyBackToken(address _buyBackToken) external;

    function setBuyBackNumerator(uint24 _buyBackNumerator) external;

    function setFundManagerByIndex(
        uint256 index,
        address _fundManagerAddress,
        uint24 _fundManagerProfitNumerator
    ) external;

    function setEarnLoopSegmentSize(uint256 _earnLoopSegmentSize) external;

    function setMaxToken0ToToken1SwapAmount(
        uint256 _maxToken0ToToken1SwapAmount
    ) external;

    function setMaxToken1ToToken0SwapAmount(
        uint256 _maxToken1ToToken0SwapAmount
    ) external;

    function setMinSwapTimeInterval(uint256 _minSwapTimeInterval) external;
}

