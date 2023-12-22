// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to spiritswap ring routing
contract SpiritRingMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant SPIRITSWAP_ROUTER = 0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52;

    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant SPIRIT = 0x5Cc61A78F164885776AA610fb0FE1257df78E59B;
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
        whitelistedAddresses.add(SPIRITSWAP_ROUTER);
        whitelistedAddresses.add(RING);
        whitelistedAddresses.add(SPIRIT);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();
    }
}

