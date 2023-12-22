//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./RecruitLevelContracts.sol";

abstract contract RecruitLevelSettings is Initializable, RecruitLevelContracts {

    function __RecruitLevelSettings_init() internal initializer {
        RecruitLevelContracts.__RecruitLevelContracts_init();

        _setLevelUpInfo(1, 10);
        _setLevelUpInfo(2, 20);
        _setLevelUpInfo(3, 40);
        _setLevelUpInfo(4, 70);
        _setLevelUpInfo(5, 100);
        _setLevelUpInfo(6, 130);
        _setLevelUpInfo(7, 175);
        _setLevelUpInfo(8, 230);

        _setMaxLevel(9);

        _setAscensionInfo(3, 6, 6, 7, 12, 12);
    }

    function setSModifier(uint32 _sModifier) external onlyAdminOrOwner {
        auxAscensionInfo.sModifier = _sModifier;
    }

    function setDModifier(uint32 _dModifier) external onlyAdminOrOwner {
        auxAscensionInfo.dModifier = _dModifier;
    }

    function setMagicCostForAux(uint128 _magicCostForAux) external onlyAdminOrOwner {
        auxAscensionInfo.magicCost = _magicCostForAux;

        emit MagicCostForAuxSet(_magicCostForAux);
    }

    function setAscensionCapRatePerSecond(uint128 _ascensionCapRatePerSecond) external onlyAdminOrOwner {
        auxAscensionInfo.capAtLastRateChange += uint128((block.timestamp - auxAscensionInfo.timeCapLastChanged) * auxAscensionInfo.capRatePerSecond);
        auxAscensionInfo.capRatePerSecond = _ascensionCapRatePerSecond;
        auxAscensionInfo.timeCapLastChanged = uint128(block.timestamp);
    }

    function setLevelUpInfo(uint16 _levelCur, uint32 _expToNextLevel) external onlyAdminOrOwner {
        _setLevelUpInfo(_levelCur, _expToNextLevel);
    }

    function setMaxLevel(uint16 _maxLevel) external onlyAdminOrOwner {
        _setMaxLevel(_maxLevel);
    }

    function setAscensionInfo(
        uint16 _minimumLevelCadet,
        uint16 _numEoSCadet,
        uint16 _numPrismShardsCadet,
        uint16 _minimumLevelApprentice,
        uint16 _numEoSApprentice,
        uint16 _numPrismShardsApprentice)
    external
    onlyAdminOrOwner
    {
        _setAscensionInfo(
            _minimumLevelCadet,
            _numEoSCadet,
            _numPrismShardsCadet,
            _minimumLevelApprentice,
            _numEoSApprentice,
            _numPrismShardsApprentice
        );
    }

    function _setLevelUpInfo(uint16 _levelCur, uint32 _expToNextLevel) private {
        levelCurToLevelUpInfo[_levelCur].expToNextLevel = _expToNextLevel;

        emit LevelUpInfoSet(_levelCur, _expToNextLevel);
    }

    function _setMaxLevel(uint16 _maxLevel) private {
        require(maxLevel < _maxLevel, "Can't decrease max level");

        maxLevel = _maxLevel;

        emit MaxLevelSet(_maxLevel);
    }

    function _setAscensionInfo(
        uint16 _minimumLevelCadet,
        uint16 _numEoSCadet,
        uint16 _numPrismShardsCadet,
        uint16 _minimumLevelApprentice,
        uint16 _numEoSApprentice,
        uint16 _numPrismShardsApprentice)
    private
    {
        ascensionInfo.minimumLevelCadet = _minimumLevelCadet;
        ascensionInfo.numEoSCadet = _numEoSCadet;
        ascensionInfo.numPrismShardsCadet = _numPrismShardsCadet;
        ascensionInfo.minimumLevelApprentice = _minimumLevelApprentice;
        ascensionInfo.numEoSApprentice = _numEoSApprentice;
        ascensionInfo.numPrismShardsApprentice = _numPrismShardsApprentice;

        emit AscensionInfoSet(
            _minimumLevelCadet,
            _numEoSCadet,
            _numPrismShardsCadet,
            _minimumLevelApprentice,
            _numEoSApprentice,
            _numPrismShardsApprentice
        );
    }
}
