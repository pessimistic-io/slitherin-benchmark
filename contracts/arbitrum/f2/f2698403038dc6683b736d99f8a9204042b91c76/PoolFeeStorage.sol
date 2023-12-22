// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./IERC20.sol";
import "./TransferHelper.sol";

import "./IDEXPool.sol";

contract PoolFeeStorage {
    IDEXPool pool;

    uint256[] public accumulatedFees;

    event PoolFeeCollected(uint256 fee0, uint256 fee1);
    event FeeSwapped(address indexed from, address to, uint256 amount);

    constructor(address poolAddress) {
        pool = IDEXPool(poolAddress);
        accumulatedFees = new uint256[](2);
    }

    function getPool() external view returns (address) {
        return address(pool);
    }

    function _collectPoolFees() internal {
        (uint256 collectableFee0, uint256 collectableFee1) = pool.getFeesToCollect();

        if (collectableFee0 != 0 || collectableFee1 != 0) {
            pool.collect(address(this), uint128(collectableFee0), uint128(collectableFee1));
            accumulatedFees[0] += collectableFee0;
            accumulatedFees[1] += collectableFee1;
        }

        emit PoolFeeCollected(collectableFee0, collectableFee1);
    }

    function collectedPoolFees() public view returns (uint256 token0, uint256 token1) {
        address[] memory tokens = pool.getTokens();
        token0 = IERC20(tokens[0]).balanceOf(address(this));
        token1 = IERC20(tokens[1]).balanceOf(address(this));
    }

    function _swapToken0ToToken1(uint256 token0Amount) internal {
        address[] memory tokens = pool.getTokens();
        uint256 token0Balance = IERC20(tokens[0]).balanceOf(address(this));
        require(token0Balance >= token0Amount, "Insufficient balance");

        _swapFeeTokens(tokens[0], tokens[1], token0Amount);

        emit FeeSwapped(tokens[0], tokens[1], token0Amount);
    }

    function _swapToken1ToToken0(uint256 token1Amount) internal {
        address[] memory tokens = pool.getTokens();
        uint256 token1Balance = IERC20(tokens[1]).balanceOf(address(this));
        require(token1Balance >= token1Amount, "Insufficient balance");

        _swapFeeTokens(tokens[1], tokens[0], token1Amount);

        emit FeeSwapped(tokens[1], tokens[0], token1Amount);
    }

    function _swapFeeTokens(address from, address to, uint256 amountIn) private returns (uint256 amountOut) {
        TransferHelper.safeApprove(from, address(pool), amountIn);
        amountOut = pool.swapExactInputSingle(IERC20(from), IERC20(to), amountIn);
    } 
}
