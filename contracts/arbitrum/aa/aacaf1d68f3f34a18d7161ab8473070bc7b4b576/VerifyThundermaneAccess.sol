// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./OwnableUpgradeable.sol";
import "./IHarvester.sol";

contract VerifyThundermaneAccess is OwnableUpgradeable {
    IHarvester public harvester;

    function initialize(address harvester_) external initializer {
        __Ownable_init();

        harvester = IHarvester(harvester_);
    }

    function balanceOf(address owner) external view returns (uint256 cap) {
        return harvester.getUserDepositCap(owner);
    }
}

