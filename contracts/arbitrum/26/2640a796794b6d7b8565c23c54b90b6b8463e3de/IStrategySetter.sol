// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategySetter {
    function setTransactionDeadlineDuration(
        uint256 _transactionDeadlineDuration
    ) external;

    function setBuyBackToken(address _buyBackToken) external;

    function setBuyBackNumerator(uint24 _buyBackNumerator) external;

    function setFundManagerVaultByIndex(
        uint256 index,
        address _fundManagerVaultAddress,
        uint24 _fundManagerProfitVaultNumerator
    ) external;

    function setEarnLoopSegmentSize(uint256 _earnLoopSegmentSize) external;
}

