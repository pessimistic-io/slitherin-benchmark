//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./MiniCraftingContracts.sol";

contract MiniCrafting is Initializable, MiniCraftingContracts {

    function initialize() external initializer {
        MiniCraftingContracts.__MiniCraftingContracts_init();
    }

    function updateCraftingLevelRequirements(uint8[5] calldata _minimumLevelPerTier) external onlyAdminOrOwner {
        for(uint8 i = 0; i < _minimumLevelPerTier.length; i++) {
            tierToTierInfo[i + 1].minimumCraftingLevel = _minimumLevelPerTier[i];
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

        for(uint256 i = 0; i < _craftTreasureParams.length; i++) {
            _craftTreasure(_craftTreasureParams[i]);
        }
    }

    function _craftTreasure(CraftTreasureParams calldata _craftTreasureParam) private {
        require(legion.ownerOf(_craftTreasureParam.legionId) == msg.sender, "MiniCrafting: Must own the legion");

        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_craftTreasureParam.legionId);
        require(_legionMetadata.legionGeneration != LegionGeneration.RECRUIT, "MiniCrafting: Cannot craft with recruit");

        require(_craftTreasureParam.treasureFragmentId > 0 && _craftTreasureParam.treasureFragmentId < 16, "MiniCrafting: Bad fragment ID");

        FragmentInfo storage _fragmentInfo = fragmentIdToInfo[_craftTreasureParam.treasureFragmentId];

        FragmentTierInfo storage _tierInfo = tierToTierInfo[_fragmentInfo.tier];

        require(_legionMetadata.craftLevel >= _tierInfo.minimumCraftingLevel, "MiniCrafting: Crafting level too low");

        // Transfer magic, burn prism shards, and burn the required number of fragments. These will revert if user does not own enough.
        if(_tierInfo.magicCost > 0) {
            bool _magicTransferSuccess = magic.transferFrom(msg.sender, address(treasury), _tierInfo.magicCost);
            require(_magicTransferSuccess, "MiniCrafting: Magic did not transfer");

            // Forward a portion to the mine.
            treasury.forwardCoinsToMine(_tierInfo.magicCost);
        }
        if(_tierInfo.prismShardsRequired > 0) {
            consumable.adminSafeTransferFrom(msg.sender, address(treasury), prismShardId, _tierInfo.prismShardsRequired);
        }
        if(_tierInfo.fragmentsRequired > 0) {
            treasureFragment.burn(msg.sender, _craftTreasureParam.treasureFragmentId, _tierInfo.fragmentsRequired);
        }

        uint256 _randomNumber = _getPseudoRandomNumber();

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

        // Add CP/Level up
        crafting.processCPGainAndLevelUp(_craftTreasureParam.legionId, _legionMetadata.craftLevel, _tierInfo.craftingCPGained);

        emit CraftingFinished(msg.sender, _craftTreasureParam.legionId, _fragmentInfo.tier, _tierInfo.craftingCPGained, _treasureIdToMint);
    }

    function _determineTreasureCategory(TreasureCategory[] storage _categories, uint256 _randomNumber) private view returns(TreasureCategory) {
        if(_categories.length == 1) {
            return _categories[0];
        } else {
            uint256 _index = _randomNumber % _categories.length;
            return _categories[_index];
        }
    }

    // This random number is only used to determine the category and id of treasures. The tier is fixed.
    // It wouldn't do much good to game this and saves user's money by keeping it at one txn.
    function _getPseudoRandomNumber() private view returns(uint256) {
        return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, block.number)));
    }
}

struct CraftTreasureParams {
    // Even though the crafting is instance, a legion is still required to craft with.
    uint128 legionId;
    // The treasure fragment id that will be used to create a treasure.
    uint128 treasureFragmentId;
}
