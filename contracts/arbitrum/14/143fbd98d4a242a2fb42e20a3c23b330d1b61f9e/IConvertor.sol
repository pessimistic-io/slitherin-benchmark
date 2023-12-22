// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IConvertor {
    function convert(address _for, uint256 _amount, uint256 _mode) external;
}
