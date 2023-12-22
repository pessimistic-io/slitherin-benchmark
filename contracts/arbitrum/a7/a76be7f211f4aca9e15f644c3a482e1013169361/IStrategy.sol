// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategy {
    function depositLiquidity(
        bool isETH,
        address userAddress,
        address inputToken,
        uint256 inputAmount
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

    function earnPreparation() external;

    function earn() external;

    function claimReward(address userAddress) external;

    function rescalePreparation() external;

    function rescale() external;

    function depositDustToken(
        bool depositDustToken0
    )
        external
        returns (uint256 increasedToken0Amount, uint256 increasedToken1Amount);
}

