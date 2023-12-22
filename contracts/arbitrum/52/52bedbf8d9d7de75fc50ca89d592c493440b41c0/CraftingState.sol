//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./ICrafting.sol";
import "./IItemz.sol";
import "./IBadgez.sol";
import "./IBugz.sol";
import "./IRandomizer.sol";
import "./IToadz.sol";
import "./IWorld.sol";
import "./AdminableUpgradeable.sol";

abstract contract CraftingState is ICrafting, ERC721HolderUpgradeable, ERC1155HolderUpgradeable, AdminableUpgradeable {

    event RecipeAdded(
        uint64 indexed _recipeId,
        CraftingRecipe _craftingRecipe
    );
    event RecipeDeleted(
        uint64 indexed _recipeId
    );

    // Called when the currentCraftsGlobal for a recipe
    // was manipulated outside of the normal crafting routine.
    event RecipeCraftsGlobalUpdated(
        uint64 indexed _recipeId,
        uint64 _totalCraftsGlobal
    );

    event CraftingStarted(
        address indexed _user,
        uint256 indexed _craftingId,
        uint128 _timeOfCompletion,
        uint64 _recipeId,
        uint64 _requestId,
        uint64 _tokenId,
        ItemInfo[] suppliedInputs
    );
    event CraftingEnded(
        uint256 _craftingId,
        uint256 _bugzRewarded,
        CraftingItemOutcome[] _itemOutcomes
    );

    IBugz public bugz;
    IItemz public itemz;
    IRandomizer public randomizer;
    IToadz public toadz;
    IWorld public world;
    IBadgez public badgez;

    uint64 public recipeIdCur;

    mapping(string => uint64) public recipeNameToRecipeId;

    mapping(uint64 => CraftingRecipe) public recipeIdToRecipe;
    mapping(uint64 => CraftingRecipeInfo) public recipeIdToInfo;
    // Ugly type signature.
    // This allows an O(1) lookup if a given combination is an option for an input and the exact amount and index of that option.
    mapping(uint64 => mapping(uint256 => mapping(uint256 => uint256))) internal recipeIdToInputIndexToItemIdToOptionIndex;

    mapping(address => EnumerableSetUpgradeable.UintSet) internal userToCraftsInProgress;

    uint256 public craftingIdCur;
    mapping(uint256 => UserCraftingInfo) internal craftingIdToUserCraftingInfo;

    // For a given toad, gives the current crafting instance it belongs to.
    mapping(uint256 => uint256) public toadIdToCraftingId;

    function __CraftingState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();

        craftingIdCur = 1;
        recipeIdCur = 1;
    }
}

struct UserCraftingInfo {
    uint128 timeOfCompletion;
    uint64 recipeId;
    uint64 requestId;
    uint64 toadId;
    ItemInfo[] nonBurnedInputs;
    mapping(uint256 => UserCraftingInput) itemIdToInput;
}

struct UserCraftingInput {
    uint64 itemAmount;
    bool wasBurned;
}

struct CraftingRecipe {
    string recipeName;
    // The time at which this recipe becomes available. Must be greater than 0.
    //
    uint256 recipeStartTime;
    // The time at which this recipe ends. If 0, there is no end.
    //
    uint256 recipeStopTime;
    // The cost of bugz, if any, to craft this recipe.
    //
    uint256 bugzCost;
    // The number of times this recipe can be crafted globally.
    //
    uint64 maxCraftsGlobally;
    // The amount of time this recipe takes to complete. May be 0, in which case the recipe could be instant (if it does not require a random).
    //
    uint64 timeToComplete;
    // If this requires a toad.
    //
    bool requiresToad;
    // The inputs for this recipe.
    //
    RecipeInput[] inputs;
    // The outputs for this recipe.
    //
    RecipeOutput[] outputs;
}

// The info stored in the following struct is either:
// - Calculated at the time of recipe creation
// - Modified as the recipe is crafted over time
//
struct CraftingRecipeInfo {
    // The number of times this recipe has been crafted.
    //
    uint64 currentCraftsGlobally;
    // Indicates if the crafting recipe requires a random number. If it does, it will
    // be split into two transactions. The recipe may still be split into two txns if the crafting recipe takes time.
    //
    bool isRandomRequired;
}

// This struct represents a single input requirement for a recipe.
// This may have multiple inputs that can satisfy the "input".
//
struct RecipeInput {
    RecipeInputOption[] inputOptions;
    // Indicates the number of this input that must be provided.
    // i.e. 11 options to choose from. Any 3 need to be provided.
    // If isRequired is false, the user can ignore all 3 provided options.
    uint8 amount;
    // Indicates if this input MUST be satisifed.
    //
    bool isRequired;
}

// This struct represents a single option for a given input requirement for a recipe.
//
struct RecipeInputOption {
    // The item that can be supplied
    //
    ItemInfo itemInfo;
    // Indicates if this input is burned or not.
    //
    bool isBurned;
    // The amount of time using this input will reduce the recipe time by.
    //
    uint64 timeReduction;
    // The amount of bugz using this input will reduce the cost by.
    //
    uint256 bugzReduction;
}

// Represents an output of a recipe. This output may have multiple options within it.
// It also may have a chance associated with it.
//
struct RecipeOutput {
    RecipeOutputOption[] outputOptions;
    // This array will indicate how many times the outputOptions are rolled.
    // This may have 0, indicating that this RecipeOutput may not be received.
    //
    uint8[] outputAmount;
    // This array will indicate the odds for each individual outputAmount.
    //
    OutputOdds[] outputOdds;
}

// An individual option within a given output.
//
struct RecipeOutputOption {
    // May be 0.
    //
    uint64 itemId;
    // The min and max for item amount, if different, is a linear odd with no boosting.
    //
    uint64 itemAmountMin;
    uint64 itemAmountMax;
    // If not 0, indicates the badge the user may get for this recipe output.
    //
    uint64 badgeId;
    uint128 bugzAmount;
    // The odds this option is picked out of the RecipeOutput group.
    //
    OutputOdds optionOdds;
}

// This is a generic struct to represent the odds for any output. This could be the odds of how many outputs would be rolled,
// or the odds for a given option.
//
struct OutputOdds {
    uint32 baseOdds;
    // The itemIds to boost these odds. If this shows up ANYWHERE in the inputs, it will be boosted.
    //
    uint64[] boostItemIds;
    // For each boost item, this the change in odds from the base odds.
    //
    int32[] boostOddChanges;
}

// For event
struct CraftingItemOutcome {
    uint64[] itemIds;
    uint64[] itemAmounts;
}
