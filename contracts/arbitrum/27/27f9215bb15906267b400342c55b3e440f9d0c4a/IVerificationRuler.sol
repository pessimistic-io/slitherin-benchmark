// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IVerificationRuler {
    function canBorrow(address _vault, uint256 _borrowedAmount) external view returns (bool);
}

