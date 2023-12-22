// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract BookTokenProxy is TransparentUpgradeableProxy {
    constructor (
        address logic,
        address _admin,
        uint256 _initialMint,
        uint256 _vestingStart,
        address _vestAdmin
    ) TransparentUpgradeableProxy(logic, _admin, generateData(
        _initialMint,
        _vestingStart,
        _vestAdmin
        )) {}

    function generateData(
        uint256 _initialMint, 
        uint256 _vestingStart,
        address _vestAdmin
    ) internal pure returns (bytes memory data) {
        data = abi.encodeWithSignature("initialize(uint256,uint256,address)", 
            _initialMint, 
            _vestingStart,
            _vestAdmin
        );
    }
}


