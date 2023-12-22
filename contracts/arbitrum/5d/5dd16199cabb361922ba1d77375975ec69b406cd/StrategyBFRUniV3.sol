// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./UniswapV3Utils.sol";
import "./StrategyBFR.sol";

contract StrategyBFRUniV3 is StrategyBFR {

    // Route
    bytes public nativeToWantPath;

    constructor(
        address _chef, // BfrRewards
        address[] memory _nativeToWantRoute, // [WETH, BFR]
        uint24[] memory _nativeToWantFees,
        CommonAddresses memory _commonAddresses
    ) StrategyBFR(_chef, _commonAddresses) {
        native = _nativeToWantRoute[0];
        wantToken = _nativeToWantRoute[_nativeToWantRoute.length - 1];
        nativeToWantPath = UniswapV3Utils.routeToPath(_nativeToWantRoute, _nativeToWantFees);
        _giveAllowances();
    }

    function swapRewards() internal override {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        UniswapV3Utils.swap(unirouter, nativeToWantPath, nativeBal);
    }

    function nativeToWant() external view override returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToWantPath);
    }
}

