//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721HolderUpgradeable.sol";
import "./Initializable.sol";
import "./ILegionMetadataStore.sol";
import "./AdminableUpgradeable.sol";
import "./ICryptsCharacterHandler.sol";
import "./ICorruptionCrypts.sol";
import "./ILegion.sol";

abstract contract CryptsLegionHandlerState is
    Initializable,
    AdminableUpgradeable,
    ERC721HolderUpgradeable,
    ICryptsCharacterHandler
{

    event MinimumCraftLevelForAuxCorruptionSet(uint256 craftLevel);
    event MalevolentPrismsPerCraftSet(uint256 malevolentPrisms);
    event LegionPercentOfPoolClaimedChanged(LegionGeneration generation, LegionRarity rarity, uint32 percentOfPool);

    ILegionMetadataStore public legionMetadataStore;
    ILegion public legionContract;
    ICorruptionCrypts public corruptionCrypts;

    bool public stakingAllowed;

    uint256 public minimumCraftLevelForAuxCorruption;

    mapping(LegionGeneration => mapping(LegionRarity => uint24)) public generationToRarityToCorruptionDiversion;
    mapping(LegionGeneration => mapping(LegionRarity => uint32)) public generationToRarityToPercentOfPoolClaimed;

    function __CryptsLegionHandlerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();

        uint24[7] memory _corruptionDivertedAmounts = [uint24(600), uint24(400), uint24(200), uint24(150), uint24(100), uint24(10), uint24(5)];
        _setCorruptionDiverted(_corruptionDivertedAmounts);

        uint32[8] memory _percentOfPoolClaimedAmounts = [uint32(1400), uint32(1000), uint32(600), uint32(500), uint32(400), uint32(220), uint32(210), uint32(200)];
        _setPercentOfPoolClaimed(_percentOfPoolClaimedAmounts);
    }

    function _setLegionPercentOfPoolClaimed(
        LegionGeneration _generation,
        LegionRarity _rarity,
        uint32 _percent)
    private
    {
        generationToRarityToPercentOfPoolClaimed[_generation][_rarity] = _percent;
        emit LegionPercentOfPoolClaimedChanged(_generation, _rarity, _percent);
    }

    function _setCorruptionDiverted(uint24[7] memory _amounts) public onlyOwner {
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.LEGENDARY] = _amounts[0];
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.RARE] = _amounts[1];
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.UNCOMMON] = _amounts[2];
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.SPECIAL] = _amounts[3];
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.COMMON] = _amounts[4];
        generationToRarityToCorruptionDiversion[LegionGeneration.AUXILIARY][LegionRarity.RARE] = _amounts[5];
        generationToRarityToCorruptionDiversion[LegionGeneration.AUXILIARY][LegionRarity.UNCOMMON] = _amounts[6];
    }

    function _setPercentOfPoolClaimed(uint32[8] memory _amounts) public onlyOwner {
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.LEGENDARY, _amounts[0]);
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.RARE, _amounts[1]);
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.UNCOMMON, _amounts[2]);
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.SPECIAL, _amounts[3]);
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.COMMON, _amounts[4]);
        _setLegionPercentOfPoolClaimed(LegionGeneration.AUXILIARY, LegionRarity.RARE, _amounts[5]);
        _setLegionPercentOfPoolClaimed(LegionGeneration.AUXILIARY, LegionRarity.UNCOMMON, _amounts[6]);
        _setLegionPercentOfPoolClaimed(LegionGeneration.AUXILIARY, LegionRarity.COMMON, _amounts[7]);
    }
}
