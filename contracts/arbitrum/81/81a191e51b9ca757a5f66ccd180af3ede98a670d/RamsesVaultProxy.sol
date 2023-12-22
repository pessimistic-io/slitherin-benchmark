// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.18;
import "./RamsesVaultStorage.sol";
import "./TransparentUpgradeableProxy.sol";
contract RamsesVaultProxy is RamsesVaultStorage, TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address crAdmin,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, crAdmin, _data) {}
}

