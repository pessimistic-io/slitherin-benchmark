// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILiquidityAMO {
    event SetRewardVault(address newVault);
    event SetBuybackVault(address newVault);
    event SetTotalMintLimit(uint256 newLimit);
    event SetDeiAmountLimit(uint256 newLimit);
    event SetLpAmountLimit(uint256 newLimit);
    event SetCollateralRatio(uint256 newRatio);
    event SetValidRangeRatio(uint256 newRatio);
    event AddLiquidity(
        uint256 requestedUsdcAmount,
        uint256 requestedDeiAmount,
        uint256 usdcSpent,
        uint256 deiSpent,
        uint256 lpAmount
    );

    event RemoveLiquidity(
        uint256 requestedUsdcAmount,
        uint256 requestedDeiAmount,
        uint256 usdcGet,
        uint256 deiGet,
        uint256 lpAmount
    );

    event DepositLP(uint256 lpAmount, uint256 tokenId);
    event WithdrawLP(uint256 lpAmount);

    event MintDei(uint256 amount);
    event BurnDei(uint256 amount);

    event Swap(address from, address to, uint256 amountFrom, uint256 amountTo);

    event GetReward(address[] tokens, uint256[] amounts);

    event OptInTokens(address[] tokens);
    event OptOutTokens(address[] tokens);
    event DecreaseDeusValueToSell(uint256 deusValueToSell, uint256 value);

    event SetRewardToken(address[] token, bool isWhitelisted);
}

