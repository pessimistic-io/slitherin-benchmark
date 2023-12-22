//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./MiniCraftingContracts.sol";

contract MiniCrafting is Initializable, MiniCraftingContracts {

    function initialize() external initializer {
        MiniCraftingContracts.__MiniCraftingContracts_init();
    }

    function setRecruitTierInfo(
        uint8 _tier,
        bool _canRecruitCraft,
        uint16 _prismShardsRequired,
        uint32 _expGained,
        uint16 _minRecruitLevel,
        uint8 _fragmentsRequired)
    external
    onlyAdminOrOwner
    {
        require(_tier >= 1 && _tier <= 5, "Bad Tier");

        tierToRecruitTierInfo[_tier].canRecruitCraft = _canRecruitCraft;
        tierToRecruitTierInfo[_tier].prismShardsRequired = _prismShardsRequired;
        tierToRecruitTierInfo[_tier].expGained = _expGained;
        tierToRecruitTierInfo[_tier].minRecruitLevel = _minRecruitLevel;
        tierToRecruitTierInfo[_tier].fragmentsRequired = _fragmentsRequired;

        emit RecruitTierInfoSet(
            _tier,
            _canRecruitCraft,
            _prismShardsRequired,
            _expGained,
            _minRecruitLevel,
            _fragmentsRequired);
    }

    function updateCraftingLevelRequirements(uint8[5] calldata _minimumLevelPerTier) external onlyAdminOrOwner {
        for(uint8 i = 0; i < _minimumLevelPerTier.length; i++) {
            tierToTierInfo[i + 1].minimumCraftingLevel = _minimumLevelPerTier[i];
        }
    }

    function updateCraftingXpGain(uint8[5] calldata _xpAmts) external onlyAdminOrOwner {
        for(uint8 i = 0; i < _xpAmts.length; i++) {
            tierToTierInfo[i + 1].craftingCPGained = _xpAmts[i];
        }
    }

    function updateMagicCosts(uint128[5] calldata _magicCosts) external onlyAdminOrOwner {
        for(uint8 i = 0; i < _magicCosts.length; i++) {
            tierToTierInfo[i + 1].magicCost = _magicCosts[i];
        }
    }

    function craftTreasures(
        CraftTreasureParams[] calldata _craftTreasureParams)
    external
    whenNotPaused
    onlyEOA
    contractsAreSet
    {
        require(_craftTreasureParams.length > 0, "MiniCrafting: No crafts passed in");

        uint256 _randomNumber = _getPseudoRandomNumber();

        for(uint256 i = 0; i < _craftTreasureParams.length; i++) {
            if(i != 0) {
                _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
            }
            _craftTreasure(_craftTreasureParams[i], _randomNumber);
        }
    }

    function _craftTreasure(CraftTreasureParams calldata _craftTreasureParam, uint256 _randomNumber) private {
        require(legion.ownerOf(_craftTreasureParam.legionId) == msg.sender, "MiniCrafting: Must own the legion");

        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_craftTreasureParam.legionId);

        FragmentInfo storage _fragmentInfo = fragmentIdToInfo[_craftTreasureParam.treasureFragmentId];

        require(_craftTreasureParam.treasureFragmentId > 0 && _craftTreasureParam.treasureFragmentId < 16, "MiniCrafting: Bad fragment ID");

        if(_legionMetadata.legionGeneration == LegionGeneration.RECRUIT) {
            _craftTreasureRecruit(_craftTreasureParam, _randomNumber, _fragmentInfo);
        } else {
            _craftTreasureRegular(_craftTreasureParam, _legionMetadata, _randomNumber, _fragmentInfo);
        }
    }

    function _craftTreasureRecruit(
        CraftTreasureParams calldata _craftTreasureParam,
        uint256 _randomNumber,
        FragmentInfo storage _fragmentInfo)
    private
    {
        RecruitTierInfo storage _recruitTierInfo = tierToRecruitTierInfo[_fragmentInfo.tier];

        require(_recruitTierInfo.canRecruitCraft, "MiniCrafting: Recruit cannot craft this tier of fragments");

        uint16 _recruitLevelCur = recruitLevel.getRecruitLevel(_craftTreasureParam.legionId);
        require(_recruitLevelCur >= _recruitTierInfo.minRecruitLevel, "MiniCrafting: Not minimum level");

        _burnShardsAndFragments(
            _recruitTierInfo.prismShardsRequired,
            _craftTreasureParam.treasureFragmentId,
            _recruitTierInfo.fragmentsRequired
        );

        uint256 _mintedTreasureId = _mintTreasure(_fragmentInfo, _randomNumber);

        if(_recruitTierInfo.expGained > 0) {
            recruitLevel.increaseRecruitExp(_craftTreasureParam.legionId, _recruitTierInfo.expGained);
        }

        emit CraftingFinished(msg.sender, _craftTreasureParam.legionId, _fragmentInfo.tier, 0, _mintedTreasureId);
    }

    function _craftTreasureRegular(
        CraftTreasureParams calldata _craftTreasureParam,
        LegionMetadata memory _legionMetadata,
        uint256 _randomNumber,
        FragmentInfo storage _fragmentInfo)
    private
    {
        FragmentTierInfo storage _tierInfo = tierToTierInfo[_fragmentInfo.tier];

        require(_legionMetadata.craftLevel >= _tierInfo.minimumCraftingLevel, "MiniCrafting: Crafting level too low");

        // Transfer magic, burn prism shards, and burn the required number of fragments. These will revert if user does not own enough.
        if(_tierInfo.magicCost > 0) {
            bool _magicTransferSuccess = magic.transferFrom(msg.sender, address(treasury), _tierInfo.magicCost);
            require(_magicTransferSuccess, "MiniCrafting: Magic did not transfer");

            // Forward a portion to the mine.
            treasury.forwardCoinsToMine(_tierInfo.magicCost);
        }

        _burnShardsAndFragments(
            _tierInfo.prismShardsRequired,
            _craftTreasureParam.treasureFragmentId,
            _tierInfo.fragmentsRequired
        );

        uint256 _mintedTreasureId = _mintTreasure(_fragmentInfo, _randomNumber);

        // Add CP/Level up
        crafting.processCPGainAndLevelUp(_craftTreasureParam.legionId, _legionMetadata.craftLevel, _tierInfo.craftingCPGained);

        emit CraftingFinished(msg.sender, _craftTreasureParam.legionId, _fragmentInfo.tier, _tierInfo.craftingCPGained, _mintedTreasureId);
    }

    function _determineTreasureCategory(TreasureCategory[] storage _categories, uint256 _randomNumber) private view returns(TreasureCategory) {
        if(_categories.length == 1) {
            return _categories[0];
        } else {
            uint256 _index = _randomNumber % _categories.length;
            return _categories[_index];
        }
    }

    function _burnShardsAndFragments(uint256 _prismShardsAmount, uint256 _treasureFragmentId, uint256 _fragmentsAmount) private {
        if(_prismShardsAmount > 0) {
            consumable.adminSafeTransferFrom(msg.sender, address(treasury), prismShardId, _prismShardsAmount);
        }
        if(_fragmentsAmount > 0) {
            treasureFragment.burn(msg.sender, _treasureFragmentId, _fragmentsAmount);
        }
    }

    function _mintTreasure(FragmentInfo storage _fragmentInfo, uint256 _randomNumber) private returns(uint256) {
        TreasureCategory _categoryToMint = _determineTreasureCategory(_fragmentInfo.categories, _randomNumber);
        _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));

        // Get random id for tier + category
        uint256 _treasureIdToMint = treasureMetadataStore.getRandomTreasureForTierAndCategory(
            _fragmentInfo.tier,
            _categoryToMint,
            _randomNumber
        );

        // Mint treasure
        treasure.mint(msg.sender, _treasureIdToMint, 1);

        return _treasureIdToMint;
    }

    // This random number is only used to determine the category and id of treasures. The tier is fixed.
    // It wouldn't do much good to game this and saves user's money by keeping it at one txn.
    function _getPseudoRandomNumber() private view returns(uint256) {
        return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, block.number, msg.sender)));
    }
}

struct CraftTreasureParams {
    // Even though the crafting is instance, a legion is still required to craft with.
    uint128 legionId;
    // The treasure fragment id that will be used to create a treasure.
    uint128 treasureFragmentId;
}
