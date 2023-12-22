// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract BookTokenProxy is TransparentUpgradeableProxy {
    constructor (
        address logic,
        address _admin,
        uint256 _initialMint,
        uint256 _vestingStart
    ) TransparentUpgradeableProxy(logic, _admin, generateData(
        _initialMint,
        _vestingStart
        )) {}

    function generateData(
        uint256 _initialMint, 
        uint256 _vestingStart
    ) internal pure returns (bytes memory data) {
        data = abi.encodeWithSignature("initialize(uint256,uint256)", 
            _initialMint, 
            _vestingStart
        );
    }
}


