//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./LegionMetadataStoreState.sol";
import "./ILegionMetadataStore.sol";

contract LegionMetadataStore is Initializable, ILegionMetadataStore, LegionMetadataStoreState {

    function initialize() external initializer {
        LegionMetadataStoreState.__LegionMetadataStoreState_init();
    }

    function setInitialMetadataForLegion(
        address _owner,
        uint256 _tokenId,
        LegionGeneration _generation,
        LegionClass _class,
        LegionRarity _rarity,
        uint256 _oldId)
    external override onlyAdminOrOwner whenNotPaused
    {
        idToGeneration[_tokenId] = _generation;
        idToClass[_tokenId] = _class;
        idToRarity[_tokenId] = _rarity;
        idToOldId[_tokenId] = _oldId;

        // Initial quest/craft level is 1.
        idToQuestLevel[_tokenId] = 1;
        idToCraftLevel[_tokenId] = 1;

        emit LegionCreated(_owner, _tokenId, _generation, _class, _rarity);
    }

    function increaseQuestLevel(uint256 _tokenId) external override onlyAdminOrOwner whenNotPaused {
        idToQuestLevel[_tokenId]++;

        emit LegionQuestLevelUp(_tokenId, idToQuestLevel[_tokenId]);
    }

    function increaseCraftLevel(uint256 _tokenId) external override onlyAdminOrOwner whenNotPaused {
        idToCraftLevel[_tokenId]++;

        emit LegionCraftLevelUp(_tokenId, idToCraftLevel[_tokenId]);
    }

    function increaseConstellationRank(uint256 _tokenId, Constellation _constellation, uint8 _to) external override onlyAdminOrOwner whenNotPaused {
        idToConstellationRanks[_tokenId][uint256(_constellation)] = _to;

        emit LegionConstellationRankUp(_tokenId, _constellation, _to);
    }

    function metadataForLegion(uint256 _tokenId) external view override returns(LegionMetadata memory) {
        return LegionMetadata(
            idToGeneration[_tokenId],
            idToClass[_tokenId],
            idToRarity[_tokenId],
            idToQuestLevel[_tokenId],
            idToCraftLevel[_tokenId],
            idToConstellationRanks[_tokenId],
            idToOldId[_tokenId]
        );
    }

    function genAndRarityForLegion(uint256 _tokenId) external view returns(LegionGeneration, LegionRarity) {
        return (idToGeneration[_tokenId], idToRarity[_tokenId]);
    }

    function tokenURI(uint256 _tokenId) external view override returns(string memory) {
        return _genToClassToRarityToOldIdToUri[idToGeneration[_tokenId]][idToClass[_tokenId]][idToRarity[_tokenId]][idToOldId[_tokenId]];
    }

    function setTokenUriForGenClassRarityOldId(LegionGeneration _gen, LegionClass _class, LegionRarity _rarity, uint256 _oldId, string calldata _uri) external onlyAdminOrOwner {
        _genToClassToRarityToOldIdToUri[_gen][_class][_rarity][_oldId] = _uri;
    }
}
