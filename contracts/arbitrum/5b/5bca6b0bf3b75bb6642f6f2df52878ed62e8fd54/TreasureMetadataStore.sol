//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TreasureMetadataStoreState.sol";
import "./ITreasureMetadataStore.sol";

contract TreasureMetadataStore is ITreasureMetadataStore, TreasureMetadataStoreState {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        TreasureMetadataStoreState.__TreasureMetadataStoreState_init();
    }

    function setMetadataForIds(uint256[] calldata _ids, TreasureMetadata[] calldata _metadatas) external override onlyAdminOrOwner {
        require(_ids.length > 0, "No IDs given");
        require(_ids.length == _metadatas.length, "Bad lengths");

        for(uint256 i = 0; i < _ids.length; i++) {
            require(_metadatas[i].tier > 0, "Bad tier");

            TreasureMetadata memory _oldMetadata = treasureIdToMetadata[_ids[i]];
            if(_oldMetadata.tier > 0) {
                tierToTreasureIds[_oldMetadata.tier].remove(_ids[i]);

                if(_oldMetadata.isMintable) {
                    tierToMintableTreasureIds[_oldMetadata.tier].remove(_ids[i]);
                    tierToCategoryToMintableTreasureIds[_oldMetadata.tier][_oldMetadata.category].remove(_ids[i]);
                }
            }

            treasureIdToMetadata[_ids[i]] = _metadatas[i];
            tierToTreasureIds[_metadatas[i].tier].add(_ids[i]);
            if(_metadatas[i].isMintable) {
                tierToMintableTreasureIds[_metadatas[i].tier].add(_ids[i]);
                tierToCategoryToMintableTreasureIds[_metadatas[i].tier][_metadatas[i].category].add(_ids[i]);
            }
        }
    }

    function hasMetadataForTreasureId(uint256 _treasureId) external view override returns(bool) {
        return treasureIdToMetadata[_treasureId].tier != 0;
    }

    function getRandomTreasureForTier(uint8 _tier, uint256 _randomNumber) external view override returns(uint256) {
        uint256[] memory _mintableIds = tierToMintableTreasureIds[_tier].values();
        require(_mintableIds.length > 0, "TreasureMetadataStore: No IDs available for tier");

        uint256 _resultIndex = _randomNumber % _mintableIds.length;
        return _mintableIds[_resultIndex];
    }

    function getAnyRandomTreasureForTier(uint8 _tier, uint256 _randomNumber) external view override returns(uint256) {
        uint256 _numberTreasuresInTier = tierToTreasureIds[_tier].length();
        require(_numberTreasuresInTier > 0, "TreasureMetadataStore: No IDs available for tier");

        return tierToTreasureIds[_tier].at(_randomNumber % _numberTreasuresInTier);
    }

    function getRandomTreasureForTierAndCategory(
        uint8 _tier,
        TreasureCategory _category,
        uint256 _randomNumber)
    external
    view
    override
    returns(uint256)
    {
        uint256[] memory _mintableIds = tierToCategoryToMintableTreasureIds[_tier][_category].values();
        require(_mintableIds.length > 0, "TreasureMetadataStore: No IDs available for tier and category");

        uint256 _resultIndex = _randomNumber % _mintableIds.length;
        return _mintableIds[_resultIndex];
    }

    function getMetadataForTreasureId(uint256 _treasureId) external view override returns(TreasureMetadata memory) {
        TreasureMetadata memory _metadata = treasureIdToMetadata[_treasureId];
        require(_metadata.tier > 0, "No metadata for ID.");
        return _metadata;
    }

}
