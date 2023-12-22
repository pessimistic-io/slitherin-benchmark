//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BalanceUpdate, UserBalanceUpdate, ProtocolBalanceUpdate } from "./Structs.sol";

interface IPepeBetPool {
    function deposit(address user, address token, uint256 amount, BalanceUpdate calldata balanceUpdate) external;

    function withdraw(address user, address token, uint256 amount, BalanceUpdate calldata balanceUpdate) external;

    function depositToPool(address token, uint256 amount, BalanceUpdate calldata balanceUpdate) external;

    function withdrawFromPool(address token, uint256 amount, BalanceUpdate calldata balanceUpdate) external;

    function transferFeesToDistributor(address token, uint256 amount, BalanceUpdate calldata balanceUpdate) external;

    function withdrawFees(address token, uint256 amount, BalanceUpdate calldata balanceUpdate) external;

    function fundServiceWallet(address token, uint256 amount) external;

    function syncBalances(BalanceUpdate calldata balanceUpdate) external;

    function approveTokens(address[] calldata tokens) external;

    function revokeTokens(address[] calldata tokens) external;

    function changeServiceWallet(address newServiceWallet) external;

    function changeFeeDistributor(address newFeeDistributor) external;

    function retrieve(address token) external;
}

