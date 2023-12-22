// SPDX-License-Identifier: MIT
// Creator: base64.tech
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SamuRiseLandErrors.sol";

interface ISamuRiseItemsV3 {
     function mintFromQuest(address _originator, uint256 _collectionId, uint256 _numberToClaim, uint256 _maxAllocation) external;
}

interface ISamuRiseLandMetadataState {
    function increaseTokenIdToDojoRarityBonus(uint256 _tokenId, uint256 _bonusAmount) external;
    function setLandTokenIdFactionAndProvince(uint256 _tokenId, uint256 _faction, uint256 _province) external;
}

contract SamuRiseQuest is UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable
{
    mapping(address => bool) contractAddressToIsWhiteListed;
    
    address samuriseItems;
    address samuriseLandMetaData;

    function initialize() public initializer {
        __Ownable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _pause();
    }

    modifier callerIsWhitelistedContract() {
        require(contractAddressToIsWhiteListed[msg.sender], "caller is not whitelisted");

        _;
    }

    function mintItem(address _originator, uint256 _collectionId, uint256 _numberToClaim, uint256 _maxAllocation) 
        public
        callerIsWhitelistedContract()
        whenNotPaused 
    {
         ISamuRiseItemsV3(samuriseItems).mintFromQuest(_originator, _collectionId, _numberToClaim, _maxAllocation);
    }

    function increaseTokenIdToDojoRarityBonus(uint256 _landTokenId, uint256 _bonusAmount) 
        public 
        callerIsWhitelistedContract()
        whenNotPaused 
    {
        ISamuRiseLandMetadataState(samuriseLandMetaData).increaseTokenIdToDojoRarityBonus(_landTokenId, _bonusAmount);
    }

    function setLandTokenIdFactionAndProvince(uint256 _tokenId, uint256 _faction, uint256 _province)
        public 
        callerIsWhitelistedContract()
        whenNotPaused 
    {
        ISamuRiseLandMetadataState(samuriseLandMetaData).setLandTokenIdFactionAndProvince(_tokenId, _faction, _province);
    }
   
   /* OWNER FUNCTIONS */

    function setSamuriseItemsContract(address _samuriseItems) external onlyOwner {
        samuriseItems = _samuriseItems;
    }

    function setSamuRiseLandMetadataStateContract(address _samuriseLandMetaData) external onlyOwner {
        samuriseLandMetaData = _samuriseLandMetaData;
    }


    function addAddressToWhiteList(address _address) public onlyOwner {
        contractAddressToIsWhiteListed[_address] = true;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

   function _authorizeUpgrade(address) internal override onlyOwner {}
}
