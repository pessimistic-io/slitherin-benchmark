// SPDX-License-Identifier: BSD

pragma solidity ^0.8.17;

interface IBalanceSetter {
    function getDividendBalance(address dividendContract, address account) external view returns (uint256);
}

