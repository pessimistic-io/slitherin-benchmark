// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to ChargeDEFI routing
contract ChargeDefiMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant SPOOKYSWAP_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;

    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant STATIC = 0x27182C8b647fd83603bB442C0E450DE7445ccfB8;
    address internal constant CHARGE = 0xe74621A75C6ADa86148b62Eef0894E05444EAE69;

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
        whitelistedAddresses.add(STATIC);
        whitelistedAddresses.add(CHARGE);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // Charge -> Static
        address[] memory _chargeStatic = new address[](3);
        _chargeStatic[0] = CHARGE;
        _chargeStatic[1] = USDC;
        _chargeStatic[2] = STATIC;
        _setSwapPath(CHARGE, STATIC, SPOOKYSWAP_ROUTER, _chargeStatic);

        // Charge -> USDC
        address[] memory _chargeUsdc = new address[](2);
        _chargeUsdc[0] = CHARGE;
        _chargeUsdc[1] = USDC;
        _setSwapPath(CHARGE, USDC, SPOOKYSWAP_ROUTER, _chargeUsdc);

        // Charge -> WFTM
        address[] memory _chargeWftm = new address[](3);
        _chargeWftm[0] = CHARGE;
        _chargeWftm[1] = USDC;
        _chargeWftm[2] = WFTM;
        _setSwapPath(CHARGE, WFTM, SPOOKYSWAP_ROUTER, _chargeWftm);
    }

    function _deposit() internal override {
        uint256 _wantBalance = IERC20(want).balanceOf(address(this));
        IMasterChef(masterchef).deposit(_wantBalance, poolId);
    }
}

