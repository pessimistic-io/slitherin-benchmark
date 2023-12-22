// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ICpSLNAConfigurator {
    function isAutoIncreaseLock() external view returns (bool);
    function maxPeg() external view returns (uint256);

    function isPausedDepositVe() external view returns (bool);
    function isPausedDeposit() external view returns (bool);

    function hasSellingTax(address _from, address _to) external view returns (uint256);
    function hasBuyingTax(address _from, address _to) external view returns (uint256);
    function deadWallet() external view returns (address);
    function getFee() external view returns (uint256);
    function coFeeRecipient() external view returns (address);
    function getExcluded() external view returns (address[] memory);
}
