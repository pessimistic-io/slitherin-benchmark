// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";
import "./IUniswapV2Router02.sol";
import "./EnumerableSet.sol";

/// @title Base Lp+MasterChef AutoCompound Strategy Framework,
/// all LP strategies will inherit this contract
contract MatrixLpAutoCompoundDogechain is MatrixLpAutoCompound {
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
        wrapped = 0xB7ddC6414bf4F5515b52D8BdD69973Ae205ff101;
        treasury = 0xAA6481333fC2D213d38BE388f255b2647627f12b;
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

