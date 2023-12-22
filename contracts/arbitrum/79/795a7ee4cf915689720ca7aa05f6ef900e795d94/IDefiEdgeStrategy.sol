// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./IUniswapV3Pool.sol";

interface IDefiEdgeStrategy {
    struct Tick {
        int24 tickLower;
        int24 tickUpper;
    }

    function getTicks() external view returns (Tick[] memory);

    function decimals() external view returns(uint256);
    
    function totalSupply() external view returns (uint256);

    function pool() external view returns (IUniswapV3Pool);

    function getAUMWithFees(bool _includeFee)
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 totalFee0,
            uint256 totalFee1
        );

    function burn(
        uint256 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external;
}
