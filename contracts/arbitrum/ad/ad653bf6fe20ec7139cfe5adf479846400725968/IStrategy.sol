// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategy {
    function depositLiquidity(
        bool isETH,
        address userAddress,
        address inputToken,
        uint256 inputAmount,
        uint256 swapInAmount,
        uint256 minimumSwapOutAmount
    )
        external
        payable
        returns (
            uint256 increasedToken0Amount,
            uint256 increasedToken1Amount,
            uint256 sendBackToken0Amount,
            uint256 sendBackToken1Amount
        );

    function withdrawLiquidity(
        address userAddress,
        uint256 withdrawShares
    )
        external
        returns (
            uint256 userReceivedToken0Amount,
            uint256 userReceivedToken1Amount
        );

    function collectRewards() external;

    function earnPreparation(
        uint256 minimumToken0SwapOutAmount,
        uint256 minimumToken1SwapOutAmount,
        uint256 minimumBuybackSwapOutAmount
    ) external;

    function earn() external;

    function claimReward(address userAddress) external;

    function rescale(int24 newTickUpper, int24 newTickLower) external;

    function depositDustToken(
        bool depositDustToken0
    )
        external
        returns (uint256 increasedToken0Amount, uint256 increasedToken1Amount);
}

