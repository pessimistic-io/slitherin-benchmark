//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IHuntingGrounds.sol";
import "./AdminableUpgradeable.sol";
import "./IWorld.sol";
import "./IBugz.sol";
import "./IBadgez.sol";

abstract contract HuntingGroundsState is Initializable, IHuntingGrounds, AdminableUpgradeable {

    event StartedHunting(uint256 _tokenId, uint256 _timestamp);
    event ClaimedBugz(uint256 _tokenId, uint256 _amount, uint256 _timestamp);
    event StoppedHunting(uint256 _tokenId);

    IWorld public world;
    IBugz public bugz;
    IBadgez public badgez;

    mapping(uint256 => uint256) tokenIdToLastClaimedTime;
    mapping(address => mapping(uint256 => uint256)) ownerToTokenIdToTotalBugzClaimed;

    uint256 public bugzAmountPerDay;

    uint256[] public bugzBadgezAmounts;
    mapping(uint256 => uint256) public bugzAmountToBadgeId;

    function __HuntingGroundsState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        bugzAmountPerDay = 10 ether;

        bugzBadgezAmounts = [10 ether, 300 ether, 3650 ether];
        bugzAmountToBadgeId[10 ether] = 2;
        bugzAmountToBadgeId[300 ether] = 3;
        bugzAmountToBadgeId[3650 ether] = 4;
    }
}
