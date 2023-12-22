// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;
//pragma abicoder v2;

import {Range, Rebalance, DepositParams} from "./EnigmaStructs.sol";

interface IEnigma {
    /// -----------------------------------------------------------
    /// EVENTS
    /// -----------------------------------------------------------

    /// @notice Emitted when a deposit is made to the enigma pool
    event Log_Deposit(address indexed sender, uint256 shares, uint256 amount0, uint256 amount1);

    /// @notice Emitted when a withdrawal is made to the enigma pool
    event Log_Withdraw(address indexed recipient, uint256 shares, uint256 amount0, uint256 amount1);

    /// @notice Emitted when a fee is collected from the underlying uniswap pool
    event Log_CollectFees(uint256 feeAmount0, uint256 feeAmount1);
    /// @notice Logs the distributed fees to the operator and enigma protocol
    event Log_DistributeFees(uint256 operatorFee0, uint256 operatorFee1, uint256 enigmaFee0, uint256 enigmaFee1);

    event Log_Rebalance(Rebalance _params, uint256 balance0After, uint256 balance1After);

    /// -----------------------------------------------------------
    /// INTERFACE FUNCTIONS
    /// -----------------------------------------------------------

    function getFactory() external view returns (address factory_);
    //function totalSupply() external view returns (uint256);

    function deposit(DepositParams calldata params)
        external
        payable
        returns (uint256 shares, uint256 amount0, uint256 amount1);

    /// -----------------------------------------------------------
    /// END IEnigma.sol by SteakHut Labs
    /// -----------------------------------------------------------
}

