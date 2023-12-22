// SPDX-License-Identifier: MIT
// Clober-dex Contracts

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ITokenBalanceViewer.sol";

contract TokenBalanceViewer is ITokenBalanceViewer {
    function tokenInfos(address[] calldata contracts) external view returns (TokenInfo[] memory results) {
        results = new TokenInfo[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            ERC20 token = ERC20(contracts[i]);
            results[i] = TokenInfo({addr: contracts[i], symbol: token.symbol(), decimals: token.decimals()});
        }
        return results;
    }

    function tokenAllowances(
        address user,
        address spender,
        address[] calldata contracts
    ) external view returns (TokenAllowance[] memory results) {
        results = new TokenAllowance[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            ERC20 token = ERC20(contracts[i]);
            results[i] = TokenAllowance({
                addr: contracts[i],
                symbol: token.symbol(),
                decimals: token.decimals(),
                allowance: token.allowance(user, spender)
            });
        }
        return results;
    }

    function tokenBalances(
        address user,
        address[] calldata contracts,
        bool withEthBalance
    ) external view returns (TokenBalance[] memory results) {
        uint256 len = contracts.length + (withEthBalance ? 1 : 0);
        results = new TokenBalance[](len);
        for (uint256 i = 0; i < contracts.length; i++) {
            ERC20 token = ERC20(contracts[i]);
            results[i] = TokenBalance({
                addr: contracts[i],
                symbol: token.symbol(),
                decimals: token.decimals(),
                balance: token.balanceOf(user)
            });
        }
        if (withEthBalance) {
            results[contracts.length] = TokenBalance({
                addr: address(0),
                symbol: "ETH",
                decimals: 18,
                balance: user.balance
            });
        }
        return results;
    }

    function tokenBalancesWithAllowances(
        address user,
        address spender,
        address[] calldata contracts,
        bool withEthBalance
    ) external view returns (TokenBalanceWithAllowance[] memory results) {
        uint256 len = contracts.length + (withEthBalance ? 1 : 0);
        results = new TokenBalanceWithAllowance[](len);
        for (uint256 i = 0; i < contracts.length; i++) {
            ERC20 token = ERC20(contracts[i]);
            results[i] = TokenBalanceWithAllowance({
                addr: contracts[i],
                symbol: token.symbol(),
                decimals: token.decimals(),
                balance: token.balanceOf(user),
                allowance: token.allowance(user, spender)
            });
        }
        if (withEthBalance) {
            results[contracts.length] = TokenBalanceWithAllowance({
                addr: address(0),
                symbol: "ETH",
                decimals: 18,
                balance: user.balance,
                allowance: 0
            });
        }
        return results;
    }
}

