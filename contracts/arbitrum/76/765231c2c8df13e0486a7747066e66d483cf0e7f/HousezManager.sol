//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./HousezManagerContracts.sol";

contract HousezManager is Initializable, HousezManagerContracts {

    function initialize() external initializer {
        HousezManagerContracts.__HousezManagerContracts_init();
    }

    function setFloorInfo(uint16 _floorNum, uint16 _numHousezForFloor) external onlyAdminOrOwner {
        require(_floorNum > 0, "Bad floor number");

        totalStakableHousez -= floorNumToInfo[_floorNum].numHousezForFloor;
        totalStakableHousez += _numHousezForFloor;

        floorNumToInfo[_floorNum].numHousezForFloor = _numHousezForFloor;

        emit FloorInfoUpdated(_floorNum, _numHousezForFloor, totalStakableHousez);
    }

    function stakeOrUnstakeHousez(
        uint16[] calldata _houseIdsToUnstake,
        uint16[] calldata _houseIdsToStake)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(_houseIdsToUnstake.length > 0 || _houseIdsToStake.length > 0);

        for(uint256 i = 0; i < _houseIdsToUnstake.length; i++) {
            _unstakeHouse(_houseIdsToUnstake[i]);
        }

        for(uint256 i = 0; i < _houseIdsToStake.length; i++) {
            _stakeHouse(_houseIdsToStake[i]);
        }
    }

    function _unstakeHouse(uint16 _houseId) private {
        require(houseIdToInfo[_houseId].owner == msg.sender, "House does not belong to you");

        uint16 _oldPreviousHouseId = houseIdToInfo[_houseId].previousHouseId;
        uint16 _oldNextHouseId = houseIdToInfo[_houseId].nextHouseId;

        if(_oldPreviousHouseId == 0) {
            userToInfo[msg.sender].firstHouseId = _oldNextHouseId;
        } else {
            houseIdToInfo[_oldPreviousHouseId].nextHouseId = _oldNextHouseId;
        }

        if(_oldNextHouseId == 0) {
            userToInfo[msg.sender].lastHouseId = _oldPreviousHouseId;
        } else {
            houseIdToInfo[_oldNextHouseId].previousHouseId = _oldPreviousHouseId;
        }

        delete houseIdToInfo[_houseId];

        userToInfo[msg.sender].housezStaked--;

        housez.adminSafeTransferFrom(address(this), msg.sender, _houseId);

        emit HouseUnstaked(msg.sender, _houseId, _oldPreviousHouseId, _oldNextHouseId);
    }

    function _stakeHouse(uint16 _houseId) private {

        uint16 _lastHouseId = userToInfo[msg.sender].lastHouseId;

        houseIdToInfo[_houseId].owner = msg.sender;
        userToInfo[msg.sender].lastHouseId = _houseId;

        // This is their first house.
        if(_lastHouseId == 0) {
            userToInfo[msg.sender].firstHouseId = _houseId;
        } else {
            houseIdToInfo[_lastHouseId].nextHouseId = _houseId;
            houseIdToInfo[_houseId].previousHouseId = _lastHouseId;
        }

        userToInfo[msg.sender].housezStaked++;
        require(userToInfo[msg.sender].housezStaked <= totalStakableHousez, "Too many housez staked");

        housez.adminSafeTransferFrom(msg.sender, address(this), _houseId);

        emit HouseStaked(msg.sender, _houseId, _lastHouseId);
    }
}
