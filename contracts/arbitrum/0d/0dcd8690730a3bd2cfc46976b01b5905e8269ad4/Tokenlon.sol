pragma solidity 0.7.6;

import "./TransparentUpgradeableProxy.sol";

contract Tokenlon is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address _admin,
        bytes memory _data
    ) public payable TransparentUpgradeableProxy(_logic, _admin, _data) {}
}

