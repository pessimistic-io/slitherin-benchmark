// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface ITokenRelease {
    function addFund(address _recipient, uint256 _amountIn) external;
}

