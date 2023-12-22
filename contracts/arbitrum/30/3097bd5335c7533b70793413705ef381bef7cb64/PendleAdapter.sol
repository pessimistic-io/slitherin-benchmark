// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "./TransferHelper.sol";
import "./PendleLpOracleLib.sol";
import "./BoringLpSeller.sol";

import "./SuAuthenticated.sol";
import "./ILPAdapter.sol";
import "./ISuOracleAggregator.sol";

struct PendleLPInfo {
    IPMarket market;
    IStandardizedYield SY;
    IPPrincipalToken PT;
    IPYieldToken YT;
    address[] underlyingTokens;
    address mainUnderlyingToken;
}

/**
 * @title PendleAdapter
 * @notice Adapter for Pendle LP token.
 * @dev See ILPAdapter interface for full details.
 */
contract PendleAdapter is SuAuthenticated, ILPAdapter, BoringLpSeller {
    using PendleLpOracleLib for IPMarket;

    mapping(address => PendleLPInfo) public lps; // Mapping from LP token to pool
    ISuOracleAggregator public ORACLE;
    address[] public underlyingTokens;

    function initialize(address _authControl, address _oracle) public initializer {
        __suAuthenticatedInit(_authControl);
        ORACLE = ISuOracleAggregator(_oracle);
    }

    /**
      * @notice Register the given LP token address and set the LP info
      * @param lp address of LP token
      * @param market market for LP token
     **/
    // Is LP == market?
    function registerLP(address lp, IPMarket market, address mainUnderlyingToken) external onlyAdmin {
        lps[lp].market = market;
        (lps[lp].SY, lps[lp].PT, lps[lp].YT) = market.readTokens();
        lps[lp].underlyingTokens = lps[lp].SY.getTokensOut();
        lps[lp].mainUnderlyingToken = mainUnderlyingToken;
    }

    function isAdapterLP(address asset) public view returns (bool) {
        return lps[asset].underlyingTokens.length != 0;
    }

    /// @notice Is depreceted, only for tests usage
    function getFiatPrice1e18Unsafe(address asset) external view returns (uint256) {
        PendleLPInfo memory lpInfo = lps[asset];

        uint256 assetPrice = ORACLE.getFiatPrice1e18(lpInfo.SY.yieldToken());
        uint256 underlyingTokensValue =
            (IERC20(lpInfo.SY).balanceOf(asset)
            + IERC20(lpInfo.PT).balanceOf(asset)
            + IERC20(lpInfo.YT).balanceOf(asset)) * assetPrice;
//        address[] memory rewardTokens = lpInfo.market.getRewardTokens();
//        for (uint16 i = 0; i < rewardTokens.length; ++i) {
//            address token = rewardTokens[i];
//            underlyingTokensValue += IERC20(token).balanceOf(asset) * ORACLE.getFiatPrice1e18(token);
//        }
        return underlyingTokensValue / lpInfo.market.totalSupply();
    }

    function getFiatPrice1e18(address asset) external view returns (uint256) {
        if (!isAdapterLP(asset)) revert IsNotLP(asset);
        PendleLPInfo memory lpInfo = lps[asset];

        uint256 lpRate = lpInfo.market.getLpToAssetRate(300); // TWAPDuration is 5min
        uint256 assetPrice = ORACLE.getFiatPrice1e18(lpInfo.mainUnderlyingToken);
        // TODO: check decimals
        return assetPrice * lpRate / 1e18;
    }

    function withdraw(address asset, uint256 amount) external returns (WithdrawResult[] memory results) {
        if (!isAdapterLP(asset)) revert IsNotLP(asset);
        TransferHelper.safeTransferFrom(asset, msg.sender, address(this), amount);
        PendleLPInfo memory lpInfo = lps[asset];

        uint256 nTokens = lpInfo.underlyingTokens.length;
        results = new WithdrawResult[](1);

        address bestTokenOut;
        uint256 bestTokenAmountOut;
        for (uint16 i = 0; i < nTokens; ++i) {
            address tokenToPreview = lpInfo.underlyingTokens[i];
            if (ORACLE.hasPriceForAsset(tokenToPreview)) {
                uint256 previewAmount =
                    lpInfo.SY.previewRedeem(tokenToPreview, amount) * ORACLE.getFiatPrice1e18(tokenToPreview);
                if (previewAmount > bestTokenAmountOut) {
                    bestTokenAmountOut = previewAmount;
                    bestTokenOut = tokenToPreview;
                }
            }
        }

        uint256 netTokenOut = _sellLpForToken(address(lpInfo.market), amount, bestTokenOut);

        results[0] = WithdrawResult({ token: bestTokenOut, amount: netTokenOut });
        TransferHelper.safeTransfer(bestTokenOut, msg.sender, netTokenOut);
    }

    uint256[45] private __gap;
}

