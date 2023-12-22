//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CryptsLegionHandlerContracts.sol";

contract CryptsLegionHandler is Initializable, CryptsLegionHandlerContracts
{

    function initialize() external initializer {
        CryptsLegionHandlerContracts.__CryptsLegionHandlerContracts_init();
    }

    function setStakingAllowed(bool _stakingAllowed) external onlyAdminOrOwner {
        _setStakingAllowed(_stakingAllowed);
    }

    function _setStakingAllowed(bool _stakingAllowed) private {
        stakingAllowed = _stakingAllowed;
    }

    function handleStake(CharacterInfo memory _characterInfo, address _user)
        public
    {
        require(msg.sender == address(corruptionCrypts), "Must call from crypts");
        require(stakingAllowed, "Staking is not allowed");

        //Ensure they're not a recruit
        require(
            legionMetadataStore
                .metadataForLegion(_characterInfo.tokenId)
                .legionGeneration != LegionGeneration.RECRUIT,
            "Legion cannot be a recruit!"
        );

        //Transfer it to the staking contract
        legionContract.adminSafeTransferFrom(
            _user,
            address(this),
            _characterInfo.tokenId
        );
    }

    function handleUnstake(CharacterInfo memory _characterInfo, address _user)
        public
    {
        require(msg.sender == address(corruptionCrypts), "Must call from crypts");

        //Transfer it from the staking contract
        legionContract.adminSafeTransferFrom(
            address(this),
            _user,
            _characterInfo.tokenId
        );
    }

    function getCorruptionDiversionPointsForToken(uint32 _tokenId) public view returns(uint24) {
        LegionMetadata memory _metadata = legionMetadataStore.metadataForLegion(_tokenId);

        // Lookup the diversion points for this legion.
        return generationToRarityToCorruptionDiversion[_metadata.legionGeneration][_metadata.legionRarity];
    }

    function getCorruptionCraftingClaimedPercent(uint32 _tokenId) public view returns(uint32){
        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_tokenId);
        require(_legionMetadata.legionGeneration == LegionGeneration.GENESIS
            || _legionMetadata.craftLevel >= minimumCraftLevelForAuxCorruption, "Craft level too low");

        return generationToRarityToPercentOfPoolClaimed[_legionMetadata.legionGeneration][_legionMetadata.legionRarity];
    }
}

