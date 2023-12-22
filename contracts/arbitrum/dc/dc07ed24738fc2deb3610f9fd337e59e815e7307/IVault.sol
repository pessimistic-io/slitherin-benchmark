// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;

interface IVault {
    function addPoolBalance(uint256 _balance) external;

    function addPoolRmLpFeeBalance(uint256 _feeAmount) external;

    function transfer(address _to, uint256 _amount, bool isOutETH) external;

    function addExchangeFeeBalance(uint256 _feeAmount) external;
}

