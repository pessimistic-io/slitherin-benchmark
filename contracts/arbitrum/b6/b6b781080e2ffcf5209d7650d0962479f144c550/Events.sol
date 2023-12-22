// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import {Enums} from "./Enums.sol";

library Events {
    // AUTOMATED VAULT

    event CreatorFeeTransfered(
        address indexed vault,
        address indexed depositor,
        address indexed creator,
        uint256 shares
    );

    // VAULT FACTORY

    event VaultCreated(
        address indexed creator,
        address indexed depositAsset,
        address[] buyAssets,
        address vaultAddress,
        uint256[] buyPercentages,
        Enums.BuyFrequency buyFrequency
    );
    event TreasuryFeeTransfered(address creator, uint256 amount);

    // TREASURY VAULT

    event TreasuryCreated(address creator, address treasuryAddress);
    event EtherReceived(address indexed sender, uint256 amount);
    event ERC20Received(address indexed sender, uint256 amount, address asset);
    event NativeWithdrawal(address indexed owner, uint256 amount);
    event ERC20Withdrawal(
        address indexed owner,
        address indexed token,
        uint256 amount
    );

    // STRATEGY WORKER

    event StrategyActionExecuted(
        address indexed vault,
        address indexed depositor,
        address tokenIn,
        uint256 tokenInAmount,
        address[] tokensOut,
        uint256[] tokensOutAmounts,
        uint256 feeAmount
    );
}

