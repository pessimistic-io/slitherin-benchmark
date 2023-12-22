// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
pragma abicoder v2;

import "./ILodestar.sol";
import "./AggregatorV3Interface.sol";
import "./ISwap.sol";
import "./StatisticsBase.sol";

contract LodestarStatistics is StatisticsBase {
    address public swapRouter;
    address[] public pathToSwapLodeToStableCoin;

    /**
     * @notice Set PancakeSwap information
     */
    function setLodeSwapInfo(
        address _swapRouter,
        address[] calldata _pathToSwapLodeToStableCoin
    ) external onlyOwnerAndAdmin {
        swapRouter = _swapRouter;
        pathToSwapLodeToStableCoin = _pathToSwapLodeToStableCoin;
    }

    /**
     * @notice get USD price by Venus Oracle for xToken
     * @param xToken xToken address
     * @param comptroller comptroller address
     * @return priceUSD USD price for xToken (decimal = 18 + (18 - decimal of underlying))
     */
    function _getUnderlyingUSDPrice(address xToken, address comptroller)
        internal
        view
        override
        returns (uint256 priceUSD)
    {
        address oracle = IComptrollerLodestar(comptroller).oracle();
        address ethUsdAggregator = IOracleLodestar(oracle).ethUsdAggregator();

        priceUSD =
            (IOracleLodestar(oracle).getUnderlyingPrice(xToken) *
                uint256(
                    AggregatorV3Interface(ethUsdAggregator).latestAnswer()
                )) /
            (10**AggregatorV3Interface(ethUsdAggregator).decimals());
    }

    /**
     * @notice get rewards underlying token of startegy
     * @param comptroller comptroller address
     * @return rewardsToken rewards token address
     */
    function _getRewardsToken(address comptroller)
        internal
        view
        override
        returns (address rewardsToken)
    {
        rewardsToken = IDistributionLodestar(comptroller).getCompAddress();
    }

    /**
     * @notice get rewards underlying token price
     * @param comptroller comptroller address
     * @param rewardsToken Address of rewards token
     * @return priceUSD usd amount : (decimal = 18 + (18 - decimal of rewards token))
     */
    function _getRewardsTokenPrice(address comptroller, address rewardsToken)
        internal
        view
        override
        returns (uint256 priceUSD)
    {
        address tokenOut;
        uint256 amountOut;

        tokenOut = pathToSwapLodeToStableCoin[
            pathToSwapLodeToStableCoin.length - 1
        ];
        amountOut = ISwapGateway(swapGateway).quoteExactInput(
            swapRouter,
            10**IERC20MetadataUpgradeable(rewardsToken).decimals(),
            pathToSwapLodeToStableCoin
        );

        priceUSD =
            _getAmountUSDByOracle(tokenOut, amountOut) *
            (10 **
                (DECIMALS -
                    IERC20MetadataUpgradeable(rewardsToken).decimals()));
    }

    /**
     * @notice Get Strategy earned
     * @param logic Logic contract address
     * @param comptroller comptroller address
     * @return strategyEarned
     */
    function _getStrategyEarned(address logic, address comptroller)
        internal
        view
        override
        returns (uint256 strategyEarned)
    {
        address[] memory xTokenList = _getAllMarkets(comptroller);
        uint256 index;
        strategyEarned = 0;

        for (index = 0; index < xTokenList.length; ) {
            address xToken = xTokenList[index];
            uint256 borrowIndex = IXToken(xToken).borrowIndex();
            (uint224 supplyIndex, ) = IDistributionLodestar(comptroller)
                .compSupplyState(xToken);
            uint256 supplierIndex = IDistributionLodestar(comptroller)
                .compSupplierIndex(xToken, logic);
            (uint224 borrowState, ) = IDistributionLodestar(comptroller)
                .compBorrowState(xToken);
            uint256 borrowerIndex = IDistributionLodestar(comptroller)
                .compBorrowerIndex(xToken, logic);

            if (supplierIndex == 0 && supplyIndex > 0)
                supplierIndex = IDistributionLodestar(comptroller)
                    .compInitialIndex();

            strategyEarned +=
                (IERC20Upgradeable(xToken).balanceOf(logic) *
                    (supplyIndex - supplierIndex)) /
                10**36;

            if (borrowerIndex > 0) {
                uint256 borrowerAmount = (IXToken(xToken).borrowBalanceStored(
                    logic
                ) * 10**18) / borrowIndex;
                strategyEarned +=
                    (borrowerAmount * (borrowState - borrowerIndex)) /
                    10**36;
            }

            unchecked {
                ++index;
            }
        }

        strategyEarned += IDistributionLodestar(comptroller).compAccrued(logic);

        // Convert to USD using Strategy
        strategyEarned =
            (strategyEarned *
                _getRewardsTokenPrice(
                    comptroller,
                    _getRewardsToken(comptroller)
                )) /
            BASE;
    }

    /**
     * @notice Check xToken is for native token
     * @param xToken Address of xToken
     * @return isXNative true : xToken is for native token
     */
    function _isXNative(address xToken)
        internal
        view
        override
        returns (bool isXNative)
    {
        if (xToken == 0x2193c45244AF12C280941281c8aa67dD08be0a64)
            isXNative = true;
        else isXNative = false;
    }

    /**
     * @notice get collateralFactorMantissa of startegy
     * @param comptroller compotroller address
     * @return collateralFactorMantissa collateralFactorMantissa
     */
    function _getCollateralFactorMantissa(address xToken, address comptroller)
        internal
        view
        override
        returns (uint256 collateralFactorMantissa)
    {
        (, collateralFactorMantissa, ) = IComptrollerLodestar(comptroller)
            .markets(xToken);
    }

    /**
     * @notice get rewardsSpeed
     * @param _asset Address of asset
     * @param comptroller comptroller address
     */
    function _getRewardsSpeed(address _asset, address comptroller)
        internal
        view
        override
        returns (uint256)
    {
        return IDistributionLodestar(comptroller).compSpeeds(_asset);
    }

    /**
     * @notice get rewardsSupplySpeed
     * @param _asset Address of asset
     * @param comptroller comptroller address
     */
    function _getRewardsSupplySpeed(address _asset, address comptroller)
        internal
        view
        override
        returns (uint256)
    {
        return IDistributionLodestar(comptroller).compSupplySpeeds(_asset);
    }
}

