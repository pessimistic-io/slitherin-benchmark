//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";

import "./WanderingMerchantContracts.sol";

contract WanderingMerchant is Initializable, WanderingMerchantContracts {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize() external initializer {
        WanderingMerchantContracts.__WanderingMerchantContracts_init();
    }

    function openMerchant(uint128 _openTime, uint128 _closeTime, bool _clearExistingRecipes, Recipe[] calldata _recipes) external onlyAdminOrOwner {
        openTime = _openTime;
        closeTime = _closeTime;

        while(_clearExistingRecipes && activeRecipeIds.length != 0) {
            _removeRecipe(activeRecipeIds[0]);
        }

        addRecipes(_recipes);

        emit WanderingMerchantActiveTimeChanged(_openTime, _closeTime);
    }

    function addRecipes(Recipe[] calldata _recipes) public onlyAdminOrOwner {
        for(uint256 i = 0; i < _recipes.length; i++) {
            _addRecipe(_recipes[i]);
        }
    }

    function removeRecipes(uint64[] calldata _recipeIds) external onlyAdminOrOwner {
        for(uint256 i = 0; i < _recipeIds.length; i++) {
            _removeRecipe(_recipeIds[i]);
        }
    }

    function _addRecipe(Recipe calldata _recipe) private {
        uint64 _recipeId = recipeIdCur;
        recipeIdCur++;

        require(_recipe.currentAvailable <= _recipe.maxAvailable, "Bad available amounts");

        RecipeInfo storage _recipeInfo = recipeIdToInfo[_recipeId];
        _recipeInfo.currentAvailable = _recipe.currentAvailable;
        _recipeInfo.maxAvailable = _recipe.maxAvailable;
        _recipeInfo.inputTokenId = _recipe.inputTokenId;
        _recipeInfo.inputType = _recipe.inputType;
        _recipeInfo.numberOfOutputs = uint32(_recipe.outputs.length);
        _recipeInfo.isActive = true;

        for(uint32 i = 0; i < _recipe.outputs.length; i++) {
            _recipeInfo.outputIndexToOutput[i] = _recipe.outputs[i];
        }

        activeRecipeIds.push(_recipeId);

        emit WanderingMerchantRecipeAdded(_recipeId, _recipe.currentAvailable, _recipe.maxAvailable, _recipe.inputTokenId, _recipe.inputType, _recipe.outputs);
    }

    function _removeRecipe(uint64 _recipeId) private {
        RecipeInfo storage _recipeInfo = recipeIdToInfo[_recipeId];

        require(_recipeInfo.isActive, "Recipe is not active");

        _recipeInfo.isActive = false;

        for(uint256 i = 0; i < activeRecipeIds.length; i++) {
            if(_recipeId == activeRecipeIds[i]) {
                activeRecipeIds[i] = activeRecipeIds[activeRecipeIds.length - 1];
                activeRecipeIds.pop();
                break;
            }
        }

        emit WanderingMerchantRecipeRemoved(_recipeId);
    }

    function fulfillRecipes(FulfillRecipeParams[] calldata _params) external whenNotPaused onlyEOA {
        require(_params.length > 0, "Bad length");
        require(openTime != 0 && closeTime != 0 && openTime <= block.timestamp && block.timestamp < closeTime, "Merchant is not open");

        for(uint256 i = 0; i < _params.length; i++) {
            _fulfillRecipe(_params[i]);
        }
    }

    function _fulfillRecipe(FulfillRecipeParams calldata _params) private {
        RecipeInfo storage _recipeInfo = recipeIdToInfo[_params.recipeId];

        require(_recipeInfo.isActive, "Recipe is not active");
        require(_recipeInfo.currentAvailable > 0, "No more available");

        _recipeInfo.currentAvailable--;

        if(_recipeInfo.inputType == InputType.CONSUMABLE) {
            require(_params.inputTokenId == _recipeInfo.inputTokenId, "Input token id does not match");
            consumable.adminBurn(msg.sender, _params.inputTokenId, 1);
        } else { // Auxiliary Legion
            LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_params.inputTokenId);
            require(_legionMetadata.legionGeneration == LegionGeneration.AUXILIARY, "Aux legions only");

            legion.adminBurn(msg.sender, _params.inputTokenId);
        }

        for(uint32 i = 0; i < _recipeInfo.numberOfOutputs; i++) {
            Output storage _output = _recipeInfo.outputIndexToOutput[i];
            if(_output.outputType == OutputType.CONSUMABLE) {
                consumable.mint(msg.sender, _output.tokenId, _output.amount);
            } else if(_output.outputType == OutputType.TRANSFERRED_ERC20) {
                IERC20Upgradeable(_output.outputAddress).safeTransferFrom(_output.transferredFrom, msg.sender, _output.amount);
            } else {
                revert("Unknown outputType");
            }
        }

        emit WanderingMerchantRecipeFulfilled(_params.recipeId, msg.sender);
    }

    function merchantInfo() external view returns(MerchantInfo memory merchantInfo_) {
        merchantInfo_.openTime = openTime;
        merchantInfo_.closeTime = closeTime;
        merchantInfo_.activeRecipes = new RecipeMerchantInfo[](activeRecipeIds.length);

        for(uint256 i = 0; i < activeRecipeIds.length; i++) {
            uint64 _recipeId = activeRecipeIds[i];
            RecipeInfo storage _recipeInfo = recipeIdToInfo[_recipeId];
            merchantInfo_.activeRecipes[i].recipeId = _recipeId;
            merchantInfo_.activeRecipes[i].currentAvailable = _recipeInfo.currentAvailable;
            merchantInfo_.activeRecipes[i].maxAvailable = _recipeInfo.maxAvailable;
            merchantInfo_.activeRecipes[i].inputTokenId = _recipeInfo.inputTokenId;
            merchantInfo_.activeRecipes[i].inputType = _recipeInfo.inputType;

            merchantInfo_.activeRecipes[i].outputs = new Output[](_recipeInfo.numberOfOutputs);
            for(uint32 j = 0; j < _recipeInfo.numberOfOutputs; j++) {
                Output storage _output = _recipeInfo.outputIndexToOutput[j];
                merchantInfo_.activeRecipes[i].outputs[j].outputType = _output.outputType;
                merchantInfo_.activeRecipes[i].outputs[j].transferredFrom = _output.transferredFrom;
                merchantInfo_.activeRecipes[i].outputs[j].tokenId = _output.tokenId;
                merchantInfo_.activeRecipes[i].outputs[j].amount = _output.amount;
                merchantInfo_.activeRecipes[i].outputs[j].outputAddress = _output.outputAddress;
            }
        }
    }
}

struct MerchantInfo {
    uint128 openTime;
    uint128 closeTime;
    RecipeMerchantInfo[] activeRecipes;
}

struct FulfillRecipeParams {
    uint64 recipeId;
    uint32 inputTokenId;
}

struct Recipe {
    uint32 currentAvailable;
    uint32 maxAvailable;
    uint32 inputTokenId;
    InputType inputType;
    Output[] outputs;
}

struct RecipeMerchantInfo {
    uint64 recipeId;
    uint32 currentAvailable;
    uint32 maxAvailable;
    uint32 inputTokenId;
    InputType inputType;
    Output[] outputs;
}
