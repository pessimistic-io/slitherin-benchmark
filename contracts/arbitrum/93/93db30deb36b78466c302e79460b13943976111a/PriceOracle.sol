pragma solidity ^0.5.16;

import "./WToken.sol";

contract PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /**
      * @notice Get the underlying price of a cToken asset
      * @param cToken The cToken to get the underlying price of
      * @return The underlying asset price mantissa (scaled by 1e18).
      *  Zero means the price is unavailable.
      */
    function getUnderlyingPrice(WToken cToken) external view returns (uint);

    function setTokenConfigs(
        address[] calldata cTokenAddress,
        address[] calldata uniswapV3PoolAddresss,
        uint256[] calldata chainlinkPriceBase,
        uint256[] calldata underlyingTokenDecimals,
        uint256[] calldata underlyingBaseDecimals,
        bool[] calldata isEthToken0
    ) external;
}

