// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.3;

interface IStableJoeStaking {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getUserInfo(address _user, address _rewardToken) external view returns (uint256, uint256);
}

interface ILBRouter { 
    enum Version {
        V1,
        V2,
        V2_1
    }
    struct Path {
        uint256[] pairBinSteps;
        Version[] versions;
        address[] tokenPath;
    }
    function swapExactTokensForTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Path memory path,
        address to,
        uint256 deadline
    )  external returns (uint256);
    function getSwapOut(address pair, uint128 amountIn, bool swapForY) external returns (uint128 amountInLeft, uint128 amountOut, uint128 fee);
}

interface ILBQuoter { 
    struct Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        ILBRouter.Version[] versions;
        uint128[] amounts;
        uint128[] virtualAmountsWithoutSlippage;
        uint128[] fees;
    }

    function findBestPathFromAmountIn(
        address[] calldata _route,
        uint128 _amountIn
    ) external view returns (Quote memory quote);
}
