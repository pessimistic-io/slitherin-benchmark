/**************************************************************************************************************
// This contract will allow an entity to configure and push digital collectibles for corresponding passports.
// A new version of this contract should be created and deployed by a factory each time an org/entity
// offers a new type of passport to its patrons.
// The mobile app will interact with this contract to fetch information about various collectibles.
**************************************************************************************************************/
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Collectible.sol";
import "./ICollectible.sol";

contract DigitalCollectible is Collectible {
    
    /************ CRITERIA ******************/

    // This collectible needs the above criteria to be fulfilled on passport
    address public passport;

    struct DigitalCollectibleDetails {
        // Min reward balance needed to get this collectible airdropped
        int256 minRewardBalance;
        // Min visits needed to get this collectible airdropped
        uint256 minVisits;
        // Min friend visits needed to get this collectible airdropped
        uint256 minFriendVisits;
    }

    DigitalCollectibleDetails public digitalCollectibleDetails;

    constructor(
        address _entity,
        CollectibleData memory _collectibleData,
        DigitalCollectibleDetails memory _digitalCollectibleDetails,
        address _authority,
        address _passport,
        address _loot8Token,
        address _layerzeroEndpoint
    ) Collectible(_entity, CollectibleType.DIGITALCOLLECTIBLE, _collectibleData, _authority, _loot8Token, _layerzeroEndpoint) {
        
        passport = _passport;
        digitalCollectibleDetails = _digitalCollectibleDetails;
    }

    function mint (
        address _patron,
        uint256 _expiry,
        bool _transferable
    ) external override onlyEntityAdmin(entity) returns (uint256 _dcId) { 

        uint256 patronPassport = ICollectible(passport).getPatronNFT(_patron);
        require(ICollectible(passport).getNFTDetails(patronPassport).visits >= digitalCollectibleDetails.minVisits, "Not enough visits");
        require(ICollectible(passport).getNFTDetails(patronPassport).rewardBalance >= digitalCollectibleDetails.minRewardBalance, "Not enough reward balance");
        require(ICollectible(passport).getNFTDetails(patronPassport).friendVisits >= digitalCollectibleDetails.minFriendVisits, "Not enough friend visits");
        _dcId = Collectible._mint(_patron, _expiry, _transferable);

    }

    function toggle(uint256 _offerId) external onlyEntityAdmin(entity) returns(bool _status) {
        _status = _toggle(_offerId);
    }

    function retire() external onlyEntityAdmin(entity) {
        _retire();
    }

    function creditRewards(address _patron, uint256 _amount) external onlyBartender(entity) {
        // Bartender may be generous to a historic patron 
        // and grant them tokens from the entities balance 
        // of tokens
       _creditRewards(_patron, _amount);
    }

    function debitRewards(address _patron, uint256 _amount) external onlyBartender(entity) {
        _debitRewards(_patron, _amount);
    }

    function addVisit(uint256 _passportId) external pure {
        // Do nothing as business doesn't need this feature on digital collectibles
       return;
    }

    function addFriendsVisit(uint256 _passportId) external pure {
        // Do nothing as business doesn't need this feature on digital collectibles
       return;
    }

    function linkCollectible(address _collectible) external onlyEntityAdmin(entity) {
        _linkCollectible(_collectible);
    }

    function delinkCollectible(address _collectible) external onlyEntityAdmin(entity) {
        _delinkCollectible(_collectible);
    }

    function getPatronNFT(address _patron) public pure returns(uint256) {
        // Do nothing as business doesn't need this feature on digital collectibles
        return 0;
    }

    function rewards() external pure returns(uint256) {
        // Do nothing as business doesn't need this feature on digital collectibles
        return 0;
    }

    function setRedemption(uint256 _offerId) external onlyDispatcher {
        // Do nothing as business doesn't need this feature on digital collectibles
    }
}
