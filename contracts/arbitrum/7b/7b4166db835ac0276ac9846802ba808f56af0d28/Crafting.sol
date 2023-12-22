// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Recipes.sol";

/// @dev Farmland - Simple Crafting Smart Contract
contract Crafting is Recipes {
    using SafeERC20 for IERC20;

// CONSTRUCTOR

    constructor (
          address itemsContract
        ) Recipes() {
            require(itemsContract != address(0), "Invalid Items Contract");
            items = IItems(itemsContract);
        }

// STATE VARIABLES

    /// @dev The Farmland Items contract
    IItems internal immutable items;

// EVENTS

    event RecipeCrafted(address indexed account, uint256 indexed recipeID, uint256 indexed item, uint256 amount);
    event RecipesCrafted(address indexed account, uint256 indexed recipeID, uint256 indexed item, uint256 amount);

// FUNCTIONS

    /// @dev Craft single item
    /// @param recipeID to use
    /// @param itemIDs to be used in the recipe
    /// @param amounts to be used in the recipe
    function craftItem(uint256 recipeID, uint256[] memory itemIDs, uint256[] memory amounts)
        external
        nonReentrant
        whenNotPaused
        onlyWhenActive(recipeID)
    {
        // Do some checks before proceeding
        require (itemIDs.length == amounts.length, "Number of items & amounts should match");
        require (getRecipeSignature(recipes[recipeID].recipeItems, recipes[recipeID].recipeAmounts) == getRecipeSignature(itemIDs, amounts), "Details should match the recipe");
        // Store the recipe details locally to save gas
        uint256 itemToMint = recipes[recipeID].itemID;
        uint256 totalToMint = recipes[recipeID].amount;
        // Write an event
        emit RecipeCrafted(_msgSender(), recipeID, itemToMint, totalToMint);
        // Burn items
        items.burnBatch(_msgSender(), itemIDs, amounts);
        // Mint crafted item
        items.mintItem(itemToMint, totalToMint, _msgSender());
        // Check if a payable recipe
        if (recipes[recipeID].paymentAddress != address(0)) {
            // Setup the payment contract
            IERC20 paymentContract = IERC20(recipes[recipeID].paymentAddress);
            // Calculate price to pay
            uint256 priceToPay = recipes[recipeID].price ;
            require(paymentContract.balanceOf(_msgSender()) >= priceToPay, "Balance too low");
            // Take the payment for crafting
            paymentContract.safeTransferFrom(_msgSender(), address(this), priceToPay);
        }
    }

    /// @dev Craft multiple items
    /// @param recipeID to use
    /// @param itemIDs to be used in the recipe
    /// @param amounts to be used in the recipe
    /// @param itemsToCraft number of items to craft
    function craftItems(uint256 recipeID, uint256[] memory itemIDs, uint256[] memory amounts, uint256 itemsToCraft)
        external
        nonReentrant
        whenNotPaused
        onlyWhenActive(recipeID)
    {
        // Do some checks before proceeding
        require (itemIDs.length == amounts.length, "Number of items & amounts should match");
        require (getRecipeSignature(recipes[recipeID].recipeItems, recipes[recipeID].recipeAmounts) == getRecipeSignature(itemIDs, amounts), "Details should match the recipe");
        // Store the recipe details locally to save gas
        uint256 itemToMint = recipes[recipeID].itemID;
        uint256 totalToMint = recipes[recipeID].amount * itemsToCraft;
        // Write an event
        emit RecipeCrafted(_msgSender(), recipeID, itemToMint, totalToMint);
        for (uint256 i=1; i <= itemsToCraft;) {
            // Burn items
            items.burnBatch(_msgSender(), itemIDs, amounts);
            unchecked { ++i; }
        }
        // Mint crafted item
        items.mintItem(itemToMint, totalToMint, _msgSender());
        // Check if a payable recipe
        if (recipes[recipeID].paymentAddress != address(0)) {
            // Setup the payment contract
            IERC20 paymentContract = IERC20(recipes[recipeID].paymentAddress);
            // Calculate price to pay
            uint256 priceToPay = recipes[recipeID].price * itemsToCraft;
            require(paymentContract.balanceOf(_msgSender()) >= priceToPay, "Balance too low");
            // Take the payment for crafting
            paymentContract.safeTransferFrom(_msgSender(), address(this), priceToPay);
        }
    }

// ADMIN FUNCTIONS

    /// @dev Allows the owner to withdraw all the payments from the contract
    function withdrawAll()
        external 
        onlyOwner
    {
        // Store total number of recipes into a local variable to save gas
        uint256 total = totalRecipes;
        // Instantiate local variable to store the amount to withdraw
        uint256 amount;
        // Loop through all recipes
        for (uint256 i=1; i <= total;) {
            // Setup the payment contract
            IERC20 paymentContract = IERC20(recipes[i].paymentAddress);
            // If payment contract is registered
            if (address(paymentContract) != address(0)) {
                // Retrieves the token balance
                amount = paymentContract.balanceOf(address(this));
                // If there's a balance
                if ( amount > 0 ) {
                    // Send to the owner
                    paymentContract.safeTransfer(_msgSender(), amount);
                }
            }
            unchecked { ++i; }
        }
    }

    /// @dev Start or pause the contract
    /// @param value to start or stop the contract
    function isPaused(bool value)
        public
        onlyOwner
    {
        if ( !value ) {
            _unpause();
        } else {
            _pause();
        }
    }

}
