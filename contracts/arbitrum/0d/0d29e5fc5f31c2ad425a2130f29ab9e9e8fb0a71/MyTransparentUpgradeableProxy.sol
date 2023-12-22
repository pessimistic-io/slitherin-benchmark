// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;
import "./TransparentUpgradeableProxy.sol";

contract MyTransparentUpgradeableProxy is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, admin_, _data) {}

    receive() external payable override {}
}
