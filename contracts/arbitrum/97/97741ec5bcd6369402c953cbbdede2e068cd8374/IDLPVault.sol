// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IDLPVault {
    function withdrawForLeverager(address _account, uint256 _amount) external;
}

