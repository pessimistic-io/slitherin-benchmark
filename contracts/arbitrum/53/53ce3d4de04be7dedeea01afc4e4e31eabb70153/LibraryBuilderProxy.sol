// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract LibraryBuilderProxy is TransparentUpgradeableProxy {
    constructor (
        address logic,
        address admin_,
        uint256 _lock,
        address _admin,
        address _coinBook
    ) TransparentUpgradeableProxy(logic, admin_, generateData(
            _lock,
            _admin,
            _coinBook
        )) {}

    function generateData(
        uint256 _lock,
        address _admin,
        address _coinBook
    ) internal pure returns (bytes memory data) {
        data = abi.encodeWithSignature(
            "initialize(uint256,address,address)",
            _lock,
            _admin,
            _coinBook
        );
    }
}


