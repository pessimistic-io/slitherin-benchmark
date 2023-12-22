// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

abstract contract SharedLiquidity {
    function _sharesFromLiquidityDelta(
        uint256 liquidityBefore,
        uint256 liquidityAfter
    ) internal view returns (uint256) {
        uint256 totalShares_ = totalShares();
        uint256 liquidityDelta = liquidityAfter - liquidityBefore;
        if (totalShares_ == 0) {
            return liquidityDelta;
        } else {
            return (liquidityDelta * totalShares_) / liquidityBefore;
        }
    }

    function _toLiquidity(uint256 shares) internal view returns (uint256) {
        return (shares * totalLiquidity()) / totalShares();
    }

    function totalShares() public view virtual returns (uint256);

    function totalLiquidity() public view virtual returns (uint256);

    function _withdrawShares(uint256 shares) internal virtual;
}

