// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IBorrower.sol";
import "./IUniswapV3StrategyData.sol";
import "./IUniswapV3Storage.sol";
import "./UniswapV3StrategyStorage.sol";

interface IUniswapV3BaseStrategy is IBorrower, IUniswapV3Storage {
    function updateCache() external;
    function balanceOptimizedWithoutSlippage() external returns (int);
    function getHarvestable() external view returns (uint harvestable);
    function getStableDebtFraction() external view returns (uint ratio);
    function getPnl() external view returns (IUniswapV3StrategyData.PNLData memory data);
    function getDepositToken() external view returns (address depositToken);
    function heartBeat()
        external
        view
        returns (
            bool ammCheck,
            int256 health,
            int256 equity,
            uint256 currentPrice
        );
    function setLeverageAndTicks(
        uint _leverage,
        int24 _multiplier0,
        int24 _multiplier1
    ) external;
    function setMinLeverage(uint _minLeverage) external;
    function setMaxLeverage(uint _maxLeverage) external;
    function setThresholds(UniswapV3StrategyStorage.Thresholds memory _thresholds) external;

    function calculateBorrowAmounts() external view returns (address[] memory tokens, int[] memory amounts);
}
