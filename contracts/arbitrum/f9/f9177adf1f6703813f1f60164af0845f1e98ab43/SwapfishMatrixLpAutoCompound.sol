// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixLpAutoCompoundV2.sol";

/// @title MatrixLpAutoCompound adapted to kibbleswap for custom routing
contract SwapfishMatrixLpAutoCompound is MatrixLpAutoCompoundV2 {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant SUSHISWAP_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address internal constant SWAPFISH_ROUTER = 0xcDAeC65495Fa5c0545c5a405224214e3594f30d8;
    address internal constant MIM = 0xFEa7a6a0B346362BF88A9e4A88416B77a57D6c2A;
    address internal constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address internal constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address internal constant GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address internal constant MAGIC = 0x539bdE0d7Dbd336b79148AA742883198BBF60342;
    address internal constant FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address internal constant USX = 0x641441c631e2F909700d2f41FD87F0aA6A6b4EDb;

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _uniRouter,
        address _vault,
        address _treasury
    ) MatrixLpAutoCompoundV2(_want, _poolId, _masterchef, _output, _uniRouter, _vault, _treasury) {}

    function _initialize(
        address _masterchef,
        address _output,
        uint256 _poolId
    ) internal override {
        wrapped = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        treasury = 0xEaD9f532C72CF35dAb18A42223eE7A1B19bC5aBF;
        USDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

        callFee = 250;
        treasuryFee = 9750;
        securityFee = 0;
        totalFee = 600;

        unirouter = SWAPFISH_ROUTER;

        routers.push(SUSHISWAP_ROUTER);
        routers.push(SWAPFISH_ROUTER);

        super._initialize(_masterchef, _output, _poolId);
    }

    function _setWhitelistedAddresses() internal override {
        super._setWhitelistedAddresses();
        whitelistedAddresses.add(SUSHISWAP_ROUTER);
        whitelistedAddresses.add(SWAPFISH_ROUTER);
        whitelistedAddresses.add(USDT);
        whitelistedAddresses.add(DAI);
        whitelistedAddresses.add(MIM);
        whitelistedAddresses.add(USDC);
        whitelistedAddresses.add(GMX);
        whitelistedAddresses.add(FRAX);
        whitelistedAddresses.add(MAGIC);
        whitelistedAddresses.add(lpToken0);
        whitelistedAddresses.add(lpToken1);
        whitelistedAddresses.add(USX);
        whitelistedAddresses.add(output);
    }

    function _setDefaultSwapPaths() internal override {
        // FISH -> MIM
        address[] memory _fishMim = new address[](4);
        _fishMim[0] = output;
        _fishMim[1] = wrapped;
        _fishMim[2] = USDC;
        _fishMim[3] = MIM;
        _setSwapPath(output, MIM, SWAPFISH_ROUTER, _fishMim);

        // FISH -> USDT
        address[] memory _fishUsdt = new address[](4);
        _fishUsdt[0] = output;
        _fishUsdt[1] = wrapped;
        _fishUsdt[2] = USDC;
        _fishUsdt[3] = USDT;
        _setSwapPath(output, USDT, SWAPFISH_ROUTER, _fishUsdt);

        // FISH -> DAI
        address[] memory _fishDAI = new address[](4);
        _fishDAI[0] = output;
        _fishDAI[1] = wrapped;
        _fishDAI[2] = USDC;
        _fishDAI[3] = DAI;
        _setSwapPath(output, DAI, SWAPFISH_ROUTER, _fishDAI);

        // FISH -> GMX
        address[] memory _fishGMX = new address[](4);
        _fishGMX[0] = output;
        _fishGMX[1] = wrapped;
        _fishGMX[2] = USDC;
        _fishGMX[3] = GMX;
        _setSwapPath(output, GMX, SWAPFISH_ROUTER, _fishGMX);

        // FISH -> MAGIC
        address[] memory _fishMAGIC = new address[](4);
        _fishMAGIC[0] = output;
        _fishMAGIC[1] = wrapped;
        _fishMAGIC[2] = USDC;
        _fishMAGIC[3] = MAGIC;
        _setSwapPath(output, MAGIC, SWAPFISH_ROUTER, _fishMAGIC);

        // FISH -> FRAX
        address[] memory _fishFRAX = new address[](4);
        _fishFRAX[0] = output;
        _fishFRAX[1] = wrapped;
        _fishFRAX[2] = USDC;
        _fishFRAX[3] = FRAX;
        _setSwapPath(output, FRAX, SWAPFISH_ROUTER, _fishFRAX);

        // FISH -> USX
        address[] memory _fishUSX = new address[](4);
        _fishUSX[0] = output;
        _fishUSX[1] = wrapped;
        _fishUSX[2] = USDC;
        _fishUSX[3] = USX;
        _setSwapPath(output, USX, SWAPFISH_ROUTER, _fishUSX);

        super._setDefaultSwapPaths();
    }
}

