// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./OwnableUpgradeable.sol";
import "./IBeacon.sol";
import "./IBeaconPetsStakingRules.sol";

contract VerifyBeaconPetsOwner is OwnableUpgradeable {
    IBeacon public beacon;
    IBeaconPetsStakingRules public stakingRule;

    function initialize(address _beacon, address _stakingRule) external initializer {
        __Ownable_init();

        beacon = IBeacon(_beacon);
        stakingRule = IBeaconPetsStakingRules(_stakingRule);
    }

    function balanceOf(address owner) external view returns (uint256 amount) {
        uint256 amountOwned = 0;
        uint256[] memory tokenIds = beacon.tokensByAccount(owner);
        for (uint256 i = 0; i < tokenIds.length; i++) {
          if (tokenIds[i] <= 4096) {
            amountOwned++;
          }
        }

        return amountOwned + stakingRule.beaconPetsAmountStaked(owner);
    }
}

