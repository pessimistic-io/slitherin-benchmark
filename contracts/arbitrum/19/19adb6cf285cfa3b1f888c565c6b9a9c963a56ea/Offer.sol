// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Collectible.sol";
import "./IEntity.sol";
import "./IDispatcher.sol";
import "./ITokenPriceCalculator.sol";

import "./Counters.sol";

contract Offer is Collectible {

    using Counters for Counters.Counter;

    enum OfferType { 
        FEATURED,
        REGULAR 
    }

    struct OfferDetails {
        uint256 duration;
        uint256 price; //offer price. 6 decimals precision 24494022 = 24.56 USD
        uint256 maxPurchase;
        uint256 expiry;
        bool transferable;
        OfferType offerType;
    }

    OfferDetails public offerDetails;
    uint256 public rewards;

    constructor(
        address _entity,
        CollectibleData memory _collectibleData,
        OfferDetails memory _offerDetails,
        address _authority,
        address _loot8Token,
        address _layerzeroEndpoint
    ) Collectible(
                    _entity, 
                    CollectibleType.OFFER, 
                    _collectibleData,
                    _authority, 
                    _loot8Token,
                    _layerzeroEndpoint
                ) {

    
        offerDetails = _offerDetails;
        rewards = _calculateRewards(_offerDetails.price);

        IDispatcher(authority.dispatcher()).addOfferWithContext(address(this), offerDetails.maxPurchase, offerDetails.expiry, offerDetails.transferable);
    }

    function mint (
        address _patron, 
        uint256 _expiry, 
        bool _transferable
    ) external override returns (uint256 _offerId) {
        require(_msgSender() == address(this), "UNAUTHORIZED");
        _offerId = Collectible._mint(_patron, _expiry, _transferable);
    }

    function toggle(uint256 _offerId) external onlyBartender(entity) returns(bool _status) {
        _status = _toggle(_offerId);
    }

    function retire() external onlyEntityAdmin(entity) {
        _retire();
    }

    function setRedemption(uint256 _offerId) external onlyDispatcher {
        _setRedemption(_offerId);
    }

    function creditRewards(address _patron, uint256 _amount) external pure {
        // Do nothing as business doesn't need this feature on offers
       return;
    }

    function debitRewards(address _patron, uint256 _amount) external pure {
        // Do nothing as business doesn't need this feature on offers
       return;
    }

    function addVisit(uint256 _offerId) external pure {
        // Do nothing as business doesn't need this feature on offers
       return;
    }

    function addFriendsVisit(uint256 _offerId) external pure {
        // Do nothing as business doesn't need this feature on offers
       return;
    }

    function linkCollectible(address _collectible) external onlyEntityAdmin(entity) {
        _linkCollectible(_collectible);
    }

    function delinkCollectible(address _collectible) external onlyEntityAdmin(entity) {
        _delinkCollectible(_collectible);
    }

    function getPatronNFT(address _patron) public pure returns(uint256) {
        // Do nothing as business doesn't need this feature on offers
        return 0;
    }

    function updateDataURI(string memory _dataURI) external onlyEntityAdmin(entity) {
        _updateDataURI(_dataURI);
    }
}
