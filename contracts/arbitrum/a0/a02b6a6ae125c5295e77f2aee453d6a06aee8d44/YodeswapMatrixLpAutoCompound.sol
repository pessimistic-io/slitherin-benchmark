// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to yodeswap for custom routing
contract YodeswapMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant YODESWAP_ROUTER = 0x72d85Ab47fBfc5E7E04a8bcfCa1601D8f8cE1a50;

    address internal constant WWDOGE = 0xB7ddC6414bf4F5515b52D8BdD69973Ae205ff101;
    address internal constant YODE = 0x6FC4563460d5f45932C473334d5c1C5B4aEA0E01;
    address internal constant USDCM = 0x765277EebeCA2e31912C9946eAe1021199B39C61;
    address internal constant USDTM = 0xE3F5a90F9cb311505cd691a46596599aA1A0AD7D;
    address internal constant DAIM = 0x639A647fbe20b6c8ac19E48E2de44ea792c62c5C;
    address internal constant ETHM = 0xB44a9B6905aF7c801311e8F4E76932ee959c663C;
    address internal constant BTC = 0xfA9343C3897324496A05fC75abeD6bAC29f8A40f;
    address internal constant BUSD = 0x332730a4F6E03D9C55829435f10360E13cfA41Ff;
    address internal constant BNB = 0xA649325Aa7C5093d12D6F98EB4378deAe68CE23F;

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

        partner = address(0x2a2e3486204C9EEeab2BeF8faa3356Bc19e9db6F);
        treasuryFee = 6800;
        partnerFee = 2200;

        super._initialize(_masterchef, _output, _poolId);
    }

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(YODESWAP_ROUTER);
        whitelistedAddresses.add(WWDOGE);
        whitelistedAddresses.add(USDCM);
        whitelistedAddresses.add(USDTM);
        whitelistedAddresses.add(DAIM);
        whitelistedAddresses.add(ETHM);
        whitelistedAddresses.add(BTC);
        whitelistedAddresses.add(BUSD);
        whitelistedAddresses.add(BNB);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // YODE -> USDC
        address[] memory _yodeUSDCM = new address[](3);
        _yodeUSDCM[0] = YODE;
        _yodeUSDCM[1] = WWDOGE;
        _yodeUSDCM[2] = USDCM;
        _setSwapPath(YODE, USDCM, YODESWAP_ROUTER, _yodeUSDCM);

        // YODE -> USDT
        address[] memory _yodeUSDT = new address[](4);
        _yodeUSDT[0] = YODE;
        _yodeUSDT[1] = WWDOGE;
        _yodeUSDT[2] = USDCM;
        _yodeUSDT[3] = USDTM;
        _setSwapPath(YODE, USDTM, YODESWAP_ROUTER, _yodeUSDT);

        // YODE -> ETH
        address[] memory _yodeETH = new address[](4);
        _yodeETH[0] = YODE;
        _yodeETH[1] = WWDOGE;
        _yodeETH[2] = USDCM;
        _yodeETH[3] = ETHM;
        _setSwapPath(YODE, ETHM, YODESWAP_ROUTER, _yodeETH);

        // YODE -> BTC
        address[] memory _yodeBTC = new address[](4);
        _yodeBTC[0] = YODE;
        _yodeBTC[1] = WWDOGE;
        _yodeBTC[2] = USDCM;
        _yodeBTC[3] = BTC;
        _setSwapPath(YODE, BTC, YODESWAP_ROUTER, _yodeBTC);

        // YODE -> BUSD
        address[] memory _yodeBUSD = new address[](4);
        _yodeBUSD[0] = YODE;
        _yodeBUSD[1] = WWDOGE;
        _yodeBUSD[2] = USDCM;
        _yodeBUSD[3] = BUSD;
        _setSwapPath(YODE, BUSD, YODESWAP_ROUTER, _yodeBUSD);

        // YODE -> BNB
        address[] memory _yodeBNB = new address[](5);
        _yodeBNB[0] = YODE;
        _yodeBNB[1] = WWDOGE;
        _yodeBNB[2] = USDCM;
        _yodeBNB[3] = BUSD;
        _yodeBNB[4] = BNB;
        _setSwapPath(YODE, BNB, YODESWAP_ROUTER, _yodeBNB);
    }
}

