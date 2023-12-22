// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

/**
 * @title  ITokenDistributor contract
 * @author Archethect
 * @notice This interface contains all functionalities for distributing ERC20 tokens.
 */
interface ITokenDistributor {
    function payout(address payee, uint256 amount) external;
}

