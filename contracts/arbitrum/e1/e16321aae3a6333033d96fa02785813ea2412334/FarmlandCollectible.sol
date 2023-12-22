// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Initializable.sol";

struct CollectibleTraits {uint256 expiryDate; uint256 trait1; uint256 trait2; uint256 trait3; uint256 trait4; uint256 trait5;}
struct CollectibleSegments {uint256 segment1; uint256 segment2; uint256 segment3; uint256 segment4; uint256 segment5; uint256 segment6; uint256 segment7; uint256 segment8;}
struct CollectibleSlots {uint256 slot1; uint256 slot2; uint256 slot3; uint256 slot4; uint256 slot5; uint256 slot6; uint256 slot7; uint256 slot8;}

abstract contract FarmlandCollectible is ERC721, ERC721Enumerable, Pausable, Ownable, ReentrancyGuard, Initializable {
    using Strings for string;
    using SafeERC20 for IERC20;

// MODIFIERS

    /**
     * @dev To limit this action to the contract designed for modifying the slots
     */
    modifier onlySlotModifier() {
        require(slotContractAddress == _msgSender(), "You don't have permission to set this collectibles slot");
        _;
    }

    /**
     * @dev This is the Collectibles reserved for giveaways and promotions
     */
    uint256 private reserved;
    
    /**
     * @dev This is the Collectibles total supply
     */
    uint256 public maxSupply;
    
    /**
     * @dev This is the Collectible price
     */
    uint256 public price;

    /**
     * @dev This is determines how many trait boosts are allowed
     */
    uint256 public maxTraitBoosts = 10;
   
    /**
     * @dev This is the price for trait boosts
     */
    uint256 public traitBoostPrice;

    /**
     * @dev This is the contract used to pay for trait boosts
     */
    IERC20 public traitPaymentContract;

    /**
     * @dev This is the contract used to update Collectible slots
     */
    address slotContractAddress;

    /**
     * @dev Initialise the nonce used to generate pseudo random numbers
     */
    uint256 private randomNonce;

    /**
     * @dev This stores the base URI used to generat the token ID
     */
    string public baseURI;

    /**
     * @dev PUBLIC: Stores the key traits for Farmland Collectibles
     */
    mapping(uint256 => CollectibleTraits) public collectibleTraits;

    /**
     * @dev PUBLIC: Stores the number trait boosts used by Farmland Collectibles
     */
    mapping(uint256 => uint256) public collectibleTraitBoostTracker;

    /**
     * @dev PUBLIC: Stores segments for Farmland Collectibles, can be used by the owners to group or stamp collectibles
     */
    mapping(uint256 => CollectibleSegments) public collectibleSegments;

    /**
     * @dev PUBLIC: Stores slots for Farmland Collectibles, can be used to store various items / awards for collectibles
     */
    mapping(uint256 => CollectibleSlots) public collectibleSlots;

// EVENTS

    event CharacterBoosted(address booster, uint256 id, uint256 trait, uint256 boost, uint256 pricePaid);
    event CharacterSegmented(address segmenter, uint256 id, uint256 segmentIndex, uint256 segment);
    event CharacterSlotSet(address slotSetter, uint256 id, uint256 slotIndex, uint256 slot);
    event ContractAddressChanged(address updatedBy, string addressType, address newAddress);

    function mintCollectible(uint256 numTokens) 
        external
        virtual
        payable
        nonReentrant
        whenNotPaused
    {
        uint256 supply = totalSupply();
        require( numTokens < 21,                                                          "You can mint a maximum of 20" );
        require( supply + numTokens < maxSupply - reserved,                               "Exceeds maximum supply" );
        require( msg.value >= price * numTokens,                                          "Ether sent is not correct" );
        for(uint256 i = 0; i < numTokens; i++){
            uint256 id = supply++;                                                        // Increment Token id
            storeTraits(id);                                                              // Store Collectible traits on chain
            _safeMint(_msgSender(), id);                                                  // Mint the Collectible
        }
    }

    function boostTrait(uint256 id, uint256 trait, uint256 boost)
        external
        virtual
        nonReentrant
        whenNotPaused
    {
        require( boost <= maxTraitBoosts,                                                  "This will exceed the maximum character boost" );
        require( ownerOf(id) == _msgSender(),                                              "Only the owner can boost this characters traits" );
        require( traitPaymentContract.balanceOf(_msgSender()) >= traitBoostPrice * boost,  "Balance too low to pay for character boost" );
        uint256 newTraitBoost = collectibleTraitBoostTracker[id] + boost;                  // Calculate the new trait tracker value after the boost
        require( newTraitBoost <= maxTraitBoosts,                                          "This will exceed the remaining character boost");
        CollectibleTraits storage collectibleTrait = collectibleTraits[id];                // Create accessor shortcut
        uint256 newTrait;                                                                  // Initialise a local variable
        if (trait == 1 ) {                                                                 // For trait 1
            newTrait = collectibleTrait.trait1 + boost;                                    // Calculate the new trait 1 value after the boost
            require ( newTrait < 100, "This will exceed the maximum trait boost");         // Revert if the new trait exceeds 99
            collectibleTrait.trait1 = newTrait;                                            // Update trait 1 value to the new trait value
        }
        else if (trait == 2 ) {
            newTrait = collectibleTrait.trait2 + boost;
            require ( newTrait < 100, "This will exceed the maximum trait boost");
            collectibleTrait.trait2 = newTrait;
        }
        else if (trait == 3 ) {
            newTrait = collectibleTrait.trait3 + boost;
            require ( newTrait < 100, "This will exceed the maximum trait boost");
            collectibleTrait.trait3 = newTrait;
        }
        else if (trait == 4 ) {
            newTrait = collectibleTrait.trait4 + boost;
            require ( newTrait < 100, "This will exceed the maximum trait boost");
            collectibleTrait.trait4 = newTrait;
        }
        else if (trait == 5 ) {
            newTrait = collectibleTrait.trait5 + boost;
            require ( newTrait < 100, "This will exceed the maximum trait boost");
            collectibleTrait.trait5 = newTrait;
        }
        collectibleTraitBoostTracker[id] = newTraitBoost;                                                 // Update the trait tracker value after the boost
        emit CharacterBoosted(_msgSender(), id, trait, boost, traitBoostPrice * boost);                   // Write an event
        traitPaymentContract.safeTransferFrom(_msgSender(), address(this), traitBoostPrice * boost);      // Take the payment for the boost
    }

    function setCollectibleSegment(uint256 id, uint256 segmentIndex, uint256 segment)
        external
        virtual
        nonReentrant
        whenNotPaused
    {
        require( _exists(id),                                               "This Collectible hasn't been minted");
        require( ownerOf(id) == _msgSender() ,                              "Only the owner of this Collectible can set the segment" );
        CollectibleSegments storage segments = collectibleSegments[id];     // Create accessor shortcut
        if (segmentIndex == 1 ) {                                           // For segment 1
            segments.segment1 = segment;                                    // Update segment 1 based on input
        }
        else if (segmentIndex == 2 ) {
            segments.segment2 = segment;
        }
        else if (segmentIndex == 3 ) {
            segments.segment3 = segment;
        }
        else if (segmentIndex == 4 ) {
            segments.segment4 = segment;
        }
        else if (segmentIndex == 5 ) {
            segments.segment5 = segment;
        }
        else if (segmentIndex == 6 ) {
            segments.segment6 = segment;
        }
        else if (segmentIndex == 7 ) {
            segments.segment7 = segment;
        }
        else if (segmentIndex == 8 ) {
            segments.segment8 = segment;
        }
        emit CharacterSegmented(_msgSender(), id, segmentIndex, segment);     // Write an event
    }

    function setCollectibleSlot(uint256 id, uint256 slotIndex, uint256 slot)
        external
        virtual
        nonReentrant
        whenNotPaused
        onlySlotModifier
    {
        require( _exists(id),                                                   "This collectible hasn't been minted");
        CollectibleSlots storage slots = collectibleSlots[id];                  // Create accessor shortcut
        if (slotIndex == 1 ) {                                                  // For slot 1
            slots.slot1 = slot;                                                 // Update slot 1 based on input
        }
        else if (slotIndex == 2 ) {
            slots.slot2 = slot;
        }
        else if (slotIndex == 3 ) {
            slots.slot3 = slot;
        }
        else if (slotIndex == 4 ) {
            slots.slot4 = slot;
        }
        else if (slotIndex == 5 ) {
            slots.slot5 = slot;
        }
        else if (slotIndex == 6 ) {
            slots.slot6 = slot;
        }
        else if (slotIndex == 7 ) {
            slots.slot7 = slot;
        }
        else if (slotIndex == 8 ) {
            slots.slot8 = slot;
        }
        emit CharacterSlotSet(_msgSender(), id, slotIndex, slot);     // Write an event
    }

    function random(uint256 max, address account)
        internal
        returns (uint256 randomNumber)
    {
        randomNonce++;
        return uint256(keccak256(abi.encodePacked(block.timestamp, account, randomNonce))) % max;
    }

    function storeTraits(uint256 id) internal virtual {}

    function _baseURI() 
        internal
        view
        override(ERC721)
        returns (string memory)
    {
        return baseURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        string memory uri = super.tokenURI(tokenId);
        return string(abi.encodePacked(uri,".json"));
    }

    function walletOfOwner(address account) 
        external
        view
        returns(uint256[] memory tokenIds)
    {
        uint256 _tokenCount = balanceOf(account);
        uint256[] memory _tokensId = new uint256[](_tokenCount);
        if (_tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            for(uint256 i = 0; i < _tokenCount; i++){
                _tokensId[i] = tokenOfOwnerByIndex(account, i);
            }
        }
        return _tokensId;
    }

// ADMIN FUNCTIONS

    // Enable giveaways to supportive community members & for promotions
    function giveAway(address to, uint256 amount)
        external
        nonReentrant
        onlyOwner
    {
       require( amount <= reserved, "Exceeds reserved supply" );
       reserved -= amount;
       uint256 supply = totalSupply();
       for(uint256 i = 0; i < amount; i++){
           uint256 id = supply++;    // Increment id
           storeTraits(id);          // Store Collectible traits on chain
           _safeMint (to, id);
       }
    }

    // Initialize the contract
    function initialize(string memory uri, uint256 reservedSupply, uint256 maximumSupply, uint256 characterPrice, uint256 boostPrice, address traitPaymentContractAddress, address slotModifierAddress)
        external
        onlyOwner
        initializer
    {
        require(traitPaymentContractAddress != address(0), "Trait Payment Contract address cannot be 0x0");
        require(slotModifierAddress != address(0), "Slot Modifier Contract address cannot be 0x0");
        baseURI = uri;
        reserved = reservedSupply;
        maxSupply = maximumSupply;
        price = characterPrice;
        traitBoostPrice = boostPrice;
        traitPaymentContract = IERC20(traitPaymentContractAddress);
        emit ContractAddressChanged(_msgSender(), "TraitPayment", traitPaymentContractAddress);
        slotContractAddress = slotModifierAddress;
        emit ContractAddressChanged(_msgSender(), "SlotModifier", slotModifierAddress);
    }

    // Allow change in the prices
    function setPrice(uint256 characterPrice, uint256 boostPrice) 
        external
        onlyOwner
    {
        if ( characterPrice != 0 && 
             characterPrice != price
        ) {
            price = characterPrice;             // In ETH
        }
        if ( boostPrice != 0 && 
             boostPrice != traitBoostPrice
        ) {
            traitBoostPrice = boostPrice;       // In ERC20
        }
    }

    // If the metadata needs to be moved
    function setBaseURI(string memory uri)
        external
        onlyOwner
    {
        baseURI = uri;
    }

    // If the amount of boosts needs to be updated
    function setMaxTraitBoost(uint256 maxBoost) 
        external
        onlyOwner
    {
        maxTraitBoosts = maxBoost;
    }

    // Start or pause the sale
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

    // Enable changes to key contract address
    function setContractAddress(
            address traitPaymentContractAddress,
            address slotModifierAddress
        )
        external
        onlyOwner
    {
        if ( traitPaymentContractAddress != address(0) && 
             traitPaymentContractAddress != address(IERC20(traitPaymentContract))
        ) {
           traitPaymentContract = IERC20(traitPaymentContractAddress);
           emit ContractAddressChanged(_msgSender(), "TraitPayment", traitPaymentContractAddress);
        }

        if ( slotModifierAddress != address(0) && 
             slotModifierAddress != slotContractAddress
        ) {
           slotContractAddress = slotModifierAddress;
           emit ContractAddressChanged(_msgSender(), "SlotModifier", slotModifierAddress);
        }
    }

    // Withdraw ETH & ERC20
    function withdrawAll()
        external
        payable
        onlyOwner
    {
        payable(owner()).transfer(address(this).balance);
        uint256 amount = traitPaymentContract.balanceOf(address(this));
        if ( amount > 0 ) {
            traitPaymentContract.safeTransfer(owner(), amount);
        }
    }

    fallback() external payable { }
    
    receive() external payable { }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }
}
