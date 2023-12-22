// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompoundOptimism.sol";
import "./IUniswapV2Router02.sol";
import "./EnumerableSet.sol";

/// @title Base Lp+MasterChef AutoCompound Strategy Framework,
/// all LP strategies will inherit this contract
contract MatrixLpAutoCompoundMultiOptimism is MatrixLpAutoCompoundOptimism {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public output2;

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _output2,
        address _uniRouter,
        address _vault,
        address _treasury
    )
        MatrixLpAutoCompoundOptimism(
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
        // It can be address(0), for single rewards pools
        output2 = _output2;
        if (output2 != address(0)) {
            whitelistedAddresses.add(output2);
        }
        _setDefaultSwapPaths();
    }

    function _setDefaultSwapPaths() internal virtual override {
        super._setDefaultSwapPaths();

        if (output2 != address(0)) {
            address _oldOutput = output;
            output = output2;

            super._setDefaultSwapPaths();

            output = _oldOutput;
        }
    }

    function _harvest()
        internal
        virtual
        override
        returns (uint256 _wantHarvested, uint256 _wrappedFeesAccrued)
    {
        (_wantHarvested, _wrappedFeesAccrued) = super._harvest();
        if (output2 != address(0)) {
            address _oldOutput = output;
            output = output2;

            (
                uint256 _wantHarvestedFromOutput2,
                uint256 _wrappedFeesAccruedFromOutput2
            ) = super._harvest();

            output = _oldOutput;

            _wantHarvested += _wantHarvestedFromOutput2;

            if (lpToken0 == wrapped || lpToken1 == wrapped) {
                // Anything left here in wrapped after adding liquidity
                // Are fees accrued
                _wrappedFeesAccrued = IERC20(wrapped).balanceOf(address(this));
            } else {
                _wrappedFeesAccrued += _wrappedFeesAccruedFromOutput2;
            }
        }
    }
}

