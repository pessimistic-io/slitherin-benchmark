// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAddToAllowList.sol";
import "./PackTypes.sol";

/// @dev Farmland - Packs Smart Contract
contract Packs is PackTypes {
    using SafeERC20 for IERC20;

// CONSTRUCTOR

    constructor (
          address itemsAddress,
          address itemSetsAddress
        ) PackTypes (itemSetsAddress,itemsAddress)
        {
            require(itemSetsAddress != address(0), "Invalid Item Sets Contract address");
            require(itemsAddress != address(0), "Invalid Items Contract address");
        }

// MODIFIERS

    /// @dev Check if this account has already claimed the air dropped pack
    /// @param index to check
    /// @param packID of the pack to check
    modifier onlyUnclaimed(uint256 index, uint256 packID) {
        require (!isClaimed(index, packID), "Airdrop Pack Already Claimed");
        _;
    }

// EVENTS

    event PackClaimed(address indexed account, uint256 packID);
    event PackMinted(address indexed account, uint256 packID);

// FUNCTIONS

    /// @dev PUBLIC: Claim air dropped packs
    /// @param index of the account in the merkleproof
    /// @param merkleProof of the air drop
    /// @param amount of packs to receive
    /// @param packID of the pack to mint
    function claimAirDrop(uint256 index, bytes32[] calldata merkleProof, uint256 amount, uint256 packID)
        external
        nonReentrant
        whenNotPaused
        onlyUnclaimed(index, packID)
        onlyWhenPackEnabled(packID)
    {
        // Hash node details
        bytes32 node = keccak256(abi.encodePacked(index, _msgSender(), amount));
        // Shortcut accessor for the pack
        Pack storage pack = packs[packID];
        require(pack.packMerkleRoot[0] != 0, "Airdrop not available");
        require(MerkleProof.verify(merkleProof, packs[packID].packMerkleRoot, node), "Invalid proof");
        if (pack.maxSupply != 0) {
            require(pack.totalSupply + amount <= pack.maxSupply, "Max supply exceeded");
        }
        // Increment Supply
        pack.totalSupply += amount;
        // Flag packs as claimed
        _setClaimed(index, packID);
        // Write an event
        emit PackClaimed(_msgSender(), packID);
        // Mint the right amount of packs
        for (uint256 i = 0; i < amount;) {
            // Calculate which item to mint
            (uint256 itemToMint, uint256 totalToMint) = getRewardItem(packID, i);
            // Mint reward items
            itemsContract.mintItem(itemToMint, totalToMint, _msgSender());
            unchecked { ++i; }
        }
    }

    /// @dev PUBLIC: Claim a free pack
    /// @param index of the account on the allowlist
    /// @param packID of the pack to claim
    function claim(uint256 index,uint256 packID)
        external
        nonReentrant
        whenNotPaused
        onlyWhenPackEnabled(packID)
    {
        // Shortcut accessor for the pack
        Pack storage pack = packs[packID];
        require (pack.allowlist.length > 0 && index <= pack.allowlist.length, "Index out of range");
        require (pack.allowlist[index].account == _msgSender(), "Caller not allowlisted");
        require (!pack.allowlist[index].claimed, "Pack Already Claimed");
        // Get the amount
        uint256 amount = pack.allowlist[index].amount;
        if (pack.maxSupply != 0) {
            require(pack.totalSupply + amount <= pack.maxSupply, "Max supply exceeded");
        }
        // Increment Supply
        pack.totalSupply += amount;
        // Set as claimed
        pack.allowlist[index].claimed = true;
        // Write an event
        emit PackClaimed(_msgSender(), packID);
        // Loop through the amount of items to mint
        for (uint256 i = 0; i < amount;) {
            // Calculate which item to mint
            (uint256 itemToMint, uint256 totalToMint) = getRewardItem(packID, i);
            // Mint reward items
            itemsContract.mintItem(itemToMint, totalToMint, _msgSender());
            unchecked { ++i; }
        }
    }

    /// @dev PUBLIC: Buy a pack
    /// @param packID of the pack to mint
    /// @param amount of packs to buy
    function mint(uint256 packID, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyWhenPackEnabled(packID)
    {
        // Shortcut accessor for the pack
        Pack storage pack = packs[packID];
        // Store the price locally
        uint256 packPrice = pack.price;
        //Do some checks
        require (packPrice > 0, "This pack only allows claims");
        require (amount > 0, "Amount should more than zero");
        require (amount < 101, "Exceeds the maximum amount");
        // Write an event
        emit PackMinted(_msgSender(), packID);
        // If the pack has a limited supply
        if (pack.maxSupply != 0) {
            require(pack.totalSupply + amount <= pack.maxSupply, "Max supply exceeded");
        }
        // Increment Supply
        pack.totalSupply += amount;
        // If there is an allow list configured
        if (pack.allowlistAddress != address(0)){
            // Add to the allowlist as a reward if threshold met
            rewardAddToAllowList(packID);
        }
        // Mint an amount of packs
        for (uint256 i = 0; i < amount;) {
            // Calculate which item to mint
            (uint256 itemToMint, uint256 totalToMint) = getRewardItem(packID, i);
            // Mint reward items
            itemsContract.mintItem(itemToMint, totalToMint, _msgSender());
            unchecked { ++i; }
        }
        // Check if a payable Pack
        if (pack.paymentAddress != address(0)) {
            // Setup the payment contract
            IERC20 paymentContract = IERC20(pack.paymentAddress);
            // Calculate price to pay
            uint256 priceToPay = packPrice * amount;
            require( paymentContract.balanceOf(_msgSender()) >= priceToPay, "Balance too low");
            // Take the payment for the pack
            paymentContract.safeTransferFrom(_msgSender(), address(this), priceToPay);
        }
    }

// HELPER FUNCTIONS
    
    /// @dev Add to the (mercenaries) allowlist as a reward for minting a pack
    /// @param packID of the pack
    function rewardAddToAllowList(uint256 packID)
        private 
    {
        // Return some random numbers
        uint256[] memory randomNumbers = new uint256[](1);
        randomNumbers = getRandomNumbers(1,1);                                          
        // Choose a random number less than 1000
        uint256 random = randomNumbers[0] % 1000;
        // If the random number is less that the threshold then
        if (random < packs[packID].allowlistThreshold) {
            // Instantiate an array
            address[] memory accounts = new address[](1);
            // Add to the address of the wallet that minted the pack
            accounts[0] = _msgSender();
            // Add to the allowlist of the contract configured
            IAddToAllowList(packs[packID].allowlistAddress).addToAllowlist(accounts);
        }
    }

    /// @dev Flag Free Pack as claimed
    /// @param index of address
    /// @param packID of the pack to set
    function _setClaimed(uint256 index, uint256 packID)
        private 
    {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        packClaimedBitMap[packID][claimedWordIndex] = packClaimedBitMap[packID][claimedWordIndex] | (1 << claimedBitIndex);
    }

//VIEWS

    /// @dev Return a reward item & amount to mint 
    /// @param packID of the pack
    /// @param salt to add external entropy
    function getRewardItem(uint256 packID, uint256 salt)
        private
        view
        returns (
            uint256 itemToMint,
            uint256 totalToMint
        )
    {
        // Return some random numbers
        uint256[] memory randomNumbers = new uint256[](3);
        randomNumbers = getRandomNumbers(3, salt);
        // Declare & set the pack item set to work from
        uint256 itemSet = packs[packID].itemSet;
        // Choose a random number less than 1000
        uint256 random = randomNumbers[0] % 1000;
        // Initialise local variable
        uint256 dropRateBucket = 0;
        // Loop through the array of drop rates
        for (uint i = 0; i < 5;) {
            if (random > packs[packID].dropRate[i] &&
            // Choose rarity & ensure an item is registered
                itemSetsContract.getItemSetByRarity(itemSet,i).length > 0) {
                // Set the drop rate bucket
                dropRateBucket = i;
                // Move on
                break;
            }
            unchecked { ++i; }
        } 
        // Retrieve the list of items
        Item[] memory items = itemSetsContract.getItemSetByRarity(itemSet, dropRateBucket);
        require(items.length > 0, "ADMIN: Not enough items registered");
        // Randomly choose item to mint
        uint256 index = randomNumbers[1] % items.length;
        // Finds the items ID
        itemToMint = items[index].itemID;
        // Calculate cap
        uint256 cap = items[index].value1;
        // Random number capped @ cap
        totalToMint = (randomNumbers[2] % cap);
        // Ensure at least 1 item is found
        if (totalToMint == 0) { totalToMint = 1;}
    }

    /// @dev Check if index has been claimed
    /// @param index of address
    /// @param packID of the pack to check
    function isClaimed(uint256 index, uint256 packID)
        public
        view
        returns (bool) 
    {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = packClaimedBitMap[packID][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

}
