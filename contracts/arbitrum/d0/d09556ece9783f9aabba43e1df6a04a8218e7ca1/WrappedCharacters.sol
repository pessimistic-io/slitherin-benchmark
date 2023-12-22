// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./CharacterActivity.sol";

contract WrappedCharacters is CharacterActivity, ERC721, ERC721Holder, ReentrancyGuard {

// CONSTRUCTOR

    constructor (string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

// STATE VARIABLES

    // @dev Track the wrapped token id
    uint256 internal totalTokens;

    /// @dev This stores the base URI used to generate the token ID
    string public baseURI;

// MODIFIERS

    /// @dev Only if a character is wrapped
    /// @param tokenID of character
    modifier onlyExists(uint256 tokenID) {
        require (_exists(tokenID),"Character does not exist");
        _;
    }  

    /// @dev Only the owner of the character can perform this action
    /// @param tokenID of character
    modifier onlyOwnerOfToken(uint256 tokenID) {
        require (ownerOf(tokenID) == _msgSender(),"Only the owner of the token can perform this action");
        _;
    }  

// FUNCTIONS

    /// @dev Wraps an NFT & mints a wrappedCharacter
    /// @param account to interact with
    /// @param wrappedTokenID ID of the token
    /// @param collectionAddress address of the NFT collection
    function wrap(address account, uint256 wrappedTokenID, address collectionAddress)
        external
        nonReentrant
        isWrappable(collectionAddress)
        onlyAllowed
    {
        // Get the tokenID, if never wrapped before then it will be 0 & stamina will be 0
        uint256 tokenID;
        if (isNeverWrapped(collectionAddress, wrappedTokenID)) {
            // Increment wrapped token id
            unchecked { totalTokens++; }
            // Store the totalTokens as a local variable
            tokenID = totalTokens;
            // Set the stats
           _storeStats(collectionAddress, wrappedTokenID);
        } else {
            // Get the ID of previously wrapped token
            tokenID = tokenIDByHash[hashWrappedToken(collectionAddress,wrappedTokenID)];
        }
        // Wrap the character
        _wrap(account, collectionAddress, wrappedTokenID, tokenID);
        // Mint a wrapped character
        _mint(account, tokenID);
    }

    /// @dev Unwraps an NFT & burns the wrappedCharacter
    /// @param tokenID ID of the token
    function unwrap(uint256 tokenID) 
        external
        nonReentrant
        onlyExists(tokenID)
        onlyOwnerOfToken(tokenID)
    {        
        _burn(tokenID);
        _unwrap(tokenID);
    }

    /// @dev Increases a stat
    /// @param tokenID ID of the token
    /// @param amount to increase
    /// @param statIndex index of stat
    function increaseStat(uint256 tokenID, uint256 amount, uint256 statIndex)
        external
        onlyAllowed
        onlyExists(tokenID)
    {
        _increaseStat(tokenID, amount, statIndex);
    }

    /// @dev Decreases a stat
    /// @param tokenID ID of the token
    /// @param amount to increase
    /// @param statIndex index of stat
    function decreaseStat(uint256 tokenID, uint256 amount, uint256 statIndex)
        external
        onlyAllowed
        onlyExists(tokenID)
    {
        _decreaseStat(tokenID, amount, statIndex);
    }

    /// @dev Set characters stat to an arbitrary amount
    /// @dev if amount = stat then there's no change
    /// @param tokenID Characters ID
    /// @param amount to add
    function setStatTo(uint256 tokenID, uint256 amount, uint256 statIndex)
        external
        onlyAllowed
        onlyExists(tokenID)
    {
        _setStatTo(tokenID, amount, statIndex);
    }

    /// @dev Boost stats based on level, enables character progression
    /// @param tokenID Characters ID
    /// @param amount amount to increase stat
    /// @param statIndex which stat to increase
    function boostStat(uint256 tokenID, uint256 amount, uint256 statIndex)
        external
        onlyAllowed
        onlyExists(tokenID)
    {
        _boostStat(tokenID, amount, statIndex);
    }

    /// @dev Update characters activity status
    /// @param tokenID Characters ID
    /// @param active the amount
    function updateActivityStatus(uint256 tokenID, bool active)
        external
        onlyAllowed
        onlyExists(tokenID)
    {
        _updateActivityStatus (tokenID, active);
    }
    
    /// @dev Update characters Activity details
    /// @param tokenID Characters ID
    /// @param activity the activity details defined in the Activity struct
    function startActivity(uint256 tokenID, Activity calldata activity)
        external 
        onlyAllowed
        onlyExists(tokenID)
    {
        _startActivity(tokenID, activity);
    }


 // OWNER FUNCTION

    /// @dev If the metadata needs to be moved
    function setBaseURI(string memory uri)
        external
        onlyOwner
    {
        baseURI = uri;
    }

// VIEWS

    /// @dev Returns the total amount of tokens stored by the contract.
    function totalSupply() external view returns (uint256)
    {
        return totalTokens;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override (ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
