// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to kibbleswap for custom routing
contract KibbleswapMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant KIBBLESWAP_ROUTER = 0x6258c967337D3faF0C2ba3ADAe5656bA95419d5f;

    address internal constant WWDOGE = 0xB7ddC6414bf4F5515b52D8BdD69973Ae205ff101;
    address internal constant KIB = 0x1e1026ba0810e6391b0F86AFa8A9305c12713B66;
    address internal constant USDTS = 0x7f8e71DD5A7e445725F0EF94c7F01806299e877A;
    address internal constant USDTM = 0xE3F5a90F9cb311505cd691a46596599aA1A0AD7D;
    address internal constant USDCS = 0x85C2D3bEBffD83025910985389aB8aD655aBC946;
    address internal constant USDCM = 0x765277EebeCA2e31912C9946eAe1021199B39C61;
    address internal constant DAIS = 0xB3306f03595490e5cC3a1b1704a5a158D3436ffC;
    address internal constant DAIM = 0x639A647fbe20b6c8ac19E48E2de44ea792c62c5C;
    address internal constant ETHS = 0x9F4614E4Ea4A0D7c4B1F946057eC030beE416cbB;
    address internal constant ETHM = 0xB44a9B6905aF7c801311e8F4E76932ee959c663C;

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

    function _initialize(address _masterchef, address _output, uint256 _poolId) internal override {
        wrapped = 0xB7ddC6414bf4F5515b52D8BdD69973Ae205ff101;
        treasury = 0xAA6481333fC2D213d38BE388f255b2647627f12b;
        USDC = address(0x765277EebeCA2e31912C9946eAe1021199B39C61);

        partner = address(0x1E3d78C7cA0cb7D3EdF8682708a0c741d8AB12f0);
        treasuryFee = 6250;
        partnerFee = 2750;

        super._initialize(_masterchef, _output, _poolId);
    }

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(KIBBLESWAP_ROUTER);
        whitelistedAddresses.add(WWDOGE);
        whitelistedAddresses.add(USDTS);
        whitelistedAddresses.add(USDTM);
        whitelistedAddresses.add(DAIS);
        whitelistedAddresses.add(DAIM);
        whitelistedAddresses.add(ETHS);
        whitelistedAddresses.add(ETHM);
        whitelistedAddresses.add(USDCS);
        whitelistedAddresses.add(USDCM);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // KIB -> USDCS
        address[] memory _kibUSDCS = new address[](3);
        _kibUSDCS[0] = KIB;
        _kibUSDCS[1] = USDCM;
        _kibUSDCS[2] = USDCS;
        _setSwapPath(KIB, USDCS, KIBBLESWAP_ROUTER, _kibUSDCS);

        // KIB -> USDTS
        address[] memory _kibUSDTS = new address[](4);
        _kibUSDTS[0] = KIB;
        _kibUSDTS[1] = WWDOGE;
        _kibUSDTS[2] = USDTM;
        _kibUSDTS[3] = USDTS;
        _setSwapPath(KIB, USDTS, KIBBLESWAP_ROUTER, _kibUSDTS);

        // KIB -> ETHS
        address[] memory _kibETHS = new address[](4);
        _kibETHS[0] = KIB;
        _kibETHS[1] = WWDOGE;
        _kibETHS[2] = ETHM;
        _kibETHS[3] = ETHS;
        _setSwapPath(KIB, ETHS, KIBBLESWAP_ROUTER, _kibETHS);

        // KIB -> DAIS
        address[] memory _kibDAIS = new address[](4);
        _kibDAIS[0] = KIB;
        _kibDAIS[1] = WWDOGE;
        _kibDAIS[2] = DAIM;
        _kibDAIS[3] = DAIS;
        _setSwapPath(KIB, DAIS, KIBBLESWAP_ROUTER, _kibDAIS);
    }
}

