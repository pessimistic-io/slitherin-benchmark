//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./StarlightTempleContracts.sol";

contract StarlightTemple is Initializable, StarlightTempleContracts {

    function initialize() external initializer {
        StarlightTempleContracts.__StarlightTempleContracts_init();
    }

    function setTempleSettings(
        uint8 _maxConstellationRank,
        uint256 _starlightConsumableId,
        uint256[] calldata _currentRankToNeededStarlight,
        uint256[] calldata _currentRankToPrismAmount,
        uint256[] calldata _currentRankToPrismIds)
    external onlyAdminOrOwner
    {
        require(_currentRankToNeededStarlight.length == _maxConstellationRank
            && _maxConstellationRank == _currentRankToPrismAmount.length
            && _maxConstellationRank == _currentRankToPrismIds.length, "Starlight length must match max");
        maxConstellationRank = _maxConstellationRank;
        starlightConsumableId = _starlightConsumableId;
        delete currentRankToNeededStarlight;
        delete currentRankToPrismAmount;
        delete currentRankToPrismId;
        for(uint256 i = 0; i < _currentRankToNeededStarlight.length; i++) {
            currentRankToNeededStarlight.push(_currentRankToNeededStarlight[i]);
            currentRankToPrismAmount.push(_currentRankToPrismAmount[i]);
            currentRankToPrismId.push(_currentRankToPrismIds[i]);
        }
    }

    function setIsIncreasingRankPaused(bool _isIncreasingRankPaused) external onlyAdminOrOwner {
        isIncreasingRankPaused = _isIncreasingRankPaused;
    }

    function increaseRankOfConstellations(
        uint256[] calldata _tokenIds,
        Constellation[] calldata _constellations)
    external
    onlyEOA
    whenNotPaused
    nonZeroLength(_tokenIds)
    {
        require(_tokenIds.length == _constellations.length, "StarlightTemple: Bad array lengths");

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            _increaseRankOfConstellation(_tokenIds[i], _constellations[i]);
        }
    }

    function _increaseRankOfConstellation(
        uint256 _tokenId,
        Constellation _constellation)
    private
    {
        require(starlightConsumableId > 0, "StarlightTemple: Bad starlight ID");
        require(msg.sender == legion.ownerOf(_tokenId), "StarlightTemple: Must be owner");
        require(!isIncreasingRankPaused, "StarlightTemple: Increasing rank is paused");

        LegionMetadata memory _metadata = legionMetadataStore.metadataForLegion(_tokenId);
        require(_metadata.legionGeneration != LegionGeneration.RECRUIT, "Cannot increase recruit rank");

        uint8 _currentRank = _metadata.constellationRanks[uint8(_constellation)];
        require(_currentRank < maxConstellationRank, "Already max constellation rank.");

        legionMetadataStore.increaseConstellationRank(_tokenId, _constellation, _currentRank + 1);

        uint256 _starlightCost = currentRankToNeededStarlight[_currentRank];
        // Will revert if failed. Send to treasury
        consumable.adminSafeTransferFrom(msg.sender, address(treasury), starlightConsumableId, _starlightCost);

        uint256 _prismAmount = currentRankToPrismAmount[_currentRank];
        uint256 _prismId = currentRankToPrismId[_currentRank];

        if(_prismAmount > 0 && _prismId > 0) {
            consumable.adminSafeTransferFrom(msg.sender, address(treasury), _prismId, _prismAmount);
        }
    }

    function maxRankOfConstellations(
        uint256 _tokenId,
        uint8 _numberOfConstellations)
    external
    onlyAdminOrOwner
    whenNotPaused
    {
        uint8 _maxConstellation = numberOfConstellations();
        require(_numberOfConstellations <= _maxConstellation, "Bad number to max");

        for(uint256 i = 0; i < _numberOfConstellations; i++) {
            legionMetadataStore.increaseConstellationRank(_tokenId, Constellation(i), maxConstellationRank);
        }
    }

    function allConstellations() public pure returns(Constellation[6] memory) {
        return [
            Constellation.FIRE,
            Constellation.EARTH,
            Constellation.WIND,
            Constellation.WATER,
            Constellation.LIGHT,
            Constellation.DARK
        ];
    }

    function numberOfConstellations() public pure returns(uint8) {
        return 6;
    }
}
