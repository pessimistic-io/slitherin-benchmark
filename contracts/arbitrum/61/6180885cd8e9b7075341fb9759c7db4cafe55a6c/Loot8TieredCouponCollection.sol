// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Loot8UniformCollection.sol";
import "./ILoot8TieredPOAPCollection.sol";
import "./ERC721Enumerable.sol";

contract Loot8TieredCouponCollection is Loot8UniformCollection {

    using Counters for Counters.Counter;
        
    uint256 public maxTokens;
    address public tierCollection;

    constructor(
        string memory _name, 
        string memory _symbol,
        string memory _contractURI,
        bool _transferable,
        address _governor,
        address _helper,
        address _trustedForwarder,
        address _layerZeroEndpoint,
        address _tierCollection,
        uint256 _maxTokens
    ) Loot8UniformCollection(
        _name, 
        _symbol, 
        _contractURI, 
        _transferable, 
        _governor, 
        _helper, 
        _trustedForwarder,
        _layerZeroEndpoint
    ) {
        tierCollection = _tierCollection;
        maxTokens = _maxTokens;
    }

    function isPatronEligibleForCoupon(address _patron) public view returns(bool, uint256) {
        
        address[] memory _coupons = ILoot8TieredPOAPCollection(tierCollection).getEligibleCouponsForPatron(_patron);
        uint256 i;

        while(i < _coupons.length) {
            if(_coupons[i] == address(this)) {
                break;
            }

            i++;
        }

        if(i == _coupons.length) {
            return (false, 0);
        }

        uint256 j;
        uint256 patronBalance = ERC721(tierCollection).balanceOf(_patron);
        uint256 tokenId;

        while(j < patronBalance) {
            tokenId = ERC721Enumerable(tierCollection).tokenOfOwnerByIndex(_patron, j);
            if(!ILoot8TieredPOAPCollection(tierCollection).checkCouponAirdroppedForToken(tokenId, address(this))) {
                break;
            }
            j++;
        }

        if(j == patronBalance) {
            return (false, 0);
        }

        return (true, tokenId);
    }

    function mint(address _patron, uint256 _collectibleId) public override {
        (bool patronEligible, uint256 tieredTokenId) = isPatronEligibleForCoupon(_patron);
        require(patronEligible && tieredTokenId > 0, "PATRON INELIGIBLE");
        require(collectionCollectibleIds.current() <= maxTokens, "TOKEN LIMIT REACHED");
        Loot8Collection.mint(_patron, _collectibleId);
        ILoot8TieredPOAPCollection(tierCollection).setCouponAirdroppedForToken(tieredTokenId);
    }

    function mintNext(address _patron) public override {
        (bool patronEligible, uint256 tieredTokenId) = isPatronEligibleForCoupon(_patron);
        require(patronEligible && tieredTokenId > 0, "PATRON INELIGIBLE");
        require(collectionCollectibleIds.current() <= maxTokens, "TOKEN LIMIT REACHED");
        Loot8Collection.mintNext(_patron);
        ILoot8TieredPOAPCollection(tierCollection).setCouponAirdroppedForToken(tieredTokenId);
    }

}
