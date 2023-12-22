//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ILegionMetadataStore.sol";

contract LegionMetadataStore is Initializable, ILegionMetadataStore {
    event LegionQuestLevelUp(uint256 indexed _tokenId, uint8 _questLevel);
    event LegionCraftLevelUp(uint256 indexed _tokenId, uint8 _craftLevel);
    event LegionConstellationRankUp(uint256 indexed _tokenId, Constellation indexed _constellation, uint8 _rank);
    event LegionCreated(
        address indexed _owner,
        uint256 indexed _tokenId,
        LegionGeneration _generation,
        LegionClass _class,
        LegionRarity _rarity
    );

    mapping(uint256 => LegionGeneration) internal idToGeneration;
    mapping(uint256 => LegionClass) internal idToClass;
    mapping(uint256 => LegionRarity) internal idToRarity;
    mapping(uint256 => uint256) internal idToOldId;
    mapping(uint256 => uint8) internal idToQuestLevel;
    mapping(uint256 => uint8) internal idToCraftLevel;
    mapping(uint256 => uint8[6]) internal idToConstellationRanks;

    mapping(LegionGeneration => mapping(LegionClass => mapping(LegionRarity => mapping(uint256 => string))))
        internal _genToClassToRarityToOldIdToUri;

    function initialize() external initializer {}

    function setInitialMetadataForLegion(
        address _owner,
        uint256 _tokenId,
        LegionGeneration _generation,
        LegionClass _class,
        LegionRarity _rarity,
        uint256 _oldId
    ) external override {
        idToGeneration[_tokenId] = _generation;
        idToClass[_tokenId] = _class;
        idToRarity[_tokenId] = _rarity;
        idToOldId[_tokenId] = _oldId;

        // Initial quest/craft level is 1.
        idToQuestLevel[_tokenId] = 1;
        idToCraftLevel[_tokenId] = 1;

        emit LegionCreated(_owner, _tokenId, _generation, _class, _rarity);
    }

    function increaseQuestLevel(uint256 _tokenId) external override {
        idToQuestLevel[_tokenId]++;

        emit LegionQuestLevelUp(_tokenId, idToQuestLevel[_tokenId]);
    }

    function increaseCraftLevel(uint256 _tokenId) external override {
        idToCraftLevel[_tokenId]++;

        emit LegionCraftLevelUp(_tokenId, idToCraftLevel[_tokenId]);
    }

    function increaseConstellationRank(
        uint256 _tokenId,
        Constellation _constellation,
        uint8 _to
    ) external override {
        idToConstellationRanks[_tokenId][uint256(_constellation)] = _to;

        emit LegionConstellationRankUp(_tokenId, _constellation, _to);
    }

    function metadataForLegion(uint256 _tokenId) external view override returns (LegionMetadata memory) {
        return
            LegionMetadata(
                idToGeneration[_tokenId],
                idToClass[_tokenId],
                idToRarity[_tokenId],
                idToQuestLevel[_tokenId],
                idToCraftLevel[_tokenId],
                idToConstellationRanks[_tokenId],
                idToOldId[_tokenId]
            );
    }

    function tokenURI(uint256 _tokenId) external view override returns (string memory) {
        return
            _genToClassToRarityToOldIdToUri[idToGeneration[_tokenId]][idToClass[_tokenId]][idToRarity[_tokenId]][
                idToOldId[_tokenId]
            ];
    }

    function setTokenUriForGenClassRarityOldId(
        LegionGeneration _gen,
        LegionClass _class,
        LegionRarity _rarity,
        uint256 _oldId,
        string calldata _uri
    ) external {
        _genToClassToRarityToOldIdToUri[_gen][_class][_rarity][_oldId] = _uri;
    }
}

