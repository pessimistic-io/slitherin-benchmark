// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Strings.sol";
import "./Base64.sol";
import "./WrappedCharacters.sol";

contract Mercenaries is WrappedCharacters {
    using Strings for uint256;

    constructor (
        string memory _initialBaseURI
    )
    WrappedCharacters("Farmland Mercenaries", "MERCENARIES") {
        // Set the starting BaseURI
        baseURI = _initialBaseURI;
    }

// STATE VARIABLES

    /// @dev For tracking the mercenaries visual traits
    mapping (uint256 => bytes16[]) public visualTraits;
    
// EVENTS

    event MercenaryMinted(address indexed account, uint256 indexed tokenID, bytes16[] traits);
    event MercenaryTraitsUpdated(address indexed account, uint256 indexed tokenID, bytes16[] traits);

// FUNCTIONS

    /// @dev Allow an external contract to mint a mercenary
    /// @dev Enables giveaways to supportive community members
    /// @dev Enables external contracts with permission to mint mercenaries for promotions
    /// @param to recipient
    /// @param traits an array representing the mercenaries traits e.g., ["blue hat","brown eyes]
    function mint(address to, bytes16[] calldata traits)
        external
        nonReentrant
        onlyAllowed
    {
        // Increment wrapped token id
        unchecked { totalTokens++; }
        // Store the totalTokens as a local variable
        uint256 tokenID = totalTokens;
        // Write an event
        emit MercenaryMinted(to, tokenID, traits);
        // Set the stats
        _storeStats(address(this),tokenID);
        // Calculate the underlying token hash
        bytes32 wrappedTokenHash = hashWrappedToken(address(this), tokenID);
        // Add Collection address to the mapping
        wrappedToken[wrappedTokenHash].collectionAddress = address(this);
        // Add Token ID to the mapping
        wrappedToken[wrappedTokenHash].wrappedTokenID = tokenID;
        // Map the underlying token hash to the wrapped token id
        wrappedTokenHashByID[tokenID] = wrappedTokenHash;
        // Add Visual Traits for mercenary
        visualTraits[tokenID] = traits;
        // Mint the Mercenaries
        _mint(to, tokenID);
    }

    /// @dev Replace traits
    /// @param tokenID of mercenary
    /// @param traits an array representing the mercenaries traits e.g., [7,2,5,1,1]
    function updateTraits(uint256 tokenID, bytes16[] calldata traits)
        external
        nonReentrant
        onlyAllowed
        onlyExists(tokenID)
    {
        // Write an event
        emit MercenaryTraitsUpdated(_msgSender(), tokenID, traits);
        // Replace Visual Traits for mercenary
        visualTraits[tokenID] = traits;
    }

// VIEWS

    /// @dev Return the token onchain metadata
    /// @param tokenID Identifies the asset
    function tokenURI(uint256 tokenID)
        public
        view
        virtual
        override(ERC721)
        onlyExists(tokenID)
        returns (string memory uri) 
    {
        (address collectionAddress,uint256 wrappedTokenID,) = getWrappedTokenDetails(tokenID);
        if (collectionAddress == address(this)) {
            bytes32 wrappedTokenHash = hashWrappedToken(collectionAddress, wrappedTokenID);
            uint256 level = getLevel(tokenID);
            string memory _url = ERC721.tokenURI(tokenID);
            string memory url = string(abi.encodePacked(_url,".png"));
            string memory mercenaryName = string(abi.encodePacked("Mercenary #",Strings.toString(tokenID)));
            string memory json1 = string(abi.encodePacked(
                '{',
                '"name": "', mercenaryName, '",',
                '"description": "Mercenaries are available to hire for various activities",',
                '"image": "', url, '",',
                '"seller_fee_basis_points": 100,',
                '"fee_recipient": "0xC74956f14b1C0F5057404A8A26D3074924545dF8",',
                '"attributes": [',
                '{ "id": 0, "trait_type": "Level", "value": "'      ,Strings.toString(level),    '" },'
            ));
            string memory output = Base64.encode(abi.encodePacked(json1, encodeTraits(tokenID), encodeStats(wrappedTokenHash)));
            return string(abi.encodePacked('data:application/json;base64,', output));   // Return the result
        } else {
            return IERC721Metadata(collectionAddress).tokenURI(wrappedTokenID);
        }
    }

    function encodeTraits(uint256 tokenID)
        internal
        view
        returns (string memory)
    {
        bytes16[] memory traits = visualTraits[tokenID];
        string memory json1 = string(abi.encodePacked(
            '{ "id": 0, "trait_type": "Background", "value": "' ,_bytes16ToString(traits[0]), '" },',
            '{ "id": 0, "trait_type": "Base", "value": "'       ,_bytes16ToString(traits[1]), '" },',
            '{ "id": 0, "trait_type": "Gender", "value": "'     ,_bytes16ToString(traits[2]), '" },',
            '{ "id": 0, "trait_type": "Hair", "value": "'       ,_bytes16ToString(traits[3]), '" },'
        ));
        string memory json2 = string(abi.encodePacked(
            '{ "id": 0, "trait_type": "Eyes", "value": "'       ,_bytes16ToString(traits[4]), '" },',
            '{ "id": 0, "trait_type": "Mouth", "value": "'      ,_bytes16ToString(traits[5]), '" },',
            '{ "id": 0, "trait_type": "Clothing", "value": "'   ,_bytes16ToString(traits[6]), '" },',
            '{ "id": 0, "trait_type": "Feature", "value": "'    ,_bytes16ToString(traits[7]), '" },'
        ));
        return string(abi.encodePacked(json1, json2));   // Return the result
    }

    function encodeStats(bytes32 wrappedTokenHash)
        internal
        view
        returns (string memory)
    {
        uint16[] memory stat = stats[wrappedTokenHash];
        string memory json1 = string(abi.encodePacked(
            '{ "id": 0, "trait_type": "Stamina", "value": "'        ,Strings.toString(stat[0]), '" },',
            '{ "id": 0, "trait_type": "Strength", "value": "'       ,Strings.toString(stat[1]), '" },',
            '{ "id": 0, "trait_type": "Speed", "value": "'          ,Strings.toString(stat[2]), '" },',
            '{ "id": 0, "trait_type": "Courage", "value": "'        ,Strings.toString(stat[3]), '" },'
        ));
        string memory json2 = string(abi.encodePacked(
            '{ "id": 0, "trait_type": "Intelligence", "value": "'   ,Strings.toString(stat[4]), '" },',
            '{ "id": 0, "trait_type": "Health", "value": "'         ,Strings.toString(stat[5]), '" },',
            '{ "id": 0, "trait_type": "Morale", "value": "'         ,Strings.toString(stat[6]), '" },',
            '{ "id": 0, "trait_type": "Experience", "value": "'     ,Strings.toString(stat[7]), '" }',
            ']',
            '}'
        ));
        return string(abi.encodePacked(json1, json2));   // Return the result
    }

    function _bytes16ToString(bytes16 toConvert) 
        private
        pure
        returns (string memory) 
    {
        uint8 i = 0;
        while(i < 16 && toConvert[i] != 0) {
            unchecked { i++; }
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 16 && toConvert[i] != 0;) {
            bytesArray[i] = toConvert[i];
            unchecked { i++; }
        }
        return string(bytesArray);
    }

    function _baseURI() 
        internal
        view
        override(ERC721)
        returns (string memory)
    {
        return baseURI;
    }

    /// @dev Check if token is a mercenary
    /// @param tokenID Identifies the asset
    function isMercenary(uint256 tokenID)
        external
        view
        onlyExists(tokenID)
        returns (bool mercenary)
    {
        (address collectionAddress,,) = getWrappedTokenDetails(tokenID);
        if (collectionAddress == address(this)) {return true;}
    }

    /// @dev Check if mercenary is a wrapped citizen
    /// @param tokenID Identifies the asset
    function isCitizen(uint256 tokenID)
        external
        view
        onlyExists(tokenID)
        returns (bool citizen)
    {
        (address collectionAddress,,) = getWrappedTokenDetails(tokenID);
        if (characterCollections[collectionAddress].native && collectionAddress != address(this)) {return true;}
    }

    /// @dev The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721)
    {
        super._beforeTokenTransfer(from, to, tokenId);
        // Revert if the mercenary is active
        require(!charactersActivity[tokenId].active, "Mercenary is active");
    }

}
