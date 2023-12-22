// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.17;

import "./IERC20.sol";

interface ILiquidator {
    struct LiquidationData {
        address user;
        ICERC20 borrowMarketAddress;
        uint256 loanAmount;
        ICERC20 collateralMarketAddress;
    }

    struct MarketData {
        address underlyingAddress;
        address wethPair;
        address usdcPair;
    }

    error UNAUTHORIZED(string);
    error INVALID_APPROVAL();
    error FAILED(string);
}

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);
}

interface ICERC20 is IERC20 {
    // CToken
    /**
     * @notice Get the underlying balance of the `owner`
     * @dev This also accrues interest in a transaction
     * @param owner The address of the account to query
     * @return The amount of underlying owned by `owner`
     */
    function balanceOfUnderlying(address owner) external returns (uint256);

    /**
     * @notice Returns the current per-block borrow interest rate for this cToken
     * @return The borrow interest rate per block, scaled by 1e18
     */
    function borrowRatePerBlock() external view returns (uint256);

    /**
     * @notice Returns the current per-block supply interest rate for this cToken
     * @return The supply interest rate per block, scaled by 1e18
     */
    function supplyRatePerBlock() external view returns (uint256);

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external returns (uint256);

    // Cerc20
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function underlying() external view returns (address);

    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) external;

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface SushiRouterInterface {
    function WETH() external returns (address);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        fixed swapAmountETH,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;
}

interface PriceOracleProxyETHInterface {
    function getUnderlyingPrice(address lToken) external returns (uint256);

    struct AggregatorInfo {
        address source;
        uint8 base;
    }

    function aggregators(address lToken) external returns (AggregatorInfo memory);
}

interface IPlutusDepositor {
    function redeem(uint256 amount) external;

    function redeemAll() external;
}

interface IGLPRouter {
    function unstakeAndRedeemGlpETH(
        uint256 _glpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external returns (uint256);

    function unstakeAndRedeemGlp(address tokenOut, uint256 glpAmount, uint256 minOut, address receiver) external returns (uint256);
}

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

interface ICETH is ICERC20 {
    function liquidateBorrow(
        address borrower,
        ICERC20 cTokenCollateral
    ) external payable;
}

