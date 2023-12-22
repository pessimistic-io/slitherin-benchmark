// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./SpookyV2MatrixLpAutoCompound.sol";

/// @title SpookyV2MatrixLpAutoCompound adapted to SpookyV2 SD routing
contract SdSpookyV2MatrixLpAutoCompound is SpookyV2MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant SD = 0x412a13C109aC30f0dB80AD3Bd1DeFd5D0A6c0Ac6;
    address internal constant SFTMX =
        0xd7028092c830b5C8FcE061Af2E593413EbbC1fc1;
    address internal constant BOO = 0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE;

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
        SpookyV2MatrixLpAutoCompound(
            _want,
            _poolId,
            _masterchef,
            _output,
            _output2,
            _uniRouter,
            _vault,
            _treasury
        )
    {}

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(SD);
        whitelistedAddresses.add(SFTMX);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // FTM -> SD
        address[] memory _ftmSd = new address[](3);
        _ftmSd[0] = WFTM;
        _ftmSd[1] = USDC;
        _ftmSd[2] = SD;
        _setSwapPath(WFTM, SD, SPOOKYSWAP_ROUTER, _ftmSd);

        // SD -> USDC
        address[] memory _sdUsdc = new address[](2);
        _sdUsdc[0] = SD;
        _sdUsdc[1] = USDC;
        _setSwapPath(SD, USDC, SPOOKYSWAP_ROUTER, _sdUsdc);

        // USDC -> SD
        address[] memory _usdcSd = new address[](2);
        _usdcSd[0] = USDC;
        _usdcSd[1] = SD;
        _setSwapPath(USDC, SD, SPOOKYSWAP_ROUTER, _usdcSd);

        // SD -> FTM
        address[] memory _sdFtm = new address[](3);
        _sdFtm[0] = SD;
        _sdFtm[1] = USDC;
        _sdFtm[2] = WFTM;
        _setSwapPath(SD, WFTM, SPOOKYSWAP_ROUTER, _sdFtm);

        // SD -> sFTMx
        address[] memory _sdSftmx = new address[](4);
        _sdSftmx[0] = SD;
        _sdSftmx[1] = USDC;
        _sdSftmx[2] = WFTM;
        _sdSftmx[3] = SFTMX;
        _setSwapPath(SD, SFTMX, SPOOKYSWAP_ROUTER, _sdSftmx);

        // BOO -> SD
        address[] memory _booSd = new address[](4);
        _booSd[0] = BOO;
        _booSd[1] = WFTM;
        _booSd[2] = USDC;
        _booSd[3] = SD;
        _setSwapPath(BOO, SD, SPOOKYSWAP_ROUTER, _booSd);
    }
}

