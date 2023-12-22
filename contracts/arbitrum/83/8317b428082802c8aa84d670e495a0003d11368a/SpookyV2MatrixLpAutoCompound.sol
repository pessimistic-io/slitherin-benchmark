// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to SpookyV2 DEUS routing
contract SpookyV2MatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    address internal constant SPOOKYSWAP_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;

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

    function _setWhitelistedAddresses() internal virtual override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(SPOOKYSWAP_ROUTER);
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

    function _beforePanic() internal override {
        IMasterChef(masterchef).emergencyWithdraw(poolId, address(this));
    }
}
