// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {IUniswapV3SingleTickLiquidityHandler} from "./IUniswapV3SingleTickLiquidityHandler.sol";
import {Math} from "./Math.sol";

library UniswapV3SingleTickLiquidityLib {
    function tokenId(
        IUniswapV3SingleTickLiquidityHandler handler,
        address pool,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(handler, pool, tickLower, tickUpper)));
    }

    /**
     * @dev convertToAssets means max amount of liquidity that can be withdrawn.
     * but it doesn't mean that all of them can be withdrawn. Some of them can be locked.
     * So we need to calculate the amount of liquidity that can be withdrawn.
     */
    function redeemableLiquidity(
        IUniswapV3SingleTickLiquidityHandler handler,
        address owner,
        uint256 tokenId_
    ) internal view returns (uint256 liquidity) {
        uint256 _shares = handler.balanceOf(owner, tokenId_);
        IUniswapV3SingleTickLiquidityHandler.TokenIdInfo memory _tki = handler.tokenIds(tokenId_);

        liquidity = Math.min(
            handler.convertToAssets(uint128(_shares), tokenId_),
            _tki.totalLiquidity - _tki.liquidityUsed
        );
    }

    function lockedLiquidity(
        IUniswapV3SingleTickLiquidityHandler handler,
        address owner,
        uint256 tokenId_
    ) internal view returns (uint256) {
        uint256 _shares = handler.balanceOf(owner, tokenId_);
        IUniswapV3SingleTickLiquidityHandler.TokenIdInfo memory _tki = handler.tokenIds(tokenId_);

        uint256 _maxRedeem = handler.convertToAssets(uint128(_shares), tokenId_);
        uint256 _freeLiquidity = _tki.totalLiquidity - _tki.liquidityUsed;

        if (_freeLiquidity >= _maxRedeem) return 0;

        return _maxRedeem - _freeLiquidity;
    }

    /// @dev currently unused
    function donationLocked(
        IUniswapV3SingleTickLiquidityHandler handler,
        uint256 tokenId_
    ) internal view returns (uint128) {
        IUniswapV3SingleTickLiquidityHandler.TokenIdInfo memory _tki = handler.tokenIds(tokenId_);

        if (block.number >= _tki.lastDonation + handler.lockedBlockDuration()) {
            return 0;
        }

        return
            _tki.donatedLiquidity -
            ((_tki.donatedLiquidity * (uint64(block.number) - _tki.lastDonation)) / handler.lockedBlockDuration());
    }
}

