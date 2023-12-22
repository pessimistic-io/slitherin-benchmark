// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Loot8UniformCollection.sol";
import "./ILoot8POAPTieredCollection.sol";

contract Loot8TieredCouponCollection is Loot8UniformCollection {

    using Counters for Counters.Counter;
        
    uint256 public maxTokens;
    address public tierCollection;

    constructor(
        string memory _name, 
        string memory _symbol,
        string memory _contractURI,
        bool _transferable,
        address _manager,
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
        _manager, 
        _governor, 
        _helper, 
        _trustedForwarder,
        _layerZeroEndpoint
    ) {
        tierCollection = _tierCollection;
        maxTokens = _maxTokens;
    }

    function isPatronEligibleForCoupon(address _patron) public view  returns(bool) {
        address[] memory _coupons = ILoot8POAPTieredCollection(tierCollection).getEligibleCouponsForPatron(_patron);

        for(uint256 i = 0; i < _coupons.length; i++) {
            if(_coupons[i] == address(this)) {
                return true;
            }
        }

        return false;
    }

    function mint(
        address _patron,
        uint256 _collectibleId
    ) public override
    {
        require(isPatronEligibleForCoupon(_patron), "PATRON INELIGIBLE");
        require(collectionCollectibleIds.current() <= maxTokens, "TOKEN LIMIT REACHED");
        Loot8Collection.mint(_patron, _collectibleId);
    }

    function mintNext(address _patron) public override {
        require(isPatronEligibleForCoupon(_patron), "PATRON INELIGIBLE");
        require(collectionCollectibleIds.current() <= maxTokens, "TOKEN LIMIT REACHED");
        Loot8Collection.mintNext(_patron);
    }
}
