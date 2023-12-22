// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces_IERC20.sol";
import "./SafeERC20.sol";
import "./interfaces_IERC777.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ICornV2.sol";
import "./ILandDistributor.sol";
import "./IWrappedCharacters.sol";
import "./IItemSets.sol";
import "./IItems.sol";
import "./IQuests.sol";

/// @dev Farmland - Quest Type Smart Contract
contract QuestType is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

// CONSTRUCTOR

    constructor (
        address[6] memory farmlandAddresses)
        {
            require(farmlandAddresses.length == 6, "Invalid number of contract addresses");
            cornContract = ICornV2(farmlandAddresses[0]);
            landDistributor = ILandDistributor(farmlandAddresses[2]);
            itemSetsContract = IItemSets(farmlandAddresses[4]);
            landContract = IERC777(farmlandAddresses[5]);
            explorers = IWrappedCharacters(farmlandAddresses[1]);
            itemsContract = IItems(farmlandAddresses[3]);
        }

// STATE VARIABLES

    /// @dev This is the Land contract
    ICornV2 internal immutable cornContract;

    /// @dev This is the Land contract
    IERC777 internal immutable landContract;

    /// @dev This is the Land Distributor contract
    ILandDistributor internal immutable landDistributor;

    /// @dev The Farmland Item Sets contract
    IItemSets internal immutable itemSetsContract;

    /// @dev The Farmland Character Contract
    IWrappedCharacters internal immutable explorers;

    /// @dev The Farmland Items contract
    IItems internal immutable itemsContract;

    /// @dev Create a mapping to track each type of quest
    mapping(uint256 => Quest) internal quests;

    /// @dev Tracks the last Quest ID
    uint256 public lastQuestID;
 
    /// @dev Create an mapping to track a explorers latest quest
    mapping(uint256 => uint256) internal latestQuest;

    /// @dev Create an mapping to track if hazard are avoided
    mapping(uint256 => bool[]) internal currentHazards;

    /// @dev Create an mapping to track a explorers item in use
    mapping(uint256 => uint256) internal itemOnQuest;

    /// @dev Define the itemset that helps to find Land as a constant
    uint256 constant internal LAND_ITEM_SET = 10;

    /// @dev Define the itemset that helps on hazardous quests as a constant
    uint256 constant internal HAZARD_ITEM_SET = 11;

// MODIFIERS

    /// @dev Check if the explorer is inactive
    /// @param tokenID of explorer
    modifier onlyInactive(uint256 tokenID) {
        // Get the explorers activity
        (bool active,,,,,) = explorers.charactersActivity(tokenID);
        require (!active, "Explorer needs to complete quest");
        _;
    }

    /// @dev Check if the explorer is active
    /// @param tokenID of explorer
    modifier onlyActive(uint256 tokenID) {
        // Get the explorers activity
        (bool active,,,,,) = explorers.charactersActivity(tokenID);
        require (active, "Explorer can only complete quest once");
        _;
    }

    /// @dev Explorer can't be on a quest
    /// @param tokenID of explorer
    modifier onlyQuestExpired(uint256 tokenID) {
        require (explorers.getBlocksUntilActivityEnds(tokenID) == 0, "Explorer still on a quest");
        _;
    }

    /// @dev Check if the explorer is owned by account calling function
    /// @param tokenID of explorer
    modifier onlyCharacterOwner (uint256 tokenID) {
        require (explorers.ownerOf(tokenID) == _msgSender(),"Only the owner of the token can perform this action");
        _;
    }

    /// @dev Check if quest enabled
    modifier onlyWhenQuestEnabled(uint256 questID) {
        require (quests[questID].active, "Quest inactive");
        _;
    }

    /// @dev Check if quest enabled
    modifier onlyWhenQuestExists(uint256 questID) {
        require (questID <= lastQuestID, "Unknown Quest");
        _;
    }

// ADMIN FUNCTIONS

    /// @dev Create a quest & set the drop rate
    /// @param questDetails the quests details based on the struct
    function createQuest(Quest calldata questDetails)
        external
        onlyOwner
    {
        require(questDetails.dropRate.length == 5, "Requires 5 drop rate values");
        // Set the quest details
        quests[lastQuestID] = questDetails;
        // Increment the quest number
        unchecked { ++lastQuestID; }
    }

    /// @dev Update a quest & set the drop rate
    /// @param questID the quests ID
    /// @param questDetails the quests details based on the struct
    function updateQuest(uint256 questID, Quest calldata questDetails)
        external
        onlyOwner
    {
        require(questDetails.dropRate.length == 5, "Requires 5 drop rate values");
        // Update the quest details
        quests[questID] = questDetails;
    }

    /// @dev Allows the owner to withdraw tokens from the contract
    function withdrawToken(address paymentAddress) 
        external 
        onlyOwner 
    {
        require(paymentAddress != address(0),"Address can't be zero address");
        // Retrieves the token balance
        uint256 amount = IERC20(paymentAddress).balanceOf(address(this));
        require(amount > 0, "There's no balance to withdraw");
        // Send to the owner
        IERC20(paymentAddress).safeTransfer(owner(), amount);
    }

// INTERNAL FUNCTIONS

    /// @dev Returns an array of Random Numbers
    /// @param n number of random numbers to generate
    /// @param salt a number that adds to randomness
    function getRandomNumbers(uint256 n, uint256 salt)
        internal
        view
        returns (uint256[] memory randomNumbers)
    {
        randomNumbers = new uint256[](n);
        for (uint256 i = 0; i < n;) {
            randomNumbers[i] = uint256(keccak256(abi.encodePacked(block.timestamp, salt, i)));
            unchecked { ++i; }
        }
    }

// VIEWS

    /// @dev Returns a list of all quests
    function getQuests()
        external
        view
        returns (string[] memory allQuests) 
    {
        // Store total number of quests into a local variable
        uint256 total = lastQuestID;
        if ( total == 0 ) {
            // if no quests added, return an empty array
            return allQuests;
        } else {
            allQuests = new string[](total);
            // Loop through the quests
            for(uint256 i = 0; i < total;){
                // Add quests to array
                allQuests[i] = quests[i].name;
                unchecked { ++i; }
            }
        }
    }

    /// @dev Returns the quest details
    /// @param questID the quests ID
    function getQuest(uint256 questID)
        external
        view
        returns (Quest memory questDetails) 
    {
        return quests[questID];
    }

}
