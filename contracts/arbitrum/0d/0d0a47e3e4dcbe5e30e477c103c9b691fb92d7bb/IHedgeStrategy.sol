// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";

interface IHedgeStrategy {

    event Reward(uint256 amount);

    event Stake(uint256 amount);
    event Unstake(uint256 amount, uint256 amountReceived);

    event SetHealthFactor(uint256 healthFactor);

    struct BalanceItem {
        address token;
        uint256 amountUSD;
        uint256 amount;
        bool    borrowed;
    }

    enum BalanceType {
        APPROACH_BALANCE,
        TARGET_BALANCE
    }

    enum BalanceSwapType {
        DEFAULT_SWAP,
        INCH_SWAP
    }

    struct BalanceParams {
        BalanceType balanceType;
        BalanceSwapType balanceSwapType;
        uint256 balanceRatio;
        uint256 targetBalancePrice;
        bool isRevertWhenBadRate;
    }

    function stake(
        uint256 _amount // value for staking in asset
    ) external;

    function unstake(
        uint256 _amount, // minimum expected value for unstaking in asset
        address _to      // PortfolioManager
    ) external returns (uint256); // Real unstake value

    function netAssetValue() external view returns (uint256); // Return value in USDC - denominator 6

    function claimRewards(address _to) external returns (uint256); // Return received amount in USDC - denominator 6

    function balance(uint256 balanceRatio) external; // Balancing aave health factor or position depends of ets

    function structBalance(BalanceParams calldata balanceParams) external; // Balancing aave health factor or position depends of ets

    function balances() external view returns (BalanceItem[] memory ); // Get info of ets liquidity and amount

    function exit() external; // exit from ETS and put all liquidity to Aave

    function enter() external; // enter to ETS from Aave
}

