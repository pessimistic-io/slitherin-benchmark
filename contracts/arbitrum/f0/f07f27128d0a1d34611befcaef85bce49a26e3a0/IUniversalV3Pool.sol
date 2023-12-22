// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title The interface for Uniswap V3 Pool and Algebra Pool
/// @notice This interface combinates to interfaces
/// @dev The pool interface has only necessary part to work
interface IUniversalV3Pool {

    /// @dev KyberSwapV2Pool function to get fee
    function swapFeeUnits() external view returns (uint24);

    /// @dev UniswapV3Pool function to get fee
    function fee() external view returns (uint24);

    /// @dev AlgebraPool function to get fee
    function globalState() external view returns (
      uint160 price,
      int24 tick,
      uint16 fee,
      uint16 timepointIndex,
      uint8 communityFeeToken0,
      uint8 communityFeeToken1,
      bool unlocked
    );

    /// @dev swap function for calculate amount
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external;

}
