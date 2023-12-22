// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20Metadata.sol";

interface ICToken is IERC20Metadata {
    function admin() external view returns (address);

    function accrueInterest() external returns (uint256);

    function mint() external payable;

    function mint(uint256 mintAmount) external returns (uint256);

    function mint(uint256 mintAmount, bool enterMarket) external returns (uint256);

    function mint(address recipient, uint256 mintAmount) external returns (uint256);

    // function mintForSelfAndEnterMarket(uint256) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function borrowBehalf(address, uint256) external;

    function borrowNative(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint repayAmount) external returns (uint);

    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);

    function redeem(uint256 redeemTokens) external returns (uint);

    // function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function comptroller() external view returns (address);

    function interestRateModel() external view returns (address);

    function borrowRatePerBlock() external view returns (uint);

    function exchangeRateStored() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function underlying() external view returns (address);

    function totalSupply() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function getCash() external view returns (uint256);

    function accrualBlockNumber() external view returns (uint256);

    function reserveFactorMantissa() external view returns (uint);

    function liquidateBorrow(address borrower, uint amount, address collateral) external returns (uint);
}

