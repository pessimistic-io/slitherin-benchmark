// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./SpookyV2MatrixLpAutoCompound.sol";

/// @title SpookyV2MatrixLpAutoCompound adapted to SpookyV2 DEUS routing
contract DeusSpookyV2MatrixLpAutoCompound is SpookyV2MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant DEUS = 0xDE5ed76E7c05eC5e4572CfC88d1ACEA165109E44;
    address internal constant DEI = 0xDE12c7959E1a72bbe8a5f7A1dc8f8EeF9Ab011B3;

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _uniRouter,
        address _vault,
        address _treasury
    )
        SpookyV2MatrixLpAutoCompound(
            _want,
            _poolId,
            _masterchef,
            _output,
            address(0),
            _uniRouter,
            _vault,
            _treasury
        )
    {}

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(SPOOKYSWAP_ROUTER);
        whitelistedAddresses.add(DEUS);
        whitelistedAddresses.add(DEI);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // DEUS -> USDC
        address[] memory _deusUsdc = new address[](3);
        _deusUsdc[0] = DEUS;
        _deusUsdc[1] = WFTM;
        _deusUsdc[2] = USDC;
        _setSwapPath(DEUS, USDC, SPOOKYSWAP_ROUTER, _deusUsdc);

        // DEUS -> DEI
        address[] memory _deusDei = new address[](4);
        _deusDei[0] = DEUS;
        _deusDei[1] = WFTM;
        _deusDei[2] = USDC;
        _deusDei[3] = DEI;
        _setSwapPath(DEUS, DEI, SPOOKYSWAP_ROUTER, _deusDei);
    }

}

