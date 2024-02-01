//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Metadata.sol";
import "./SafeERC20.sol";

import "./Constants.sol";
import "./ICurvePool.sol";
import "./IStableConverter.sol";

//import "hardhat/console.sol";

contract StableConverter is IStableConverter {
    using SafeERC20 for IERC20Metadata;

    uint256 public constant SLIPPAGE_DENOMINATOR = 10_000;

    ICurvePool public curve3Pool;

    uint256 public defaultSlippage = 30; // 0.3%

    mapping(address => int128) public curve3PoolStableIndex;
    mapping(address => int8) public curve3PoolStableDecimals;

    constructor() {
        curve3Pool = ICurvePool(Constants.CRV_3POOL_ADDRESS);

        curve3PoolStableIndex[Constants.DAI_ADDRESS] = 0; //DAI
        curve3PoolStableDecimals[Constants.DAI_ADDRESS] = 18;

        curve3PoolStableIndex[Constants.USDC_ADDRESS] = 1; //USDC
        curve3PoolStableDecimals[Constants.USDC_ADDRESS] = 6;

        curve3PoolStableIndex[Constants.USDT_ADDRESS] = 2; //USDT
        curve3PoolStableDecimals[Constants.USDT_ADDRESS] = 6;
    }

    function handle(
        address from,
        address to,
        uint256 amount,
        uint256 slippage
    ) public {
        IERC20Metadata(from).safeApprove(address(curve3Pool), amount);

        curve3Pool.exchange(
            curve3PoolStableIndex[from],
            curve3PoolStableIndex[to],
            amount,
            applySlippage(
                amount,
                slippage,
                curve3PoolStableDecimals[to] - curve3PoolStableDecimals[from]
            )
        );

        IERC20Metadata(to).safeTransfer(
            address(msg.sender),
            IERC20Metadata(to).balanceOf(address(this))
        );
    }

    function valuate(
        address from,
        address to,
        uint256 amount
    ) public view returns (uint256) {
        return curve3Pool.get_dy(curve3PoolStableIndex[from], curve3PoolStableIndex[to], amount);
    }

    function applySlippage(
        uint256 amount,
        uint256 slippage,
        int8 decimalsDiff
    ) internal view returns (uint256) {
        require(slippage <= SLIPPAGE_DENOMINATOR, 'Wrong slippage');
        if (slippage == 0) slippage = defaultSlippage;
        uint256 value = (amount * (SLIPPAGE_DENOMINATOR - slippage)) / SLIPPAGE_DENOMINATOR;
        if (decimalsDiff == 0) return value;
        if (decimalsDiff < 0) return value / (10**uint8(decimalsDiff * (-1)));
        return value * (10**uint8(decimalsDiff));
    }
}

