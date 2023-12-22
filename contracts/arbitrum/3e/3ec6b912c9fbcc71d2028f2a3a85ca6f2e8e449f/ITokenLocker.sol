// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface ITokenLocker {
    function addFund(address _recipient, uint256 _amountIn) external;

    function addFunds(address[] calldata _recipients, uint256[] calldata _amounts, uint256 _totalSupply) external;

    function claim() external;
}

