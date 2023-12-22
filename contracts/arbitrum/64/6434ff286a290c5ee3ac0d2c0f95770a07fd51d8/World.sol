//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./WorldContracts.sol";

contract World is Initializable, WorldContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        WorldContracts.__WorldContracts_init();
    }

    function transferToadzToHuntingGrounds(
        uint256[] calldata _tokenIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_tokenIds)
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];

            _requireValidToadAndLocation(_tokenId, Location.HUNTING_GROUNDS);

            // From
            _transferFromLocation(_tokenId);

            // To
            huntingGrounds.startHunting(_tokenId);

            // Finalize
            tokenIdToInfo[_tokenId].location = Location.HUNTING_GROUNDS;
        }

        emit ToadLocationChanged(_tokenIds, msg.sender, Location.HUNTING_GROUNDS);
    }

    function transferToadzToWorld(
        uint256[] calldata _tokenIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_tokenIds)
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];

            _requireValidToadAndLocation(_tokenId, Location.WORLD);

            // From
            _transferFromLocation(_tokenId);

            // To
            // Nothing needed for world

            // Finalize
            tokenIdToInfo[_tokenId].location = Location.WORLD;
        }

        emit ToadLocationChanged(_tokenIds, msg.sender, Location.WORLD);
    }

    function transferToadzOutOfWorld(
        uint256[] calldata _tokenIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_tokenIds)
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];

            _requireValidToadAndLocation(_tokenId, Location.NOT_STAKED);

            // From
            _transferFromLocation(_tokenId);

            // To
            // Unstake the toad.

            ownerToStakedTokens[msg.sender].remove(_tokenId);
            delete tokenIdToInfo[_tokenId];
            toadz.adminSafeTransferFrom(address(this), msg.sender, _tokenId);

            // Finalize
            tokenIdToInfo[_tokenId].location = Location.NOT_STAKED;
        }

        emit ToadLocationChanged(_tokenIds, msg.sender, Location.NOT_STAKED);
    }

    function transferToadzToAdventure(
        uint256[] calldata _tokenIds,
        string calldata _adventureName,
        uint256[][] calldata _itemInputIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_tokenIds)
    {
        require(_tokenIds.length == _itemInputIds.length, "World: Bad adventure array lengths");

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];

            _requireValidToadAndLocation(_tokenId, Location.ADVENTURE);

            // From
            _transferFromLocation(_tokenId);

            // To
            adventure.startAdventure(msg.sender, _tokenId, _adventureName, _itemInputIds[i]);

            // Finalize
            tokenIdToInfo[_tokenId].location = Location.ADVENTURE;
        }

        emit ToadLocationChanged(_tokenIds, msg.sender, Location.ADVENTURE);
    }

    function _transferFromLocation(uint256 _tokenId) private {
        Location _oldLocation = tokenIdToInfo[_tokenId].location;

        if(_oldLocation == Location.WORLD) {
            // Nothing to do here.
        } else if(_oldLocation == Location.HUNTING_GROUNDS) {

            huntingGrounds.stopHunting(_tokenId, msg.sender);
        } else if(_oldLocation == Location.ADVENTURE) {

            adventure.finishAdventure(msg.sender, _tokenId);
        } else if(_oldLocation == Location.NOT_STAKED) {

            tokenIdToInfo[_tokenId].owner = msg.sender;

            ownerToStakedTokens[msg.sender].add(_tokenId);

            // Will revert if user doesn't own token.
            toadz.adminSafeTransferFrom(msg.sender, address(this), _tokenId);
        } else {
            revert("World: Unknown from location");
        }
    }

    function _requireValidToadAndLocation(uint256 _tokenId, Location _newLocation) private view {
        Location _oldLocation = tokenIdToInfo[_tokenId].location;

        // If the location is NOT_STAKED, the toad is not in the world yet, so checking the owner wouldn't make sense.
        //
        if(_oldLocation != Location.NOT_STAKED) {
            require(ownerToStakedTokens[msg.sender].contains(_tokenId), "World: User does not own toad");
        }

        require(_oldLocation != _newLocation, "World: Location must be different for toad");
    }

    function toadzStakedForOwner(address _owner) external view returns(uint256[] memory) {
        return ownerToStakedTokens[_owner].values();
    }

    function ownerForStakedToad(uint256 _tokenId) public view override returns(address) {
        address _owner = tokenIdToInfo[_tokenId].owner;
        require(_owner != address(0), "World: Toad is not staked");
        return _owner;
    }

    function locationForStakedToad(uint256 _tokenId) public view override returns(Location) {
        return tokenIdToInfo[_tokenId].location;
    }

    function isToadStaked(uint256 _tokenId) public view returns(bool) {
        return tokenIdToInfo[_tokenId].owner != address(0);
    }

    function infoForToad(uint256 _tokenId) external view returns(TokenInfo memory) {
        require(isToadStaked(_tokenId), "World: Toad is not staked");
        return tokenIdToInfo[_tokenId];
    }
}
