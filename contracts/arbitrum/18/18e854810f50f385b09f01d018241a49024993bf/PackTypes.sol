// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces_IERC20.sol";
import "./SafeERC20.sol";
import "./MerkleProof.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./Permissioned.sol";
import "./IItemSets.sol";
import "./IItems.sol";

struct Allowlist {address account; uint256 amount; bool claimed;}
struct Pack { 
    string name;                                    // The name of the pack
    uint256[5] dropRate;                            // The percentage chance of getting items [common % ,uncommon %, rare %, epic %, legendary %]
    uint256 itemSet;                                // The item set the pack can pull from
    uint256 price;                                  // Price of the pack, disregarded if payment address is empty
    address paymentAddress;                         // Zero address is a free mint
    bytes32 packMerkleRoot;                         // Stores the packs Merkle root, if empty airdrop not available
    uint256 maxSupply;                              // Max supply of packs
    uint256 totalSupply;                            // Current supply of packs
    uint256 allowlistThreshold;                     // Threshold for adding to an allowlist (0-1000) e.g., 100 = 10%
    address allowlistAddress;                       // Contract that supports addToAllowlist
    bool active;                                    // Status (Active/Inactive)
    Allowlist[] allowlist;                          // Onchain allowlist & claims
    }

/// @dev Farmland - PackTypes Smart Contract
contract PackTypes is ReentrancyGuard, Pausable, Permissioned {
    using SafeERC20 for IERC20;

// CONSTRUCTOR

    constructor (
          address itemSetsAddress,
          address itemsContractAddress
        ) Permissioned()
        {
            require(itemSetsAddress != address(0),      "Invalid Items Contract address");
            require(itemsContractAddress != address(0), "Invalid Items Contract address");
            itemSetsContract = IItemSets(itemSetsAddress);
            itemsContract = IItems(itemsContractAddress);
        }

// STATE VARIABLES

    /// @dev The Farmland ItemSets contract
    IItemSets internal immutable itemSetsContract;

    /// @dev The Farmland Items contract
    IItems internal immutable itemsContract;

    /// @dev Create a mapping to track each type of pack
    mapping(uint256 => Pack) public packs;

    /// @dev Stores the air drop claims by pack
    mapping (uint256 => mapping(uint256 => uint256)) packClaimedBitMap;

    /// @dev Tracks the last Pack ID
    uint256 public lastPackID;

// MODIFIERS

    /// @dev Check if items registered
    /// @param packID identifies the pack
    modifier onlyWhenPackEnabled(uint256 packID) {
        require (packs[packID].active, "Pack inactive");
        _;
    }
    
    /// @dev Checks whether an pack exists
    /// @param packID identifies the pack
    modifier onlyIfPackExists(uint256 packID) {
        require(packID < lastPackID,"Pack does not exist");
        _;
    }

// EVENTS

    event AccountAllowlisted(address sender, address indexed account, uint256 packID, uint256 amount);

// ADMIN FUNCTIONS


    /// @dev Adds a new pack to the game
    /// @param pack pack payload
    function addPack(Pack calldata pack)
        external
        onlyOwner
    {
        // Set the pack details
        packs[lastPackID] = pack;
        // Increment the total items
        unchecked { ++lastPackID; }
    }

    /// @dev The owner can update an pack
    /// @param packID ID of the pack
    /// @param pack pack payload
    function updatePack(uint256 packID, Pack calldata pack)
        external 
        onlyOwner
        onlyIfPackExists(packID)
    {
        // Set the pack details
        packs[packID] = pack;
    }

    /// @dev The owner can delete an pack
    /// @param packID ID of the pack
    function deletePack(uint256 packID)
        external 
        onlyOwner
        onlyIfPackExists(packID)
    {
        delete packs[packID];
    }

    /// @dev Adds a list of addresses to the allowlist
    /// @param packIDs which Pack are the accounts being allowlisted for
    /// @param accounts to add to the allowlist
    /// @param amounts to add to the allowlist
    function addToAllowlist(uint256[] memory packIDs, address[] memory accounts, uint256[] memory amounts)
        external
        onlyAllowed
    {
        require (accounts.length == amounts.length && accounts.length == packIDs.length, "Mismatching totals");
        uint256 total = accounts.length;
        for (uint i = 0; i < total;) {
            // Add to the allowlist
            packs[packIDs[i]].allowlist.push(Allowlist(accounts[i], amounts[i], false));
            // Write an event
            emit AccountAllowlisted(_msgSender(), accounts[i], packIDs[i], amounts[i]);
            unchecked { ++i; }
        }
    }

    /// @dev Start or pause the contract
    /// @param value to start or stop the contract
    function isPaused(bool value)
        external
        onlyOwner
    {
        if ( !value ) {
            _unpause();
        } else {
            _pause();
        }
    }

    /// @dev Allows the owner to withdraw all the payments from the contract
    function withdrawAll() 
        external 
        onlyOwner 
    {
        // Store total number of packs into a local variable to save gas
        uint256 total = lastPackID;                                        
        // Instantiate local variable to store the amount to withdraw
        uint256 amount;                                                    
        // Loop through all packs
        for (uint256 i=0; i < total;) {
            // Setup the payment contract
            IERC20 paymentContract = IERC20(packs[i].paymentAddress);
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
            unchecked{ ++i; }
        }
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
    
    /// @dev Returns a packs allowlist
    /// @param packID which pack to return
    function getPacksAllowList(uint256 packID)
        external
        view
        returns (Allowlist[] memory allowlist) 
    {
        allowlist = packs[packID].allowlist;
    }

    /// @dev Returns a packs drop rates
    /// @param packID which pack to return
    function getPackDropRates(uint256 packID)
        external
        view
        returns (uint256[5] memory dropRate) 
    {
        dropRate = packs[packID].dropRate;
    }

    /// @dev Returns a list of all packs
    function getPacks()
        external
        view
        returns (string[] memory allPacks)
    {
        // Store total number of packs into a local variable
        uint256 total = lastPackID;
        if ( total == 0 ) {
            // if no packs added, return an empty array
            return allPacks;
        } else {
            // Loop through the packs
            allPacks = new string[](total);
            for(uint256 i = 0; i < total;) {
                // Add packs to array
                allPacks[i] = packs[i].name;
                unchecked { ++i; }
            }
        }
    }

    /// @dev Check a allowlist address for unclaimed pack
    /// @param packID of the pack to check
    /// @param account address to check for allowlist
    function getAllowlistIndex(uint256 packID, address account)
        external
        view
        returns (
            bool unclaimed,
            uint256 index)
    {
        // Get the current allowlist array index
        uint256 total = packs[packID].allowlist.length;
        if (total == 0 ) {
            return (false, 0);
        } else {
            // Loop through the addresses
            for(uint256 i=0; i < total;){
                // if account matches and unclaimed
                if ( packs[packID].allowlist[i].account == account && !packs[packID].allowlist[i].claimed )
                {
                    return (true,i);
                }
                unchecked { ++i; }
            }
        }
    }

}
