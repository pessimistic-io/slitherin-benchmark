// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;


interface ITimelock {
    function batchWithdrawFees(address _vault, address[] memory _tokens) external;
    function admin() external view returns (address);
}

