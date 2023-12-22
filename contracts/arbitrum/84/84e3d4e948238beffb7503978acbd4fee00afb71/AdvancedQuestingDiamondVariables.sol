//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdvancedQuestingDiamondState.sol";

contract AdvancedQuestingDiamondVariables is Initializable, AdvancedQuestingDiamondState {

    function setContracts(
        address _randomizerAddress,
        address _questingAddress,
        address _legionAddress,
        address _legionMetadataStoreAddress,
        address _treasureAddress,
        address _consumableAddress,
        address _treasureMetadataStoreAddress,
        address _treasureTriadAddress,
        address _treasureFragmentAddress,
        address _recruitLevelAddress,
        address _masterOfInflationAddress,
        address _corruptionAddress)
    external onlyAdminOrOwner
    {
        appStorage.randomizer = IRandomizer(_randomizerAddress);
        appStorage.questing = IQuesting(_questingAddress);
        appStorage.legion = ILegion(_legionAddress);
        appStorage.legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        appStorage.treasure = ITreasure(_treasureAddress);
        appStorage.consumable = IConsumable(_consumableAddress);
        appStorage.treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        appStorage.treasureTriad = ITreasureTriad(_treasureTriadAddress);
        appStorage.treasureFragment = ITreasureFragment(_treasureFragmentAddress);
        appStorage.recruitLevel = IRecruitLevel(_recruitLevelAddress);
        appStorage.masterOfInflation = IMasterOfInflation(_masterOfInflationAddress);
        appStorage.corruption = ICorruption(_corruptionAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(appStorage.randomizer) != address(0)
            && address(appStorage.questing) != address(0)
            && address(appStorage.legion) != address(0)
            && address(appStorage.legionMetadataStore) != address(0)
            && address(appStorage.treasure) != address(0)
            && address(appStorage.consumable) != address(0)
            && address(appStorage.treasureMetadataStore) != address(0)
            && address(appStorage.treasureTriad) != address(0)
            && address(appStorage.treasureFragment) != address(0)
            && address(appStorage.recruitLevel) != address(0)
            && address(appStorage.masterOfInflation) != address(0)
            && address(appStorage.corruption) != address(0);
    }

    function stasisLengthForCorruptedCard() external view returns(uint256) {
        return appStorage.stasisLengthForCorruptedCard;
    }

    function zoneNameToInfo(string calldata _name) external view returns(LibAdvancedQuestingDiamond.ZoneInfo memory) {
        return appStorage.zoneNameToInfo[_name];
    }

    function chanceUniversalLock() external view returns(uint256) {
        return appStorage.chanceUniversalLock;
    }

    function cadetRecruitFragmentBoost() external view returns(uint256) {
        return appStorage.cadetRecruitFragmentBoost;
    }

    function tierToPoolId(uint8 _tier) external view returns(uint64) {
        return appStorage.tierToPoolId[_tier];
    }

    function tierToRecruitPoolId(uint8 _tier) external view returns(uint64) {
        return appStorage.tierToRecruitPoolId[_tier];
    }

    function zoneNameToPartIndexToRecruitPartInfo(string calldata _name, uint256 _partIndex) external view returns(LibAdvancedQuestingDiamond.RecruitPartInfo memory) {
        return appStorage.zoneNameToPartIndexToRecruitPartInfo[_name][_partIndex];
    }

    function zoneNameToPartIndexToRewardIndexToQuestBoosts(string calldata _name, uint256 _partIndex, uint256 _rewardIndex, uint8 _level) external view returns(uint8) {
        return appStorage.zoneNameToPartIndexToRewardIndexToQuestBoosts[_name][_partIndex][_rewardIndex][_level];
    }

    function endingPartToQPGained(uint8 _endingPart) external view returns(uint256) {
        return appStorage.endingPartToQPGained[_endingPart];
    }

    function setPoolIds(uint64[5] calldata _poolIds, uint64 _recruitTier5PoolId) external onlyAdminOrOwner {
        if(appStorage.timePoolsFirstSet == 0) {
            appStorage.timePoolsFirstSet = block.timestamp;
        }
        appStorage.tierToPoolId[1] = _poolIds[0];
        appStorage.tierToPoolId[2] = _poolIds[1];
        appStorage.tierToPoolId[3] = _poolIds[2];
        appStorage.tierToPoolId[4] = _poolIds[3];
        appStorage.tierToPoolId[5] = _poolIds[4];

        appStorage.tierToRecruitPoolId[5] = _recruitTier5PoolId;
    }

    function setChanceUniversalLock(
        uint256 _chanceUniversalLock)
    external
    onlyAdminOrOwner
    {
        appStorage.chanceUniversalLock = _chanceUniversalLock;
    }

    function setCadetRecruitFragmentBoost(uint32 _cadetRecruitFragmentBoost) external onlyAdminOrOwner {
        appStorage.cadetRecruitFragmentBoost = _cadetRecruitFragmentBoost;

        emit SetCadetRecruitFragmentBoost(_cadetRecruitFragmentBoost);
    }

    function setRecruitPartInfo(string calldata _zoneName, uint256 _partIndex, LibAdvancedQuestingDiamond.RecruitPartInfo calldata _recruitPartInfo) external onlyAdminOrOwner {
        // For now, only the first part is accessible.
        require(_partIndex == 0 && isValidZone(_zoneName));

        appStorage.zoneNameToPartIndexToRecruitPartInfo[_zoneName][_partIndex].numEoS = _recruitPartInfo.numEoS;
        appStorage.zoneNameToPartIndexToRecruitPartInfo[_zoneName][_partIndex].numShards = _recruitPartInfo.numShards;
        appStorage.zoneNameToPartIndexToRecruitPartInfo[_zoneName][_partIndex].chanceUniversalLock = _recruitPartInfo.chanceUniversalLock;
        appStorage.zoneNameToPartIndexToRecruitPartInfo[_zoneName][_partIndex].recruitXPGained = _recruitPartInfo.recruitXPGained;
        appStorage.zoneNameToPartIndexToRecruitPartInfo[_zoneName][_partIndex].fragmentId = _recruitPartInfo.fragmentId;
        delete appStorage.zoneNameToPartIndexToRecruitPartInfo[_zoneName][_partIndex].emptySpace;

        emit SetRecruitPartInfo(_zoneName, _partIndex + 1, _recruitPartInfo);
    }

    function addZone(string calldata _zoneName, LibAdvancedQuestingDiamond.ZoneInfo calldata _zone) external onlyAdminOrOwner {
        require(!compareStrings(_zoneName, "") && !isValidZone(_zoneName) && _zone.zoneStartTime > 0);

        appStorage.zoneNameToInfo[_zoneName] = _zone;
    }

    function updatePartLengthsForZone(
        string calldata _zoneName,
        uint256[] calldata _partLengths,
        uint256[] calldata _stasisLengths)
    external
    onlyAdminOrOwner
    {
        require(isValidZone(_zoneName), "Zone is invalid");

        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo = appStorage.zoneNameToInfo[_zoneName];
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

        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo = appStorage.zoneNameToInfo[_zoneName];
        require(_partIndex < _zoneInfo.parts.length, "Bad part index");

        LibAdvancedQuestingDiamond.ZonePart storage _zonePart = _zoneInfo.parts[_partIndex];
        require(_rewardIndex < _zonePart.rewards.length, "Bad reward index");

        appStorage.zoneNameToPartIndexToRewardIndexToQuestBoosts[_zoneName][_partIndex][_rewardIndex] = _questLevelBoosts;
    }

    function setStasisLengthForCorruptedCard(uint256 _stasisLengthForCorruptedCard) external onlyAdminOrOwner {
        appStorage.stasisLengthForCorruptedCard = _stasisLengthForCorruptedCard;
    }

    function setEndingPartToQPGained(EndingPartParams[] calldata _endingPartParams) external onlyAdminOrOwner {
        for(uint256 i = 0; i < _endingPartParams.length; i++) {
            appStorage.endingPartToQPGained[_endingPartParams[i].endingPart] = _endingPartParams[i].qpGained;

            emit QPForEndingPart(_endingPartParams[i].endingPart, _endingPartParams[i].qpGained);
        }
    }

    function lengthForPartOfZone(string calldata _zoneName, uint8 _partIndex) public view returns(uint256) {
        return appStorage.zoneNameToInfo[_zoneName].parts[_partIndex].zonePartLength;
    }

    function numberOfLegionsQuesting() external view returns(uint256, uint256) {
        return (appStorage.numQuesting, appStorage.numRecruitsQuesting);
    }

    function requestIdForLegion(uint256 _legionId) external view returns(uint256) {
        require(isLegionQuesting(_legionId), "Legion is not questing");

        bool _usingOldSchema = _isUsingOldSchema(_legionId);
        return _requestIdForLegion(_usingOldSchema, _legionId);
    }

    function additionalCorruptedCellsForLegion(uint256 _legionId) external view returns(uint8) {
        require(isLegionQuesting(_legionId), "Legion is not questing");

        uint256 _corruptionBalance = appStorage.legionIdToLegionQuestingInfoV2[_legionId].corruptionAmount;

        (,uint8 _additionalCorruptedCells,,) = _getCorruptionEffects(_corruptionBalance);
        return _additionalCorruptedCells;
    }
}

struct EndingPartParams {
    uint8 endingPart;
    uint248 qpGained;
}
