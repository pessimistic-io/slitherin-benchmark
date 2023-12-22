// SPDX-License-Identifier: MIT
// Clober-dex Contracts

pragma solidity ^0.8.0;

/**
 * @title ITokenBalanceViewer
 * @dev ITokenBalanceViewer is an interface contract that provides the functionality to retrieve information
 * about the balance and allowances of various token contracts.
 *
 * @author Clober-dex
 */
interface ITokenBalanceViewer {
    struct TokenInfo {
        address addr;
        string symbol;
        uint256 decimals;
    }

    struct TokenAllowance {
        address addr;
        string symbol;
        uint256 decimals;
        uint256 allowance;
    }

    struct TokenBalance {
        address addr;
        string symbol;
        uint256 decimals;
        uint256 balance;
    }

    struct TokenBalanceWithAllowance {
        address addr;
        string symbol;
        uint256 decimals;
        uint256 balance;
        uint256 allowance;
    }

    /*
     @function tokenInfos - Returns information about the given token contracts.
     @param contracts - Array of token contract addresses.
     @return results - Array of token information structs.
    */
    function tokenInfos(address[] calldata contracts) external view returns (TokenInfo[] memory results);

    /**
     * Function to retrieve token allowances for the given user and spender addresses.
     *
     * @param user - address of the token holder
     * @param spender - address of the spender
     * @param contracts - array of addresses of the token contracts to retrieve allowances from
     *
     * @return results - array of TokenAllowance structures containing information about
     * the user's allowance for each contract
     */
    function tokenAllowances(
        address user,
        address spender,
        address[] calldata contracts
    ) external view returns (TokenAllowance[] memory results);

    /*
     * @function tokenBalances - Returns the balances of the given tokens for the given user.
     * @param user - Address of the user to get the balances for.
     * @param contracts - Array of token contract addresses.
     * @param withEthBalance - Flag indicating whether to include the Ether balance in the result.
     * @return results - Array of token balance structs.
     */
    function tokenBalances(
        address user,
        address[] calldata contracts,
        bool withEthBalance
    ) external view returns (TokenBalance[] memory results);

    /*
     * @function tokenBalancesWithAllowances - Returns the balances and allowances of the given
     * tokens for the given user and spender.
     * @param user - Address of the user to get the balances for.
     * @param spender - Address of the spender to get the allowances for.
     * @param contracts - Array of token contract addresses.
     * @param withEthBalance - Flag indicating whether to include the Ether balance in the result.
     * @return results - Array of token balance with allowance structs.
     */
    function tokenBalancesWithAllowances(
        address user,
        address spender,
        address[] calldata contracts,
        bool withEthBalance
    ) external view returns (TokenBalanceWithAllowance[] memory results);
}

