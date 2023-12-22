//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Initializable.sol";

import "./CraftingContracts.sol";

abstract contract CraftingSettings is Initializable, CraftingContracts {

    function __CraftingSettings_init() internal initializer {
        CraftingContracts.__CraftingContracts_init();
    }

    function addCraftingRecipe(
        CraftingRecipe calldata _craftingRecipe)
    external
    onlyAdminOrOwner
    {
        require(_craftingRecipe.recipeStartTime > 0 &&
            (_craftingRecipe.recipeStopTime == 0  || _craftingRecipe.recipeStopTime > _craftingRecipe.recipeStartTime)
            && recipeNameToRecipeId[_craftingRecipe.recipeName] == 0,
            "Bad crafting recipe");

        uint64 _recipeId = recipeIdCur;
        recipeIdCur++;

        recipeNameToRecipeId[_craftingRecipe.recipeName] = _recipeId;

        // Input validation.
        for(uint256 i = 0; i < _craftingRecipe.inputs.length; i++) {
            RecipeInput calldata _input = _craftingRecipe.inputs[i];

            require(_input.inputOptions.length > 0, "Input must have options");

            for(uint256 j = 0; j < _input.inputOptions.length; j++) {
                RecipeInputOption calldata _inputOption = _input.inputOptions[j];

                require(_inputOption.itemInfo.amount > 0, "Bad amount");

                recipeIdToInputIndexToItemIdToOptionIndex[_recipeId][i][_inputOption.itemInfo.itemId] = j;
            }
        }

        // Output validation.
        require(_craftingRecipe.outputs.length > 0, "Recipe requires outputs");

        bool _isRandomRequiredForRecipe;
        for(uint256 i = 0; i < _craftingRecipe.outputs.length; i++) {
            RecipeOutput calldata _output = _craftingRecipe.outputs[i];

            require(_output.outputAmount.length > 0
                && _output.outputAmount.length == _output.outputOdds.length
                && _output.outputOptions.length > 0,
                "Bad output info");

            // If there is a variable amount for this RecipeOutput or multiple options,
            // a random is required.
            _isRandomRequiredForRecipe = _isRandomRequiredForRecipe
                || _output.outputAmount.length > 1
                || _output.outputOptions.length > 1;

            for(uint256 j = 0; j < _output.outputOptions.length; j++) {
                RecipeOutputOption calldata _outputOption = _output.outputOptions[j];

                // If there is an amount range, a random is required.
                _isRandomRequiredForRecipe = _isRandomRequiredForRecipe
                    || _outputOption.itemAmountMin != _outputOption.itemAmountMax;
            }
        }

        recipeIdToRecipe[_recipeId] = _craftingRecipe;
        recipeIdToInfo[_recipeId].isRandomRequired = _isRandomRequiredForRecipe;

        emit RecipeAdded(_recipeId, _craftingRecipe);
    }

    function addToCurrentCraftsGlobal(
        uint64 _recipeId,
        uint64 _craftsToAdd)
    external
    onlyAdminOrOwner
    {
        require(_isValidRecipeId(_recipeId), "Unknown recipe Id");
        recipeIdToInfo[_recipeId].currentCraftsGlobally += _craftsToAdd;

        emit RecipeCraftsGlobalUpdated(_recipeId, recipeIdToInfo[_recipeId].currentCraftsGlobally);
    }

    function deleteRecipe(
        uint64 _recipeId)
    external
    onlyAdminOrOwner
    {
        require(_isValidRecipeId(_recipeId), "Unknown recipe Id");
        recipeIdToRecipe[_recipeId].recipeStopTime = recipeIdToRecipe[_recipeId].recipeStartTime;

        emit RecipeDeleted(_recipeId);
    }

    function _isValidRecipeId(uint64 _recipeId) internal view returns(bool) {
        return recipeIdToRecipe[_recipeId].recipeStartTime > 0;
    }

    function recipeIdForName(string calldata _recipeName) external view returns(uint64) {
        return recipeNameToRecipeId[_recipeName];
    }
}
