// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to claim BSHARE rewards from the correct routes
contract BasedMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant SPOOKYSWAP_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;

    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant TOMB = 0x6c021Ae822BEa943b2E66552bDe1D2696a53fbB7;
    address internal constant TSHARE = 0x4cdF39285D7Ca8eB3f090fDA0C069ba5F4145B37;
    address internal constant BSHARE = 0x49C290Ff692149A4E16611c694fdED42C954ab7a;
    address internal constant BASED = 0x8D7d3409881b51466B483B11Ea1B8A03cdEd89ae;
    address internal constant MAI = 0xfB98B335551a418cD0737375a2ea0ded62Ea213b;

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
        whitelistedAddresses.add(TOMB);
        whitelistedAddresses.add(TSHARE);
        whitelistedAddresses.add(BSHARE);
        whitelistedAddresses.add(BASED);
        whitelistedAddresses.add(MAI);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // BSHARE -> BASED
        address[] memory _bshareBased = new address[](2);
        _bshareBased[0] = BSHARE;
        _bshareBased[1] = BASED;
        _setSwapPath(BSHARE, BASED, SPOOKYSWAP_ROUTER, _bshareBased);

       // BSHARE -> TOMB
        address[] memory _bshareTomb = new address[](3);
        _bshareTomb[0] = BSHARE;
        _bshareTomb[1] = BASED;
        _bshareTomb[2] = TOMB;
        _setSwapPath(BSHARE, TOMB, SPOOKYSWAP_ROUTER, _bshareTomb);

        // BSHARE -> FTM
        address[] memory _bshareWFTM = new address[](2);
        _bshareWFTM[0] = BSHARE;
        _bshareWFTM[1] = WFTM;
        _setSwapPath(BSHARE, WFTM, SPOOKYSWAP_ROUTER, _bshareWFTM);

        // BSHARE -> MAI
        address[] memory _bshareMAI = new address[](4);
        _bshareMAI[0] = BSHARE;
        _bshareMAI[1] = WFTM;
        _bshareMAI[2] = USDC;
        _bshareMAI[3] = MAI;
        _setSwapPath(BSHARE, MAI, SPOOKYSWAP_ROUTER, _bshareMAI);
    }
}

