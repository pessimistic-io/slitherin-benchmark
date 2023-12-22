// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

interface IMarketRegistry {
    struct MarketInfo {
        address pool;
        uint24 uniswapFeeRatio;
        uint24 insuranceFundFeeRatio;
        uint24 platformFundFeeRatio;
        uint24 optimalDeltaTwapRatio;
        uint24 unhealthyDeltaTwapRatio;
        uint24 optimalFundingRatio;
    }

    /// @notice Emitted when a new market is created.
    /// @param baseToken The address of the base token
    /// @param nftContract Fee ratio of the market
    /// @param pool The address of the pool
    event PoolAdded(
        address indexed baseToken,
        address nftContract,
        address creator,
        bool isIsolated,
        address indexed pool
    );

    /// @notice Emitted when the fee ratio of a market is updated.
    /// @param baseToken The address of the base token
    /// @param feeRatio Fee ratio of the market
    event PlatformFundFeeRatioChanged(address baseToken, uint24 feeRatio);

    /// @notice Emitted when the insurance fund fee ratio is updated.
    /// @param baseToken The address of the base token
    /// @param feeRatio Insurance fund fee ratio
    event InsuranceFundFeeRatioChanged(address baseToken, uint24 feeRatio);

    /// @notice Emitted when the max orders per market is updated.
    /// @param maxOrdersPerMarket Max orders per market
    event MaxOrdersPerMarketChanged(uint8 maxOrdersPerMarket);

    /// @notice Get the pool address (UNIv3 pool) by given base token address
    /// @param baseToken The address of the base token
    /// @return pool The address of the pool
    function getPool(address baseToken) external view returns (address pool);

    /// @notice Get the insurance fund fee ratio of a given market
    /// @dev The ratio is in `1e6` format, that means `1% = 1e4`
    /// @param baseToken The address of the base token
    /// @return feeRatio The fee ratio of the market, it is a decimal in `1e6`
    function getInsuranceFundFeeRatio(address baseToken) external view returns (uint24 feeRatio);

    /// @notice Get the insurance fund fee ratio of a given market
    /// @dev The ratio is in `1e6` format, that means `1% = 1e4`
    /// @param baseToken The address of the base token
    /// @return feeRatio The fee ratio of the market, it is a decimal in `1e6`
    function getPlatformFundFeeRatio(address baseToken) external view returns (uint24);

    /// @notice Get the insurance fund fee ratio of a given market
    /// @dev The ratio is in `1e6` format, that means `1% = 1e4`
    /// @param baseToken The address of the base token
    /// @return feeRatio The fee ratio of the market, it is a decimal in `1e6`
    function getOptimalDeltaTwapRatio(address baseToken) external view returns (uint24);

    /// @notice Get the insurance fund fee ratio of a given market
    /// @dev The ratio is in `1e6` format, that means `1% = 1e4`
    /// @param baseToken The address of the base token
    /// @return feeRatio The fee ratio of the market, it is a decimal in `1e6`
    function getOptimalFundingRatio(address baseToken) external view returns (uint24);

    /// @notice Get the market info by given base token address
    /// @param baseToken The address of the base token
    /// @return info The market info encoded as `MarketInfo`
    function getMarketInfo(address baseToken) external view returns (MarketInfo memory info);

    /// @notice Get the quote token address
    /// @return quoteToken The address of the quote token
    function getQuoteToken() external view returns (address quoteToken);

    /// @notice Get Uniswap factory address
    /// @return factory The address of the Uniswap factory
    function getUniswapV3Factory() external view returns (address factory);

    /// @notice Get max allowed orders per market
    /// @return maxOrdersPerMarket The max allowed orders per market
    function getMaxOrdersPerMarket() external view returns (uint8 maxOrdersPerMarket);

    /// @notice Check if a pool exist by given base token address
    /// @return hasPool True if the pool exist, false otherwise
    function hasPool(address baseToken) external view returns (bool);

    function getNftContract(address baseToken) external view returns (address);

    function getCreator(address baseToken) external view returns (address);

    function isIsolated(address baseToken) external view returns (bool);

    function getInsuranceFundFeeRatioGlobal() external view returns (uint24);

    function getPlatformFundFeeRatioGlobal() external view returns (uint24);

    function getOptimalDeltaTwapRatioGlobal() external view returns (uint24);

    function getUnhealthyDeltaTwapRatioGlobal() external view returns (uint24);

    function getOptimalFundingRatioGlobal() external view returns (uint24);

    function getSharePlatformFeeRatioGlobal() external view returns (uint24);

    function getMinQuoteTickCrossedGlobal() external view returns (uint256);

    function getMaxQuoteTickCrossedGlobal() external view returns (uint256);

    function getDefaultQuoteTickCrossedGlobal() external view returns (uint256);

    function getMinInsuranceFundPerContribution() external view returns (uint256);

    function getMinInsuranceFundPerCreated() external view returns (uint256);

    function isOpen(address baseToken) external view returns (bool);

    function createIsolatedPool(
        address nftContractArg,
        string memory symbolArg,
        uint160 sqrtPriceX96,
        address token,
        uint256 contributedAmount
    ) external returns (address baseToken, address uniPool);
}

