// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./MerkleProof.sol";
import "./Permissioned.sol";
import "./IMercenaries.sol";

struct Allowlist {address account; bool claimed;}

/// @dev Farmland - Smart Contract for minting Mercenaries
contract MintMercenaries is ReentrancyGuard, Pausable, Permissioned {

// CONSTRUCTOR

    constructor (
        uint256 _traitPrice,
        uint256 _mercenaryPrice,
        address _mercenariesAddress,
        bytes32 _merkleRoot
        )
        {
            require(_mercenariesAddress != address(0), "Invalid Mercenaries Contract address");
            traitPrice = _traitPrice;
            mercenaryPrice = _mercenaryPrice;
            mercenaries = IMercenaries(_mercenariesAddress);
            merkleRoot = _merkleRoot;
            isPaused(true);
        }

// STATE VARIABLES

    /// @dev The Mercenaries contract
    IMercenaries internal immutable mercenaries;

    /// @dev Stores the mercenarys Merkle root, if empty airdrop not available
    bytes32 private merkleRoot;
    
    /// @dev Stores the offchain air drop claims
    mapping(uint256 => uint256) private claimedBitMap;

    /// @dev Stores the onchain allowlist & claims
    Allowlist[] private allowlist;

    /// @dev This is the price for minting
    uint256 public mercenaryPrice;

    /// @dev This is the price for updating traits
    uint256 public traitPrice;

// MODIFIERS

    /// @dev Check if this account has already claimed the air dropped mercenary
    /// @param index to check
    modifier onlyUnclaimed(uint256 index) {
        require (!isClaimed(index), "Mercenary Already Claimed");
        _;
    }

// EVENTS

    event MercenaryClaimed(address indexed account, uint256 index);
    event AccountAllowlisted(address sender, address indexed account);
    event SetPrice(address indexed sender, uint256 newPrice);
    event SetTraitPrice(address indexed sender, uint256 newPrice);
    
// FUNCTIONS

    /// @dev Claim air dropped mercenaries
    /// @param index of the account in the merkleproof
    /// @param merkleProof of the air drop
    /// @param traits an array representing the mercenaries traits e.g., ["blue hat","brown eyes]
    function claimAirDrop(uint256 index, bytes32[] calldata merkleProof, bytes16[] calldata traits)
        external
        nonReentrant
        whenNotPaused
        onlyUnclaimed(index)
    {
        require(merkleRoot[0] != 0, "Mercenary not available");
        // Hash node details
        bytes32 node = keccak256(abi.encodePacked(index, _msgSender(), uint256(1)));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "Invalid proof");
        // Flag mercenaries as claimed
        _setClaimed(index);
        // Write an event
        emit MercenaryClaimed(_msgSender(), index);
        // Mint Mercenary
        mercenaries.mint(_msgSender(), traits);
    }

    /// @dev Claim one free mercenary
    /// @param index of the account on the allowlist
    /// @param traits an array representing the mercenaries traits e.g., ["blue hat","brown eyes]
    function claim(uint256 index, bytes16[] calldata traits)
        external
        nonReentrant
        whenNotPaused
    {
        require (allowlist.length > 0 && index <= allowlist.length, "Index out of range");
        require (allowlist[index].account == _msgSender(), "Caller not allowlisted");
        require (!allowlist[index].claimed, "Mercenary Already Claimed");
        // Set claimed
        allowlist[index].claimed = true;
        // Write an event
        emit MercenaryClaimed(_msgSender(), index);
        // Mint Mercenary
        mercenaries.mint(_msgSender(), traits);                  
    }

    /// @dev Mint a mercenary
    /// @param traits an array representing the mercenaries traits e.g., ["blue hat","brown eyes]
    function mint(bytes16[] calldata traits)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require( msg.value >= mercenaryPrice, "Ether sent is not correct" );
        // Mint Mercenary
        mercenaries.mint(_msgSender(), traits);
    }

    /// @dev Wraps an NFT & mints a Mercenary
    /// @param tokenID ID of the token
    /// @param collectionAddress address of the NFT collection
    function wrap(uint256 tokenID, address collectionAddress)
        external
        nonReentrant
        whenNotPaused
    {
        // Wrap token as a Mercenary
        mercenaries.wrap(_msgSender(), tokenID, collectionAddress);
    }
    
    /// @dev Replace traits
    /// @param tokenID of mercenary
    /// @param traits an array representing the mercenaries traits e.g., [7,2,5,1,1]
    function updateTraits(uint256 tokenID, bytes16[] calldata traits)
        external
        payable
        nonReentrant
    {
        require(mercenaries.ownerOf(tokenID) == _msgSender(), "Only the owner can update traits");
        require( msg.value >= traitPrice, "Ether sent is not correct" );
        // Replace Visual Traits for mercenary
        mercenaries.updateTraits(tokenID, traits);
    }

// ADMIN FUNCTIONS

    /// @dev Adds a list of addresses to the allowlist
    /// @param accounts to add to the allowlist
    function addToAllowlist(address[] memory accounts)
        external
        onlyAllowed
    {
        uint256 total = accounts.length;
        for (uint i = 0; i < total;) {
            // Add to the allowlist
            allowlist.push(Allowlist(accounts[i], false));
            // Write an event
            emit AccountAllowlisted(_msgSender(), accounts[i]);
            unchecked { i++; }               
        }
    }

    /// @dev Allow change in the prices
    /// @param newPrice new price in ETH
    function setPrice(uint256 newPrice) 
        external
        onlyOwner
    {
        mercenaryPrice = newPrice;
        emit SetPrice(_msgSender(), newPrice);
    }

    /// @dev Allow change in the prices
    /// @param newPrice new price in ETH
    function setTraitPrice(uint256 newPrice) 
        external
        onlyOwner
    {
        traitPrice = newPrice;
        emit SetTraitPrice(_msgSender(), newPrice);
    }

    /// @dev Withdraw ETH
    function withdrawAll()
        external
        payable
        onlyOwner
    {
        payable(_msgSender()).transfer(address(this).balance);
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

    fallback() external payable { }
    
    receive() external payable { }

// INTERNAL FUNCTIONS

    /// @dev Flag index as claimed
    /// @param index of address
    function _setClaimed(uint256 index)
        private 
    {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

//VIEWS

    /// @dev Check if index has been claimed
    /// @param index of address
    function isClaimed(uint256 index)
        public
        view
        returns (bool) 
    {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    /// @dev Check a allowlist address for unclaimed pack
    /// @param account address to check for allowlist
    function getAllowlistIndex(address account)
        external
        view
        returns (
            bool unclaimed,
            uint256 index)
    {
        // Get the current allowlist array index
        uint256 total = allowlist.length;
        if (total == 0 ) {
            return (false, 0);
        } else {
            // Loop through the addresses
            for(uint256 i=0; i < total;){
                // If account matches and unclaimed
                if ( allowlist[i].account == account && !allowlist[i].claimed) {
                    return (true,i);
                }
                unchecked { i++; }
            }
        }
    }

}
