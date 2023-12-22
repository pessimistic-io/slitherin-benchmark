// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

contract LendingPairEvents {
    event Liquidation(
        address indexed account,
        address indexed repayToken,
        address indexed supplyToken,
        uint256 repayAmount,
        uint256 supplyAmount
    );
    event Deposit(
        address indexed account,
        address indexed token,
        uint256 amount
    );
    event Withdraw(
        address indexed account,
        address indexed token,
        uint256 amount
    );
    event Borrow(
        address indexed account,
        address indexed token,
        uint256 amount
    );
    event Repay(address indexed account, address indexed token, uint256 amount);
    event CollectSystemFee(address indexed token, uint256 amount);
    event ColFactorSet(
        address indexed token,
        uint256 oldValue,
        uint256 newValue
    );
    event LpRateSet(uint256 oldLpRate, uint256 newLpRate);
    event InterestRateParametersSet(
        uint256 oldMinRate,
        uint256 oldLowRate,
        uint256 oldHighRate,
        uint256 oldTargetUtilization,
        uint256 minRate,
        uint256 lowRate,
        uint256 highRate,
        uint256 targetUtilization
    );
}

