//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadHousezMinterContracts.sol";

contract ToadHousezMinter is Initializable, ToadHousezMinterContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        ToadHousezMinterContracts.__ToadHousezMinterContracts_init();
    }

    function setHouseBuildingDuration(uint256 _houseBuildingDuration) external onlyAdminOrOwner {
        houseBuildingDuration = _houseBuildingDuration;
        emit HouseBuildingDuration(houseBuildingDuration);
    }

    function setHouseBlueprintBugzCost(uint256 _houseBlueprintBugzCost) external onlyAdminOrOwner {
        houseBlueprintBugzCost = _houseBlueprintBugzCost;
        emit HouseBlueprintBugzCost(_houseBlueprintBugzCost);
    }

    function setHouseBuildingBugzCost(uint256 _houseBuildingBugzCost) external onlyAdminOrOwner {
        houseBuildingBugzCost = _houseBuildingBugzCost;
        emit HouseBuildingBugzCost(_houseBuildingBugzCost);
    }

    function setIsBlueprintBuyingEnabled(bool _isBlueprintBuyingEnabled) external onlyAdminOrOwner {
        isBlueprintBuyingEnabled = _isBlueprintBuyingEnabled;
        emit BlueprintBuyingEnabledChanged(isBlueprintBuyingEnabled);
    }

    function setIsHouseBuildingEnabled(bool _isHouseBuildingEnabled) external onlyAdminOrOwner {
        isHouseBuildingEnabled = _isHouseBuildingEnabled;
        emit HouseBuildingEnabledChanged(isHouseBuildingEnabled);
    }

    function setTraitRaritiesAndAliases(string calldata _trait, uint8[] calldata _rarities, uint8[] calldata _aliases) external onlyAdminOrOwner {
        traitTypeToRarities[_trait] = _rarities;
        traitTypeToAliases[_trait] = _aliases;
    }

    function rarities(string calldata _traitType) external view returns(uint8[] memory) {
        return traitTypeToRarities[_traitType];
    }

    function aliases(string calldata _traitType) external view returns(uint8[] memory) {
        return traitTypeToAliases[_traitType];
    }

    function buyBlueprints(
        uint256[] calldata _toadIds)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(_toadIds.length > 0, "ToadHousezMinter: Invalid array length");
        require(wartlocksHallow.isCroakshirePowered(), "ToadHousezMinter: Croakshire is not powered");
        require(isBlueprintBuyingEnabled, "ToadHousezMinter: Blueprint buying not enabled");

        for(uint256 i = 0; i < _toadIds.length; i++) {
            uint256 _toadId = _toadIds[i];

            require(toadz.ownerOf(_toadId) == msg.sender || world.ownerForStakedToad(_toadId) == msg.sender,
                "ToadHousezMinter: Must own toad to buy the blueprints");

            // Update to bought. Will revert if already purchased
            toadzMetadata.setHasPurchasedBlueprint(_toadId);
        }

        itemz.mint(msg.sender, houseBlueprintId, _toadIds.length);

        uint256 _totalBugzCost = houseBlueprintBugzCost * _toadIds.length;
        if(_totalBugzCost > 0) {
            bugz.burn(msg.sender, _totalBugzCost);
        }
    }

    function startBuildingHouses(
        BuildHouseParams[] calldata _buildHouseParams)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(_buildHouseParams.length > 0, "ToadHousezMinter: Invalid array length");
        require(wartlocksHallow.isCroakshirePowered(), "ToadHousezMinter: Croakshire is not powered");
        require(isHouseBuildingEnabled, "ToadHousezMinter: House building not enabled");

        uint256 _requestId = randomizer.requestRandomNumber();
        addressToRequestIds[msg.sender].add(_requestId);

        requestIdToHouses[_requestId].startTime = block.timestamp;

        uint256[] memory _woodAmountsToBurn = new uint256[](8);

        for(uint256 i = 0; i < _buildHouseParams.length; i++) {
            BuildHouseParams calldata _buildHouseParam = _buildHouseParams[i];

            // Track what wood to burn
            for(uint256 j = 0; j < _buildHouseParam.woods.length; j++) {
                _woodAmountsToBurn[uint256(_buildHouseParam.woods[j])] += 1;
            }

            requestIdToHouses[_requestId].houseParams.push(_buildHouseParam);
        }

        for(uint256 i = 0; i < _woodAmountsToBurn.length; i++) {
            uint256 _amount = _woodAmountsToBurn[i];
            if(_amount == 0) {
                continue;
            }
            uint256 _woodId = woodTypeToItemId[WoodType(i)];
            itemz.burn(msg.sender, _woodId, _amount);
        }

        // Burn the correct number of blueprints
        itemz.burn(msg.sender, houseBlueprintId, _buildHouseParams.length);

        uint256 _totalBugzCost = houseBuildingBugzCost * _buildHouseParams.length;
        if(_totalBugzCost > 0) {
            bugz.burn(msg.sender, _totalBugzCost);
        }

        emit HouseBuildingBatchStarted(msg.sender, _requestId, _buildHouseParams.length, block.timestamp + houseBuildingDuration);
    }

    function finishBuildingHouses()
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        uint256[] memory _requestIds = addressToRequestIds[msg.sender].values();

        uint256 _requestIdsProcessed;

        for(uint256 i = 0; i < _requestIds.length; i++) {
            uint256 _requestId = _requestIds[i];

            if(!randomizer.isRandomReady(_requestId)) {
                continue;
            }

            RequestIdInfo storage _requestIdInfo = requestIdToHouses[_requestId];
            if(block.timestamp < _requestIdInfo.startTime + houseBuildingDuration) {
                continue;
            }

            _requestIdsProcessed++;
            addressToRequestIds[msg.sender].remove(_requestId);

            uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

            for(uint256 j = 0; j < _requestIdInfo.houseParams.length; j++) {
                if(j != 0) {
                    _randomNumber = uint256(keccak256(abi.encode(_randomNumber, j)));
                }

                ToadHouseTraits memory _traits = _pickTraits(
                    _requestIdInfo.houseParams[j],
                    _randomNumber
                );

                toadHousez.mint(
                    msg.sender,
                    _traits
                );
            }

            emit HouseBuildingBatchFinished(msg.sender, _requestId);
        }


        require(_requestIdsProcessed > 0, "ToadHousezMinter: Nothing to finish");
    }

    function _pickTraits(
        BuildHouseParams storage _buildHouseParams,
        uint256 _randomNumber)
    private
    view
    returns(ToadHouseTraits memory _toadHouseTraits)
    {
        _toadHouseTraits.rarity = HouseRarity.COMMON;

        // In total, have 12 fields to pick (the last wood position does not require a random).
        // Each takes 16 bits of the 256 bit random number. No worry about using too many bits.
        //
        _toadHouseTraits.variation = HouseVariation(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[VARIATION],
            traitTypeToAliases[VARIATION]));
        _randomNumber >>= 16;

        _toadHouseTraits.background = HouseBackground(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[BACKGROUND],
            traitTypeToAliases[BACKGROUND]));
        _randomNumber >>= 16;

        _toadHouseTraits.smoke = HouseSmoke(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[SMOKE],
            traitTypeToAliases[SMOKE]));
        _randomNumber >>= 16;

        // Used 4 16 bit slots of the random.
        //
        WoodType[5] memory _woodTypeOrder = _randomizeWoodPositions(_buildHouseParams, _randomNumber);
        _randomNumber >>= 64;

        _toadHouseTraits.main = _woodTypeOrder[0];
        _toadHouseTraits.left = _woodTypeOrder[1];
        _toadHouseTraits.right = _woodTypeOrder[2];
        _toadHouseTraits.door = _woodTypeOrder[3];
        _toadHouseTraits.mushroom = _woodTypeOrder[4];
    }

    function _pickTrait(
        uint16 _randomNumber,
        uint8[] storage _rarities,
        uint8[] storage _aliases)
    private
    view
    returns(uint8)
    {
        uint8 _trait = uint8(_randomNumber) % uint8(_rarities.length);

        // If a selected random trait probability is selected, return that trait
        if(_randomNumber >> 8 < _rarities[_trait]) {
            return _trait;
        } else {
            return _aliases[_trait];
        }
    }

    function _randomizeWoodPositions(
        BuildHouseParams memory _buildHouseParams,
        uint256 _randomNumber)
    private
    pure
    returns(WoodType[5] memory _randomizedArray)
    {
        uint8 _elementsRemaining = 5;
        uint256 _returnValueArrayIndex = 0;

        while(_elementsRemaining > 0) {
            uint256 _chosenIndex;
            if(_elementsRemaining == 1) {
                _chosenIndex = 0;
            } else {
                _chosenIndex = _randomNumber % _elementsRemaining;
                _randomNumber >> 16;
            }

            _randomizedArray[_returnValueArrayIndex] = _buildHouseParams.woods[_chosenIndex];
            _returnValueArrayIndex++;
            _elementsRemaining--;

            // Swap the chosen element position with the last element.
            //
            _buildHouseParams.woods[_chosenIndex] = _buildHouseParams.woods[_elementsRemaining];
        }
    }
}
