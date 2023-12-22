// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategyInfo {
    /// @dev Uniswap-Transaction-related Variable
    function transactionDeadlineDuration() external view returns (uint256);

    /// @dev get Liquidity-NFT-related Variable
    function liquidityNftId() external view returns (uint256);

    function tickEndurance() external view returns (int24);

    function tickSpread() external view returns (int24);

    function tickSpacing() external view returns (int24);

    /// @dev get Pool-related Variable
    function poolAddress() external view returns (address);

    function poolFee() external view returns (uint24);

    function token0Address() external view returns (address);

    function token1Address() external view returns (address);

    /// @dev get Tracker-Token-related Variable
    function trackerTokenAddress() external view returns (address);

    /// @dev get User-Management-related Variable
    function isInUserList(address userAddress) external view returns (bool);

    function userIndex(address userAddress) external view returns (uint256);

    function getAllUsersInUserList() external view returns (address[] memory);

    /// @dev get User-Share-Management-related Variable
    function userShare(address userAddress) external view returns (uint256);

    function totalUserShare() external view returns (uint256);

    /// @dev get Reward-Management-related Variable
    function rewardToken0Amount() external view returns (uint256);

    function rewardToken1Amount() external view returns (uint256);

    function rewardUsdtAmount() external view returns (uint256);

    /// @dev get User-Reward-Management-related Variable
    function userUsdtReward(
        address userAddress
    ) external view returns (uint256);

    function totalUserUsdtReward() external view returns (uint256);

    /// @dev get Buyback-related Variable
    function buyBackToken() external view returns (address);

    function buyBackNumerator() external view returns (uint24);

    /// @dev get Fund-Manager-related Variable
    struct FundManager {
        address fundManagerAddress;
        uint256 fundManagerProfitNumerator;
    }

    function getAllFundManagers() external view returns (FundManager[7] memory);

    /// @dev get Earn-Loop-Control-related Variable
    function earnLoopSegmentSize() external view returns (uint256);

    function earnLoopDistributedAmount() external view returns (uint256);

    function earnLoopStartIndex() external view returns (uint256);

    function isEarning() external view returns (bool);

    /// @dev get Rescale-related Variable
    function dustToken0Amount() external view returns (uint256);

    function dustToken1Amount() external view returns (uint256);

    /// @dev get Rescale-Swap-related Variable
    function maxToken0ToToken1SwapAmount() external view returns (uint256);

    function maxToken1ToToken0SwapAmount() external view returns (uint256);

    function minSwapTimeInterval() external view returns (uint256);

    /// @dev get Rescale-Swap-Pace-Control-related Variable
    function lastSwapTimestamp() external view returns (uint256);

    function remainingSwapAmount() external view returns (uint256);

    function swapToken0ToToken1() external view returns (bool);

    /// @dev get Constant Variable
    function getBuyBackDenominator() external pure returns (uint24);

    function getFundManagerProfitDenominator() external pure returns (uint24);

    function getFarmAddress() external pure returns (address);

    function getControllerAddress() external pure returns (address);

    function getSwapAmountCalculatorAddress() external pure returns (address);

    function getZapAddress() external pure returns (address);
}

