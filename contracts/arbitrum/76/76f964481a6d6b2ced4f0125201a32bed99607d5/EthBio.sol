// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./ERC721Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./Counters.sol";
import "./AppURI.sol";
import "./ContractMetadata.sol";

contract EthBio is ERC721Enumerable, ERC721URIStorage, ERC721Burnable, Pausable, AppURI, ContractMetadata, Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    mapping(string => address) public usernames;
    mapping(address => string) public addresses;

    /* ERC721-related overrides */
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    // Remember to implement the access control function
    function _canSetContractURI() internal view override onlyOwner returns (bool) {
        // example implementation:
        return true;
    }

    // Remember to implement the access control function
    function _canSetAppURI() internal view override onlyOwner returns (bool) {
        // example implementation:
        return true;
    }


    /* Helper functions */
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
            // Uppercase character...
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                // So we add 32 to make it lowercase
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    function createUsername(string memory username) internal {
        require(bytes(username).length > 0, "Username can not be empty");
        string memory lower = _toLower(username);
        require(usernames[lower] == address(0), "Username has already been claimed");
        usernames[lower] = _msgSender();
        addresses[_msgSender()] = lower;
    }

    /* External APIs */
    function getBio(address owner) public view returns (string memory) {
        if(owner == address(0)){
            owner = _msgSender();
        }
        uint256 balance = balanceOf(owner);
        require(balance > 0, "No token found for address");
        uint256 tokenId = tokenOfOwnerByIndex(owner, 0);
        return tokenURI(tokenId);
    }

    // use this to look up a bio by username directly
    function getBioByUsername(string memory username) external view returns (string memory) {
        return getBio(usernames[username]);
    }

    function updateBio(address owner, string memory uri) public {
        require(owner != address(0), "missing owner address");

        uint256 balance = balanceOf(owner);
        require(balance > 0, "No token found for owner");

        uint256 tokenId = tokenOfOwnerByIndex(owner, 0);
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not owner nor approved");
        _setTokenURI(tokenId, uri);
    }

    function createBio(string memory username, string memory uri) external {
        string memory lower = _toLower(username);
        if (usernames[lower] != address(0)) {
            updateBio(usernames[lower], uri);
            return;
        }

        _tokenIds.increment();
        uint256 newBioId = _tokenIds.current();
        _safeMint(_msgSender(), newBioId);
        _setTokenURI(newBioId, uri);
        usernames[lower] = _msgSender();
        addresses[_msgSender()] = lower;
    }

    constructor() ERC721("Eth.Bio", "BIO") {
        setAppURI("https://eth.bio");
    }
}

