// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract CoinBookProxy is TransparentUpgradeableProxy {
    constructor (
        address _logic,
        address _admin,
        address _multiSig,
        address _weth,
        address _priceFeed,
        uint256 _fees,
        address payable _taxWallet, 
        uint16 _tax
    ) TransparentUpgradeableProxy(_logic, _admin, generateData(
        _multiSig,
        _weth,
        _priceFeed,
        _fees,
        _taxWallet, 
        _tax
        )) {}

    function generateData(
        address _multiSig,
        address _weth,
        address _priceFeed,
        uint256 _fees,
        address payable _taxWallet, 
        uint16 _tax
    ) internal pure returns (bytes memory data) {
        data = abi.encodeWithSignature(
            "initialize(address,address,address,uint256,address,uint16)",
            _multiSig,
            _weth,
            _priceFeed,
            _fees,
            _taxWallet, 
            _tax
        );
    }
}


