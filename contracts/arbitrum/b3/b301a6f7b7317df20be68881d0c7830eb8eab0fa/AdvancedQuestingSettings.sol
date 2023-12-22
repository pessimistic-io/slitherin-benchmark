//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdvancedQuestingContracts.sol";

abstract contract AdvancedQuestingSettings is Initializable, AdvancedQuestingContracts {

    function __AdvancedQuestingSettings_init() internal initializer {
        AdvancedQuestingContracts.__AdvancedQuestingContracts_init();
    }

    function setChanceUniversalLock(
        uint256 _chanceUniversalLock)
    external
    onlyAdminOrOwner
    {
        chanceUniversalLock = _chanceUniversalLock;
    }

    function addZone(string calldata _zoneName, ZoneInfo calldata _zone) external onlyAdminOrOwner {
        require(!compareStrings(_zoneName, ""), "Zone name cannot be blank");
        require(!isValidZone(_zoneName), "Zone already exists");
        require(_zone.zoneStartTime > 0, "Zone must have a start time");

        zoneNameToInfo[_zoneName] = _zone;
    }

    function updatePartLengthsForZone(
        string calldata _zoneName,
        uint256[] calldata _partLengths,
        uint256[] calldata _stasisLengths)
    external
    onlyAdminOrOwner
    {
        require(isValidZone(_zoneName), "Zone is invalid");

        ZoneInfo storage _zoneInfo = zoneNameToInfo[_zoneName];
        require(_partLengths.length == _zoneInfo.parts.length && _partLengths.length == _stasisLengths.length, "Bad array lengths");

        for(uint256 i = 0; i < _partLengths.length; i++) {
            _zoneInfo.parts[i].zonePartLength = _partLengths[i];
            _zoneInfo.parts[i].stasisLength = _stasisLengths[i];
        }
    }

    function updateQuestLevelBoosts(
        string calldata _zoneName,
        uint256 _partIndex,
        uint256 _rewardIndex,
        uint8[7] calldata _questLevelBoosts)
    external
    onlyAdminOrOwner
    {
        require(isValidZone(_zoneName), "Zone is invalid");

        ZoneInfo storage _zoneInfo = zoneNameToInfo[_zoneName];
        require(_partIndex < _zoneInfo.parts.length, "Bad part index");

        ZonePart storage _zonePart = _zoneInfo.parts[_partIndex];
        require(_rewardIndex < _zonePart.rewards.length, "Bad reward index");

        zoneNameToPartIndexToRewardIndexToQuestBoosts[_zoneName][_partIndex][_rewardIndex] = _questLevelBoosts;
    }

    function setStasisLengthForCorruptedCard(uint256 _stasisLengthForCorruptedCard) external onlyAdminOrOwner {
        stasisLengthForCorruptedCard = _stasisLengthForCorruptedCard;
    }

    function isValidZone(string memory _zoneName) public view returns(bool) {
        return zoneNameToInfo[_zoneName].zoneStartTime > 0;
    }

    function lengthForPartOfZone(string calldata _zoneName, uint8 _partIndex) public view returns(uint256) {
        return zoneNameToInfo[_zoneName].parts[_partIndex].zonePartLength;
    }
}
