// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./IUniswapV3Pool.sol";
import "./SafeERC20Namer.sol";

import "./ChainId.sol";
import "./INonfungiblePositionManager.sol";
import "./INonfungibleTokenPositionDescriptor.sol";
import "./IERC20Metadata.sol";
import "./PoolAddress.sol";
import "./NFTDescriptor1EX.sol";
import "./TokenRatioSortOrder.sol";

/// @title Describes NFT token positions
/// @notice Produces a string containing the data URI for a JSON metadata string
contract NonfungibleTokenPositionDescriptor1EX is INonfungibleTokenPositionDescriptor {
    address private constant DAI_ETH = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC_ETH = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT_ETH = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant TBTC_ETH = 0x8dAEBADE922dF735c38C80C7eBD708Af50815fAa;
    address private constant WBTC_ETH = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address private constant BUSD_BSC = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address private constant DAI_BSC = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3;
    address private constant USDC_BSC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address private constant USDT_BSC = 0x55d398326f99059fF775485246999027B3197955;
    address private constant WETH_BSC = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    address private constant BTCB_BSC = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;

    address public immutable WNative;

    constructor(address _WNative) {
        WNative = _WNative;
    }

    /// @inheritdoc INonfungibleTokenPositionDescriptor
    function tokenURI(
        INonfungiblePositionManager positionManager,
        uint256 tokenId
    ) external view override returns (string memory) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            ,
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);

        IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(
                positionManager.factory(),
                PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})
            )
        );

        bool _flipRatio = flipRatio(token0, token1, ChainId.get());
        address quoteTokenAddress = !_flipRatio ? token1 : token0;
        address baseTokenAddress = !_flipRatio ? token0 : token1;

        return
            NFTDescriptor1EX.constructTokenURI(
                NFTDescriptor1EX.ConstructTokenURIParams({
                    tokenId: tokenId,
                    quoteTokenAddress: quoteTokenAddress,
                    baseTokenAddress: baseTokenAddress,
                    quoteTokenSymbol: SafeERC20Namer.tokenSymbol(quoteTokenAddress),
                    baseTokenSymbol: SafeERC20Namer.tokenSymbol(baseTokenAddress),
                    quoteTokenDecimals: IERC20Metadata(quoteTokenAddress).decimals(),
                    baseTokenDecimals: IERC20Metadata(baseTokenAddress).decimals(),
                    flipRatio: _flipRatio,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    tickSpacing: pool.tickSpacing(),
                    fee: fee,
                    poolAddress: address(pool)
                })
            );
    }

    function flipRatio(
        address token0,
        address token1,
        uint256 chainId
    ) public view returns (bool) {
        return
            tokenRatioPriority(token0, chainId) > tokenRatioPriority(token1, chainId);
    }

    function tokenRatioPriority(
        address token,
        uint256 chainId
    ) public view returns (int256) {
        if (token == WNative) {
            return TokenRatioSortOrder.DENOMINATOR;
        } else if (chainId == 1) {
            if (token == USDC_ETH) {
                return TokenRatioSortOrder.NUMERATOR_MOST;
            } else if (token == USDT_ETH) {
                return TokenRatioSortOrder.NUMERATOR_MORE;
            } else if (token == DAI_ETH) {
                return TokenRatioSortOrder.NUMERATOR;
            } else if (token == TBTC_ETH) {
                return TokenRatioSortOrder.DENOMINATOR_MORE;
            } else if (token == WBTC_ETH) {
                return TokenRatioSortOrder.DENOMINATOR_MOST;
            } else {
                return 0;
            }
        } else if (chainId == 56) {
            if (token == BUSD_BSC) {
                return TokenRatioSortOrder.NUMERATOR_MOST;
            } else if (token == USDC_BSC) {
                return TokenRatioSortOrder.NUMERATOR_MOST;
            } else if (token == USDT_BSC) {
                return TokenRatioSortOrder.NUMERATOR_MORE;
            } else if (token == DAI_BSC) {
                return TokenRatioSortOrder.NUMERATOR;
            } else if (token == WETH_BSC) {
                return TokenRatioSortOrder.DENOMINATOR_MORE;
            } else if (token == BTCB_BSC) {
                return TokenRatioSortOrder.DENOMINATOR_MOST;
            } else {
                return 0;
            }
        }

        return 0;
    }
}

