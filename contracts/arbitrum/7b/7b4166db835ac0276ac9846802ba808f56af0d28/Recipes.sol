// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces_IERC20.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./Permissioned.sol";
import "./IItems.sol";
import "./IGold.sol";

struct Recipe { 
    uint256 recipeID;         // ID of the Recipe
    string name;              // The name of the recipe
    uint256 itemID;           // ID of the item to craft
    uint256 amount;           // Amount of the item to craft
    uint256 price;            // Price of the recipe, disregarded if payment address is empty
    address paymentAddress;   // Zero address is a free recipe
    bool active;              // Status (Active/Inactive)
    uint256[] recipeItems;    // A list of items for the recipe
    uint256[] recipeAmounts;  // A list of amounts for the recipe
    }

/// @dev Farmland - Recipes Smart Contract
contract Recipes is ReentrancyGuard, Pausable, Permissioned {
    using SafeERC20 for IERC20;

// CONSTRUCTOR

    constructor () Permissioned() {}

// STATE VARIABLES

    /// @dev Create a mapping to track each recipe
    mapping(uint256 => Recipe) internal recipes;

    /// @dev Create a mapping between recipeID & recipeSignature (defined as the hash of the recipe items / amounts)
    mapping(bytes32 => uint256) internal getRecipeIDFromSignature;

    /// @dev Tracks the Recipe ID
    uint256 public totalRecipes;


// MODIFIERS

    /// @dev Checks whether a minting has started
    /// @param recipeID identifies the recipe
    modifier onlyWhenActive(uint256 recipeID) {
        require(recipes[recipeID].active, "Recipe Inactive");
        _;
    }

    /// @dev Checks whether a recipe exists
    /// @param recipeID identifies the recipe
    modifier onlyIfRecipeExists(uint256 recipeID) {
        require(recipes[recipeID].recipeID > 0,"Recipe does not exist");
        _;
    }

// ADMIN FUNCTIONS

    /// @dev Create a recipe
    /// @param recipe the recipe
    function addRecipe(Recipe calldata recipe)
        external
        onlyOwner
    {
        // Ensure recipe items & amounts are unique
        require(getRecipeIDFromSignature[getRecipeSignature(recipe.recipeItems, recipe.recipeAmounts)] == 0,"Recipe details already exist");
        // Increment the recipe number
        unchecked { ++totalRecipes; }
        // Store the recipe details in mappings
        recipes[totalRecipes] = recipe;
        getRecipeIDFromSignature[getRecipeSignature(recipe.recipeItems, recipe.recipeAmounts)] = totalRecipes;
    }

    /// @dev The owner can update a recipe
    /// @param recipeID ID of the recipe
    /// @param recipe the recipe
    function updateRecipe(uint256 recipeID, Recipe calldata recipe)
        external 
        onlyOwner
        onlyIfRecipeExists(recipeID)
    {
        // Delete the recipeID to Recipe Signature mappings first
        delete getRecipeIDFromSignature[getRecipeSignature(recipes[recipeID].recipeItems, recipes[recipeID].recipeAmounts)];
        // Ensure the new recipe items & amounts are unique
        require(getRecipeIDFromSignature[getRecipeSignature(recipe.recipeItems, recipe.recipeAmounts)] == 0,"Recipe details already exist");
        // Update the recipe details in mappings
        recipes[recipeID] = recipe;
        getRecipeIDFromSignature[getRecipeSignature(recipe.recipeItems, recipe.recipeAmounts)] = totalRecipes;
    }

    /// @dev The owner can delete an recipe
    /// @param recipeID ID of the recipe
    function deleteRecipe(uint256 recipeID)
        external 
        onlyOwner
        onlyIfRecipeExists(recipeID)
    {
        // Delete the mappings
        delete getRecipeIDFromSignature[getRecipeSignature(recipes[recipeID].recipeItems, recipes[recipeID].recipeAmounts)];
        delete recipes[recipeID];
    }

// VIEWS

    /// @dev Return recipe signature
    function getRecipeSignature(uint256[] memory recipeItems, uint256[] memory recipeAmounts)
        internal
        pure
        returns (bytes32 recipeSignature) 
    {
        return keccak256(abi.encodePacked(recipeItems, recipeAmounts));
    }

    /// @dev Returns a list of all recipes
    function getRecipes()
        external
        view
        returns (Recipe[] memory allRecipes) 
    {
        // Store total number of recipes into a local variable
        uint256 total = totalRecipes;
        if ( total == 0 ) {
            // if no recipes added, return an empty array
            return allRecipes;
        } else {
            Recipe[] memory _allRecipes = new Recipe[](total);
            // Loop through the recipes
            for(uint256 i = 0; i < total;){
                // Add recipe to the array
                _allRecipes[i] = recipes[i+1];
                unchecked { ++i; }
            }
            return _allRecipes;
        }
    }

}
