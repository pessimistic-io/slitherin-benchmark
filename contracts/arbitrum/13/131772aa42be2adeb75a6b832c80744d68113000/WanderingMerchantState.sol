//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IWanderingMerchant.sol";
import "./AdminableUpgradeable.sol";
import "./IConsumable.sol";
import "./ILegion.sol";
import "./ILegionMetadataStore.sol";

abstract contract WanderingMerchantState is Initializable, IWanderingMerchant, AdminableUpgradeable {

    event WanderingMerchantActiveTimeChanged(uint128 openTime, uint128 closeTime);
    event WanderingMerchantRecipeAdded(uint64 indexed recipeId, uint32 currentAvailable, uint32 maxAvailable, uint32 inputTokenId, InputType inputType, Output[] outputs);
    event WanderingMerchantRecipeRemoved(uint64 indexed recipeId);
    event WanderingMerchantRecipeFulfilled(uint64 indexed recipeId, address indexed user);

    IConsumable public consumable;
    ILegion public legion;
    ILegionMetadataStore public legionMetadataStore;

    uint128 public openTime;
    uint128 public closeTime;

    mapping(uint64 => RecipeInfo) recipeIdToInfo;
    uint64 public recipeIdCur;

    uint64[] public activeRecipeIds;

    function __WanderingMerchantState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        recipeIdCur = 1;
    }
}

struct RecipeInfo {
    // Slot 1
    mapping(uint32 => Output) outputIndexToOutput;

    // Slot 2 (144/256)
    //
    // The remaining times this recipe can be used. Will be decremented until
    // it reaches 0.
    //
    uint32 currentAvailable;
    uint32 maxAvailable;
    // If consumable, corresponds to the consumable id.
    // If legion, will be 0.
    //
    uint32 inputTokenId;
    InputType inputType;
    uint32 numberOfOutputs;
    bool isActive;
}

struct Output {
    // Slot 1 (200/256)
    //
    OutputType outputType;
    address transferredFrom;
    uint32 tokenId;

    // Slot 2
    //
    uint256 amount;

    // Slot 3 (160/256)
    //
    // Used to determine which ERC20 is being transferred for OutputType.TRANSFERRED_ERC20.
    //
    address outputAddress;
}

enum InputType {
    CONSUMABLE,
    AUXILIARY_LEGION
}

enum OutputType {
    CONSUMABLE,
    TRANSFERRED_ERC20
}

