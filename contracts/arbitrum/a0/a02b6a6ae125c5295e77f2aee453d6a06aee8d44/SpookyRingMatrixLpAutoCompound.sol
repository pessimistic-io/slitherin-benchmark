// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to spiritswap ring routing
contract SpookyRingMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant SPOOKYSWAP_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;

    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant BOO = 0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE;
    address internal constant RING = 0x582423C10c9e83387a96d00A69bA3D11ee47B7b5;

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
        partner = 0x370880694995Aa8A53F71645F7Bec3b0e7bb25d9;
        partnerFee = 4500;
        treasuryFee = 4500;
    }

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(SPOOKYSWAP_ROUTER);
        whitelistedAddresses.add(RING);
        whitelistedAddresses.add(BOO);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // BOO -> RING
        address[] memory _booRing = new address[](4);
        _booRing[0] = BOO;
        _booRing[1] = WFTM;
        _booRing[2] = USDC;
        _booRing[3] = RING;
        _setSwapPath(BOO, RING, SPOOKYSWAP_ROUTER, _booRing);

        // BOO -> USDC
        address[] memory _booUsdc = new address[](3);
        _booUsdc[0] = BOO;
        _booUsdc[1] = WFTM;
        _booUsdc[2] = USDC;
        _setSwapPath(BOO, USDC, SPOOKYSWAP_ROUTER, _booUsdc);

    }
}

