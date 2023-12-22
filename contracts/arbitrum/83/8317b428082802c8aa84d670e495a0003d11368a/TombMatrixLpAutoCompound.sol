// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompound.sol";

/// @title MatrixLpAutoCompound adapted to claim BSHARE rewards from the correct routes
contract TombMatrixLpAutoCompound is MatrixLpAutoCompound {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant TOMBSWAP_ROUTER = 0x6D0176C5ea1e44b08D3dd001b0784cE42F47a3A7;
    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant TOMB = 0x6c021Ae822BEa943b2E66552bDe1D2696a53fbB7;
    address internal constant MAI = 0xfB98B335551a418cD0737375a2ea0ded62Ea213b;
    address internal constant TSHARE = 0x4cdF39285D7Ca8eB3f090fDA0C069ba5F4145B37;
    address internal constant BTC = 0x321162Cd933E2Be498Cd2267a90534A804051b11;
    address internal constant ETH = 0x74b23882a30290451A17c44f4F05243b6b58C76d;
    address internal constant MIM = 0x82f0B8B456c1A451378467398982d4834b6829c1;
    address internal constant FUSDT = 0x049d68029688eAbF473097a2fC38ef61633A3C7A;
    address internal constant FUSD = 0xAd84341756Bf337f5a0164515b1f6F993D194E1f;
    address internal constant TREEB = 0xc60D7067dfBc6f2caf30523a064f416A5Af52963;
    address internal constant ZOO = 0x09e145A1D53c0045F41aEEf25D8ff982ae74dD56;
    address internal constant SCREAM = 0xe0654C8e6fd4D733349ac7E09f6f23DA256bF475;
    address internal constant LIFE = 0xbf60e7414EF09026733c1E7de72E7393888C64DA;
    address internal constant LSHARE = 0xCbE0CA46399Af916784cADF5bCC3aED2052D6C45;
    address internal constant BNB = 0xD67de0e0a0Fd7b15dC8348Bb9BE742F3c5850454;
    address internal constant AVAX = 0x511D35c52a3C244E7b8bd92c0C297755FbD89212;
    address internal constant LINK = 0xb3654dc3D10Ea7645f8319668E8F54d2574FBdC8;
    address internal constant CRV = 0x1E4F97b9f9F913c46F1632781732927B9019C68b;
    address internal constant DAI = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;

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
        whitelistedAddresses.add(LIFE);
        whitelistedAddresses.add(LSHARE);
        whitelistedAddresses.add(TOMBSWAP_ROUTER);
        whitelistedAddresses.add(TOMB);
        whitelistedAddresses.add(BTC);
        whitelistedAddresses.add(MAI);
        whitelistedAddresses.add(TSHARE);
        whitelistedAddresses.add(ETH);
        whitelistedAddresses.add(MIM);
        whitelistedAddresses.add(FUSDT);
        whitelistedAddresses.add(FUSD);
        whitelistedAddresses.add(TREEB);
        whitelistedAddresses.add(SCREAM);
        whitelistedAddresses.add(ZOO);
        whitelistedAddresses.add(BNB);
        whitelistedAddresses.add(AVAX);
        whitelistedAddresses.add(LINK);
        whitelistedAddresses.add(CRV);
        whitelistedAddresses.add(DAI);
    }

    function _setDefaultSwapPaths() internal override {
        super._setDefaultSwapPaths();

        // LSHARE -> FTM
        address[] memory _lshareFtm = new address[](3);
        _lshareFtm[0] = LSHARE;
        _lshareFtm[1] = USDC;
        _lshareFtm[2] = WFTM;
        _setSwapPath(LSHARE, WFTM, TOMBSWAP_ROUTER, _lshareFtm);

        // LSHARE -> TOMB
        address[] memory _lshareTomb = new address[](3);
        _lshareTomb[0] = LSHARE;
        _lshareTomb[1] = USDC;
        _lshareTomb[2] = TOMB;
        _setSwapPath(LSHARE, TOMB, TOMBSWAP_ROUTER, _lshareTomb);

        // LSHARE -> USDC
        address[] memory _lshareUsdc = new address[](2);
        _lshareUsdc[0] = LSHARE;
        _lshareUsdc[1] = USDC;
        _setSwapPath(LSHARE, USDC, TOMBSWAP_ROUTER, _lshareUsdc);

        // LSHARE -> ZOO
        address[] memory _lshareZoo = new address[](4);
        _lshareZoo[0] = LSHARE;
        _lshareZoo[1] = USDC;
        _lshareZoo[2] = TOMB;
        _lshareZoo[3] = ZOO;
        _setSwapPath(LSHARE, ZOO, TOMBSWAP_ROUTER, _lshareZoo);

        // LSHARE -> TREEB
        address[] memory _lshareTreeb = new address[](4);
        _lshareTreeb[0] = LSHARE;
        _lshareTreeb[1] = USDC;
        _lshareTreeb[2] = TOMB;
        _lshareTreeb[3] = TREEB;
        _setSwapPath(LSHARE, TREEB, TOMBSWAP_ROUTER, _lshareTreeb);

        // LSHARE -> BTC
        address[] memory _lshareBtc = new address[](4);
        _lshareBtc[0] = LSHARE;
        _lshareBtc[1] = USDC;
        _lshareBtc[2] = WFTM;
        _lshareBtc[3] = BTC;
        _setSwapPath(LSHARE, BTC, TOMBSWAP_ROUTER, _lshareBtc);

        // LSHARE -> ETH
        address[] memory _lshareEth = new address[](4);
        _lshareEth[0] = LSHARE;
        _lshareEth[1] = USDC;
        _lshareEth[2] = WFTM;
        _lshareEth[3] = ETH;
        _setSwapPath(LSHARE, ETH, TOMBSWAP_ROUTER, _lshareEth);

        // LSHARE -> TSHARE
        address[] memory _lshareTshare = new address[](2);
        _lshareTshare[0] = LSHARE;
        _lshareTshare[1] = TSHARE;
        _setSwapPath(LSHARE, TSHARE, TOMBSWAP_ROUTER, _lshareTshare);

        // LSHARE -> FUSDT
        address[] memory _lshareFusdt = new address[](3);
        _lshareFusdt[0] = LSHARE;
        _lshareFusdt[1] = USDC;
        _lshareFusdt[2] = FUSDT;
        _setSwapPath(LSHARE, FUSDT, TOMBSWAP_ROUTER, _lshareFusdt);

        // LSHARE -> MIM
        address[] memory _lshareMim = new address[](3);
        _lshareMim[0] = LSHARE;
        _lshareMim[1] = USDC;
        _lshareMim[2] = MIM;
        _setSwapPath(LSHARE, MIM, TOMBSWAP_ROUTER, _lshareMim);

        // LSHARE -> FUSD
        address[] memory _lshareFusd = new address[](3);
        _lshareFusd[0] = LSHARE;
        _lshareFusd[1] = USDC;
        _lshareFusd[2] = FUSD;
        _setSwapPath(LSHARE, FUSD, TOMBSWAP_ROUTER, _lshareFusd);

        // LSHARE -> DAI
        address[] memory _lshareDai = new address[](4);
        _lshareDai[0] = LSHARE;
        _lshareDai[1] = USDC;
        _lshareDai[2] = WFTM;
        _lshareDai[3] = DAI;
        _setSwapPath(LSHARE, DAI, TOMBSWAP_ROUTER, _lshareDai);

        // LSHARE -> BNB
        address[] memory _lshareBnb = new address[](4);
        _lshareBnb[0] = LSHARE;
        _lshareBnb[1] = USDC;
        _lshareBnb[2] = WFTM;
        _lshareBnb[3] = BNB;
        _setSwapPath(LSHARE, BNB, TOMBSWAP_ROUTER, _lshareBnb);

        // LSHARE -> AVAX
        address[] memory _lshareAvax = new address[](4);
        _lshareAvax[0] = LSHARE;
        _lshareAvax[1] = USDC;
        _lshareAvax[2] = WFTM;
        _lshareAvax[3] = AVAX;
        _setSwapPath(LSHARE, AVAX, TOMBSWAP_ROUTER, _lshareAvax);

        // LSHARE -> LINK
        address[] memory _lshareLink = new address[](4);
        _lshareLink[0] = LSHARE;
        _lshareLink[1] = USDC;
        _lshareLink[2] = WFTM;
        _lshareLink[3] = LINK;
        _setSwapPath(LSHARE, LINK, TOMBSWAP_ROUTER, _lshareLink);

        // LSHARE -> CRV
        address[] memory _lshareCrv = new address[](4);
        _lshareCrv[0] = LSHARE;
        _lshareCrv[1] = USDC;
        _lshareCrv[2] = WFTM;
        _lshareCrv[3] = CRV;
        _setSwapPath(LSHARE, CRV, TOMBSWAP_ROUTER, _lshareCrv);

        // LSHARE -> LIFE
        address[] memory _lshareLife = new address[](3);
        _lshareLife[0] = LSHARE;
        _lshareLife[1] = USDC;
        _lshareLife[2] = LIFE;
        _setSwapPath(LSHARE, LIFE, TOMBSWAP_ROUTER, _lshareLife);
    }
}

