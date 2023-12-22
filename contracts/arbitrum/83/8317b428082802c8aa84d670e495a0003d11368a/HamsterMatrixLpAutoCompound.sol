// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to Hamster routing
contract HamsterMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant SPOOKYSWAP_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;

    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant HAM = 0x20AC818b34A60117E12ffF5bE6AbbEF68BF32F6d;
    address internal constant HSHARE = 0xFFEAF32AB5F99F95a9B6dF177ef56D84fb40fc12;
    address internal constant GEM = 0x42e270Af1FeA762fCFCB65CDB9e3eFFEb2301533;

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
    {}

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(SPOOKYSWAP_ROUTER);
        whitelistedAddresses.add(HAM);
        whitelistedAddresses.add(HSHARE);
        whitelistedAddresses.add(GEM);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

    }
}

