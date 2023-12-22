// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract CoinBookPresaleProxy is TransparentUpgradeableProxy {
    constructor (
        address logic,
        address _admin,
        address _weth, 
        address _usdc,
        address _book,
        address _sushi,
        uint80 _wlStart,
        uint80 _wlEnd,
        uint256 _wlMaxSpend,
        uint256 _wlTarget,
        uint256 _wlSaleAmount,
        uint80 _psStart,
        uint80 _psEnd,
        uint256 _psMaxSpend,
        uint256 _psTarget,
        uint256 _psSaleAmount,
        uint80 _claimStart
    ) TransparentUpgradeableProxy(logic, _admin, generateData(
        _weth, 
        _usdc,
        _book,
        _sushi,
        _wlStart,
        _wlEnd,
        _wlMaxSpend,
        _wlTarget,
        _wlSaleAmount,
        _psStart,
        _psEnd,
        _psMaxSpend,
        _psTarget,
        _psSaleAmount,
        _claimStart
        )) {}

    function generateData(
        address _weth, 
        address _usdc,
        address _book,
        address _sushi,
        uint80 _wlStart,
        uint80 _wlEnd,
        uint256 _wlMaxSpend,
        uint256 _wlTarget,
        uint256 _wlSaleAmount,
        uint80 _psStart,
        uint80 _psEnd,
        uint256 _psMaxSpend,
        uint256 _psTarget,
        uint256 _psSaleAmount,
        uint80 _claimStart
    ) internal pure returns (bytes memory data) {
        data = abi.encodeWithSignature(
            "initialize(address,address,address,address,uint80,uint80,uint256,uint256,uint256,uint80,uint80,uint256,uint256,uint256,uint80)",
            _weth,
            _usdc, 
            _book,
            _sushi,
            _wlStart,
            _wlEnd,
            _wlMaxSpend,
            _wlTarget,
            _wlSaleAmount,
            _psStart,
            _psEnd,
            _psMaxSpend,
            _psTarget,
            _psSaleAmount,
            _claimStart
        );
    }
}


