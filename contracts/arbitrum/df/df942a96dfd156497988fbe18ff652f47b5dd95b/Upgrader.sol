// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UpgradeableBeacon.sol";
import "./Ownable.sol";

import "./IFeeder.sol";
import "./IUpgrader.sol";
import "./IRegistry.sol";

// @address:REGISTRY
IRegistry constant registry = IRegistry(0x0000000000000000000000000000000000000000);

contract Upgrader is IUpgrader, Ownable {
    uint256 public minUpgradePeriod;
    uint256 public upgradePeriod;
    uint256 public nextUpgradeDate;
    IFeeder public feeder;
    Upgrade[] public upgrades;

    constructor(uint256 _minUpgradePeriod, uint256 _upgradePeriod) {
        minUpgradePeriod = _minUpgradePeriod;
        upgradePeriod = _upgradePeriod;
    }

    function setUpgradePeriod(uint256 _upgradePeriod) external onlyOwner {
        require(_upgradePeriod >= minUpgradePeriod, "TU/UPS"); // upgrade period too short
        upgradePeriod = _upgradePeriod;
    }
 
    function requestUpgrade(Upgrade[] memory _upgrades) external onlyOwner {
        for (uint i = 0; i < _upgrades.length; i++) {
            require(_upgrades[i].implementation != address(0), "TU/II"); // invalid implementation
        }
        upgrades = _upgrades;
        nextUpgradeDate = block.timestamp + upgradePeriod;
        emit UpgradeRequested(_upgrades, upgradePeriod);
    }

    function upgrade() external onlyOwner {
        require(block.timestamp >= nextUpgradeDate, "TU/UPNE"); // upgrade period not expired
        require(!registry.feeder().hasUnprocessedWithdrawals(), "TU/UW"); // has unprocessed withdrawals
        for (uint i = 0; i < upgrades.length; i++) {
            upgrades[i].destination.upgradeTo(upgrades[i].implementation);
        }
        nextUpgradeDate = 0;
        delete upgrades;
    }

    function pendingUpgrades() public view returns (Upgrade[] memory) {
        return upgrades;
    }

    function cancelUpgrade() external onlyOwner {
        nextUpgradeDate = 0;
        delete upgrades;
    }
}
