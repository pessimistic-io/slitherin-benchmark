//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Initializable.sol";

import "./CraftingSettings.sol";

contract Crafting is Initializable, CraftingSettings {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        CraftingSettings.__CraftingSettings_init();
    }

    // Called by World. Returns if the crafting immediately finished for the toad.
    function startCraftingForToad(
        StartCraftingParams calldata _startCraftingParams,
        address _owner)
    external
    whenNotPaused
    contractsAreSet
    worldIsCaller
    returns(bool)
    {
        return _startAndOptionallyFinishCrafting(_startCraftingParams, _owner, true);
    }

    function endCraftingForToad(
        uint256 _toadId,
        address _owner)
    external
    whenNotPaused
    contractsAreSet
    worldIsCaller
    {
        uint256 _craftingId = toadIdToCraftingId[_toadId];
        require(_craftingId > 0, "Toad is not crafting");

        _endCrafting(_craftingId, _owner, true);
    }

    function startOrEndCraftingNoToad(
        uint256[] calldata _craftingIdsToEnd,
        StartCraftingParams[] calldata _startCraftingParams)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(_craftingIdsToEnd.length > 0 || _startCraftingParams.length > 0, "No inputs provided");

        for(uint256 i = 0; i < _craftingIdsToEnd.length; i++) {
            _endCrafting(_craftingIdsToEnd[i], msg.sender, false);
        }

        for(uint256 i = 0; i < _startCraftingParams.length; i++) {
            _startAndOptionallyFinishCrafting(_startCraftingParams[i], msg.sender, false);
        }
    }

    // Returns if the crafting was immediately finished.
    function _startAndOptionallyFinishCrafting(
        StartCraftingParams calldata _craftingParams,
        address _owner,
        bool _shouldHaveToad)
    private
    returns(bool)
    {
        (uint256 _craftingId, bool _isRecipeInstant) = _startCrafting(_craftingParams, _owner, _shouldHaveToad);
        if(_isRecipeInstant) {
            // No random is required if _isRecipeInstant == true.
            // Safe to pass in 0.
            _endCraftingPostValidation(_craftingId, 0, _owner);
        }
        return _isRecipeInstant;
    }

    // Verifies recipe info, inputs, and transfers those inputs.
    // Returns if this recipe can be completed instantly
    function _startCrafting(
        StartCraftingParams calldata _craftingParams,
        address _owner,
        bool _shouldHaveToad)
    private
    returns(uint256, bool)
    {
        require(_isValidRecipeId(_craftingParams.recipeId), "Unknown recipe");

        CraftingRecipe storage _craftingRecipe = recipeIdToRecipe[_craftingParams.recipeId];
        require(block.timestamp >= _craftingRecipe.recipeStartTime &&
            (_craftingRecipe.recipeStopTime == 0
            || _craftingRecipe.recipeStopTime > block.timestamp), "Recipe has not started or stopped");
        require(!_craftingRecipe.requiresToad || _craftingParams.toadId > 0, "Recipe requires Toad");

        CraftingRecipeInfo storage _craftingRecipeInfo = recipeIdToInfo[_craftingParams.recipeId];
        require(_craftingRecipe.maxCraftsGlobally == 0
            || _craftingRecipe.maxCraftsGlobally > _craftingRecipeInfo.currentCraftsGlobally,
            "Recipe has reached max number of crafts");

        _craftingRecipeInfo.currentCraftsGlobally++;

        uint256 _craftingId = craftingIdCur;
        craftingIdCur++;

        uint64 _totalTimeReduction;
        uint256 _totalBugzReduction;
        (_totalTimeReduction,
            _totalBugzReduction) = _validateAndTransferInputs(
                _craftingRecipe,
                _craftingParams,
                _craftingId,
                _owner
            );

        _burnBugz(_craftingRecipe, _owner, _totalBugzReduction);

        _validateAndStoreToad(_craftingRecipe, _craftingParams.toadId, _craftingId, _shouldHaveToad);

        UserCraftingInfo storage _userCrafting = craftingIdToUserCraftingInfo[_craftingId];

        if(_craftingRecipe.timeToComplete > _totalTimeReduction) {
            _userCrafting.timeOfCompletion
                = uint128(block.timestamp + _craftingRecipe.timeToComplete - _totalTimeReduction);
        }

        if(_craftingRecipeInfo.isRandomRequired) {
            _userCrafting.requestId = uint64(randomizer.requestRandomNumber());
        }

        _userCrafting.recipeId = _craftingParams.recipeId;
        _userCrafting.toadId = _craftingParams.toadId;

        // Indicates if this recipe will complete in the same txn as the startCrafting txn.
        bool _isRecipeInstant = !_craftingRecipeInfo.isRandomRequired && _userCrafting.timeOfCompletion == 0;

        if(!_isRecipeInstant) {
            userToCraftsInProgress[_owner].add(_craftingId);
        }

        _emitCraftingStartedEvent(_craftingId, _owner, _craftingParams);

        return (_craftingId, _isRecipeInstant);
    }

    function _emitCraftingStartedEvent(uint256 _craftingId, address _owner, StartCraftingParams calldata _craftingParams) private {
        emit CraftingStarted(
            _owner,
            _craftingId,
            craftingIdToUserCraftingInfo[_craftingId].timeOfCompletion,
            craftingIdToUserCraftingInfo[_craftingId].recipeId,
            craftingIdToUserCraftingInfo[_craftingId].requestId,
            craftingIdToUserCraftingInfo[_craftingId].toadId,
            _craftingParams.inputs);
    }

    function _validateAndStoreToad(
        CraftingRecipe storage _craftingRecipe,
        uint256 _toadId,
        uint256 _craftingId,
        bool _shouldHaveToad)
    private
    {
        require(_craftingRecipe.requiresToad == _shouldHaveToad, "Bad method to start recipe");
        if(_craftingRecipe.requiresToad) {
            require(_toadId > 0, "No toad supplied");
            toadIdToCraftingId[_toadId] = _craftingId;
        } else {
            require(_toadId == 0, "No toad should be supplied");
        }
    }

    function _burnBugz(
        CraftingRecipe storage _craftingRecipe,
        address _owner,
        uint256 _totalBugzReduction)
    private
    {
        uint256 _totalBugz;
        if(_craftingRecipe.bugzCost > _totalBugzReduction) {
            _totalBugz = _craftingRecipe.bugzCost - _totalBugzReduction;
        }

        if(_totalBugz > 0) {
            bugz.burn(_owner, _totalBugz);
        }
    }

    // Ensures all inputs are valid and provided if required.
    function _validateAndTransferInputs(
        CraftingRecipe storage _craftingRecipe,
        StartCraftingParams calldata _craftingParams,
        uint256 _craftingId,
        address _owner)
    private
    returns(uint64 _totalTimeReduction, uint256 _totalBugzReduction)
    {
        // Because the inputs can have a given "amount" of inputs that must be supplied,
        // the input index provided, and those in the recipe may not be identical.
        uint8 _paramInputIndex;

        for(uint256 i = 0; i < _craftingRecipe.inputs.length; i++) {
            RecipeInput storage _recipeInput = _craftingRecipe.inputs[i];

            for(uint256 j = 0; j < _recipeInput.amount; j++) {
                require(_paramInputIndex < _craftingParams.inputs.length, "Bad number of inputs");
                ItemInfo calldata _startCraftingItemInfo = _craftingParams.inputs[_paramInputIndex];
                _paramInputIndex++;
                // J must equal 0. If they are trying to skip an optional amount, it MUST be the first input supplied for the RecipeInput
                if(j == 0 && _startCraftingItemInfo.itemId == 0 && !_recipeInput.isRequired) {
                    // Break out of the amount loop. They are not providing any of the input
                    break;
                } else if(_startCraftingItemInfo.itemId == 0) {
                    revert("Supplied no input to required input");
                } else {
                    uint256 _optionIndex = recipeIdToInputIndexToItemIdToOptionIndex[_craftingParams.recipeId][i][_startCraftingItemInfo.itemId];
                    RecipeInputOption storage _inputOption = _recipeInput.inputOptions[_optionIndex];

                    require(_inputOption.itemInfo.amount > 0
                        && _inputOption.itemInfo.amount == _startCraftingItemInfo.amount
                        && _inputOption.itemInfo.itemId == _startCraftingItemInfo.itemId, "Bad item input given");

                    // Add to reductions
                    _totalTimeReduction += _inputOption.timeReduction;
                    _totalBugzReduction += _inputOption.bugzReduction;

                    craftingIdToUserCraftingInfo[_craftingId]
                        .itemIdToInput[_inputOption.itemInfo.itemId].itemAmount += _inputOption.itemInfo.amount;
                    craftingIdToUserCraftingInfo[_craftingId]
                        .itemIdToInput[_inputOption.itemInfo.itemId].wasBurned = _inputOption.isBurned;

                    // Only need to save off non-burned inputs. These will be reminted when the recipe is done. Saves
                    // gas over transferring to this contract.
                    if(!_inputOption.isBurned) {
                        craftingIdToUserCraftingInfo[_craftingId].nonBurnedInputs.push(_inputOption.itemInfo);
                    }

                    _mintOrBurnItem(
                        _inputOption.itemInfo,
                        _owner,
                        true);
                }
            }
        }
    }

    function _endCrafting(uint256 _craftingId, address _owner, bool _shouldHaveToad) private {
        require(userToCraftsInProgress[_owner].contains(_craftingId), "Invalid crafting id for user");

        // Remove crafting from users in progress crafts.
        userToCraftsInProgress[_owner].remove(_craftingId);

        UserCraftingInfo storage _userCraftingInfo = craftingIdToUserCraftingInfo[_craftingId];
        require(block.timestamp >= _userCraftingInfo.timeOfCompletion, "Crafting is not complete");

        require(_shouldHaveToad == (_userCraftingInfo.toadId > 0), "Bad method to end crafting");

        uint256 _randomNumber;
        if(_userCraftingInfo.requestId > 0) {
            _randomNumber = randomizer.revealRandomNumber(_userCraftingInfo.requestId);
        }

        _endCraftingPostValidation(_craftingId, _randomNumber, _owner);
    }

    function _endCraftingPostValidation(uint256 _craftingId, uint256 _randomNumber, address _owner) private {
        UserCraftingInfo storage _userCraftingInfo = craftingIdToUserCraftingInfo[_craftingId];
        CraftingRecipe storage _craftingRecipe = recipeIdToRecipe[_userCraftingInfo.recipeId];

        uint256 _bugzRewarded;

        CraftingItemOutcome[] memory _itemOutcomes = new CraftingItemOutcome[](_craftingRecipe.outputs.length);

        for(uint256 i = 0; i < _craftingRecipe.outputs.length; i++) {
            // If needed, get a fresh random for the next output decision.
            if(i != 0 && _randomNumber != 0) {
                _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
            }

            (uint256 _bugzForOutput, CraftingItemOutcome memory _outcome) = _determineAndMintOutputs(
                _craftingRecipe.outputs[i],
                _userCraftingInfo,
                _owner,
                _randomNumber);

            _bugzRewarded += _bugzForOutput;
            _itemOutcomes[i] = _outcome;
        }

        for(uint256 i = 0; i < _userCraftingInfo.nonBurnedInputs.length; i++) {
            ItemInfo storage _userCraftingInput = _userCraftingInfo.nonBurnedInputs[i];

            _mintOrBurnItem(
                _userCraftingInput,
                _owner,
                false);
        }

        if(_userCraftingInfo.toadId > 0) {
            delete toadIdToCraftingId[_userCraftingInfo.toadId];
        }

        emit CraftingEnded(_craftingId, _bugzRewarded, _itemOutcomes);
    }

    function _determineAndMintOutputs(
        RecipeOutput storage _recipeOutput,
        UserCraftingInfo storage _userCraftingInfo,
        address _owner,
        uint256 _randomNumber)
    private
    returns(uint256 _bugzForOutput, CraftingItemOutcome memory _outcome)
    {
        uint8 _outputAmount = _determineOutputAmount(
            _recipeOutput,
            _userCraftingInfo,
            _randomNumber);

        // Just in case the output amount needed a random. Only would need 16 bits (one random roll).
        _randomNumber >>= 16;

        uint64[] memory _itemIds = new uint64[](_outputAmount);
        uint64[] memory _itemAmounts = new uint64[](_outputAmount);

        for(uint256 i = 0; i < _outputAmount; i++) {
            if(i != 0 && _randomNumber != 0) {
                _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
            }

            RecipeOutputOption memory _selectedOption = _determineOutputOption(
                _recipeOutput,
                _userCraftingInfo,
                _randomNumber);
            _randomNumber >>= 16;

            uint64 _itemAmount;
            if(_selectedOption.itemAmountMin == _selectedOption.itemAmountMax) {
                _itemAmount = _selectedOption.itemAmountMax;
            } else {
                uint64 _rangeSelection = uint64(_randomNumber
                    % (_selectedOption.itemAmountMax - _selectedOption.itemAmountMin + 1));

                _itemAmount = _selectedOption.itemAmountMin + _rangeSelection;
            }

            _bugzForOutput += _selectedOption.bugzAmount;
            _itemIds[i] = _selectedOption.itemId;
            _itemAmounts[i] = _itemAmount;

            _mintOutputOption(_selectedOption, _itemAmount, _owner);
        }

        _outcome.itemIds = _itemIds;
        _outcome.itemAmounts = _itemAmounts;
    }

    function _determineOutputOption(
        RecipeOutput storage _recipeOutput,
        UserCraftingInfo storage _userCraftingInfo,
        uint256 _randomNumber)
    private
    view
    returns(RecipeOutputOption memory)
    {
        RecipeOutputOption memory _selectedOption;
        if(_recipeOutput.outputOptions.length == 1) {
            _selectedOption = _recipeOutput.outputOptions[0];
        } else {
            uint256 _outputOptionResult = _randomNumber % 100000;
            uint32 _topRange = 0;
            for(uint256 j = 0; j < _recipeOutput.outputOptions.length; j++) {
                RecipeOutputOption storage _outputOption = _recipeOutput.outputOptions[j];
                uint32 _adjustedOdds = _adjustOutputOdds(_outputOption.optionOdds, _userCraftingInfo);
                _topRange += _adjustedOdds;
                if(_outputOptionResult < _topRange) {
                    _selectedOption = _outputOption;
                    break;
                }
            }
        }

        return _selectedOption;
    }

    // Determines how many "rolls" the user has for the passed in output.
    function _determineOutputAmount(
        RecipeOutput storage _recipeOutput,
        UserCraftingInfo storage _userCraftingInfo,
        uint256 _randomNumber
    ) private view returns(uint8) {
        uint8 _outputAmount;
        if(_recipeOutput.outputAmount.length == 1) {
            _outputAmount = _recipeOutput.outputAmount[0];
        } else {
            uint256 _outputResult = _randomNumber % 100000;
            uint32 _topRange = 0;

            for(uint256 i = 0; i < _recipeOutput.outputAmount.length; i++) {
                uint32 _adjustedOdds = _adjustOutputOdds(_recipeOutput.outputOdds[i], _userCraftingInfo);
                _topRange += _adjustedOdds;
                if(_outputResult < _topRange) {
                    _outputAmount = _recipeOutput.outputAmount[i];
                    break;
                }
            }
        }
        return _outputAmount;
    }

    function _mintOutputOption(
        RecipeOutputOption memory _selectedOption,
        uint256 _itemAmount,
        address _owner)
    private
    {
        if(_itemAmount > 0 && _selectedOption.itemId > 0) {
            itemz.mint(
                _owner,
                _selectedOption.itemId,
                _itemAmount);
        }
        if(_selectedOption.bugzAmount > 0) {
            bugz.mint(
                _owner,
                _selectedOption.bugzAmount);
        }
        if(_selectedOption.badgeId > 0) {
            badgez.mintIfNeeded(
                _owner,
                _selectedOption.badgeId);
        }
    }

    function _adjustOutputOdds(
        OutputOdds storage _outputOdds,
        UserCraftingInfo storage _userCraftingInfo)
    private
    view
    returns(uint32)
    {
        if(_outputOdds.boostItemIds.length == 0) {
            return _outputOdds.baseOdds;
        }

        int32 _trueOdds = int32(_outputOdds.baseOdds);

        for(uint256 i = 0; i < _outputOdds.boostItemIds.length; i++) {
            uint64 _itemId = _outputOdds.boostItemIds[i];
            if(_userCraftingInfo.itemIdToInput[_itemId].itemAmount == 0) {
                continue;
            }

            _trueOdds += _outputOdds.boostOddChanges[i];
        }

        if(_trueOdds > 100000) {
            return 100000;
        } else if(_trueOdds < 0) {
            return 0;
        } else {
            return uint32(_trueOdds);
        }
    }

    function _mintOrBurnItem(
        ItemInfo memory _itemInfo,
        address _owner,
        bool _burn)
    private
    {
        if(_burn) {
            itemz.burn(_owner, _itemInfo.itemId, _itemInfo.amount);
        } else {
            itemz.mint(_owner, _itemInfo.itemId, _itemInfo.amount);
        }
    }
}
