// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to dante routing
contract DanteMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant SPOOKYSWAP_ROUTER = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;

    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant TOMB = 0x6c021Ae822BEa943b2E66552bDe1D2696a53fbB7;
    address internal constant GRAIL = 0x255861B569D44Df3E113b6cA090a1122046E6F89;
    address internal constant DANTE = 0xDA763530614fb51DFf9673232C8B3b3e0A67bcf2;


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
        partner = 0x698d286d660B298511E49dA24799d16C74b5640D;
        partnerFee = 1000;
        treasuryFee = 8000;
    }

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(SPOOKYSWAP_ROUTER);
        whitelistedAddresses.add(GRAIL);
        whitelistedAddresses.add(TOMB);
        whitelistedAddresses.add(DANTE);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // GRAIL -> DANTE
        address[] memory _grailDante = new address[](4);
        _grailDante[0] = GRAIL;
        _grailDante[1] = WFTM;
        _grailDante[2] = TOMB;
        _grailDante[3] = DANTE;
        _setSwapPath(GRAIL, DANTE, SPOOKYSWAP_ROUTER, _grailDante);

        // GRAIL -> TOMB
        address[] memory _grailTomb = new address[](3);
        _grailTomb[0] = GRAIL;
        _grailTomb[1] = WFTM;
        _grailTomb[2] = TOMB;
        _setSwapPath(GRAIL, TOMB, SPOOKYSWAP_ROUTER, _grailTomb);
    }
}
