// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";
import "./IUniswapV2Router02.sol";
import "./EnumerableSet.sol";

/// @title Base Lp+MasterChef AutoCompound Strategy Framework,
/// all LP strategies will inherit this contract
contract MatrixLpAutoCompoundOptimism is MatrixLpAutoCompound {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _uniRouter,
        address _vault,
        address _treasury
    )
        MatrixLpAutoCompound(
            _want,
            _poolId,
            _masterchef,
            _output,
            _uniRouter,
            _vault,
            _treasury
        )
    {
        wrapped = 0x4200000000000000000000000000000000000006;
        treasury = 0xEaD9f532C72CF35dAb18A42223eE7A1B19bC5aBF;
        _setDefaultSwapPaths();
    }

    function _beforeWithdraw(uint256 _amount) internal override {
        IMasterChef(masterchef).withdrawAndHarvestShort(
            poolId,
            uint128(_amount)
        );
    }

    function _beforeHarvest() internal override {
        IMasterChef(masterchef).harvestShort(poolId);
    }

    function _deposit() internal virtual override {
        uint256 _wantBalance = IERC20(want).balanceOf(address(this));
        IMasterChef(masterchef).depositShort(poolId, uint128(_wantBalance));
    }

    function _beforePanic() internal virtual override {
        IMasterChef(masterchef).withdrawAll(poolId);
    }

}

