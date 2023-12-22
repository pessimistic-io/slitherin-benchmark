// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./Strings.sol";
import { IProxyRegistry } from "./IProxyRegistry.sol";


contract TarsilaNft is Ownable, ERC721Enumerable {
    using Strings for uint256;

    uint256[] private _randomNumbers;
    uint256[] public metadataIds;
    string public baseUri;

    IProxyRegistry public immutable proxyRegistry;

    event TokensCreated(uint256[] tokenIds, address indexed owner);

    event TokenCreated(uint256 indexed tokenId, address indexed owner);

    event TokenBurned(uint256 indexed tokenId);

    constructor(address owner, IProxyRegistry _proxyRegistry) ERC721("Tarsila Reimagined", "TDA") {
        _transferOwnership(owner);
        proxyRegistry = _proxyRegistry;
        baseUri = "https://api.zeitls.io/tarsila/variations/";

        for(uint i = 1; i <= 225; i++) {
            _randomNumbers.push(i);
        }
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
        emit TokenBurned(tokenId);
    }

    function ownerMint(address target, uint tokenId) external onlyOwner {
        require(totalSupply() < 225, "Max supply reached");
        _safeMint(target, tokenId);
       emit TokenCreated(tokenId, target);
    }

    function mint(address target) external {
        require(totalSupply() < 225, "Max supply reached");
        // get the random number, divide it by our array size and store the mod of that division.
        // this is to make sure the generated random number fits into our required range
        uint256 randomIndex = random() % _randomNumbers.length;

        // draw the current random number by taking the value at the random index
        uint256 tokenId = _randomNumbers[randomIndex];

        // write the last number of the array to the current position.
        // thus we take out the used number from the circulation and store the last number of the array for future use
        _randomNumbers[randomIndex] = _randomNumbers[_randomNumbers.length - 1];
        // reduce the size of the array by 1 (this deletes the last record we’ve copied at the previous step)
        _randomNumbers.pop();

        _safeMint(target, tokenId);

        emit TokenCreated(tokenId, target);
    }

    function mintBulk(address target, uint256 count) external {
        require(count > 0, "Invalid amount");
        require(totalSupply() + count <= 225, "Invalid token count");
        uint256[] memory tokenIds = new uint256[](count);
        for (uint i = 0; i < tokenIds.length; i++) {
            // get the random number, divide it by our array size and store the mod of that division.
            // this is to make sure the generated random number fits into our required range
            uint256 randomIndex = random() % _randomNumbers.length;

            // draw the current random number by taking the value at the random index
            uint256 tokenId = _randomNumbers[randomIndex];

            // write the last number of the array to the current position.
            // thus we take out the used number from the circulation and store the last number of the array for future use
            _randomNumbers[randomIndex] = _randomNumbers[_randomNumbers.length - 1];
            // reduce the size of the array by 1 (this deletes the last record we’ve copied at the previous step)
            _randomNumbers.pop();

            _safeMint(target, tokenId);
            tokenIds[i] = tokenId;
        }
        emit TokensCreated(tokenIds, target);
    }

    function exists(uint tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function random() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            tx.origin,
            blockhash(block.number - 1),
            block.timestamp,
            msg.sender,
            totalSupply()
        )));
    }

    function isApprovedForAll(address owner, address operator) public view override(IERC721, ERC721) returns (bool) {
        // Whitelist OpenSea proxy contract for easy trading.
        if (address(proxyRegistry) != address(0x0) && proxyRegistry.proxies(owner) == operator) {
            return true;
        }
        return super.isApprovedForAll(owner, operator);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function setBaseUri(string memory newBaseUri) external onlyOwner {
        baseUri = newBaseUri;
    }

    function withdrawERC20(IERC20 _tokenContract) external onlyOwner {
        uint256 balance = _tokenContract.balanceOf(address(this));
        require(balance > 0, "Nothing to withdraw");
        _tokenContract.transfer(msg.sender, balance);
    }

    function approveERC721(IERC721 _tokenContract) external onlyOwner {
        _tokenContract.setApprovalForAll(msg.sender, true);
    }
}
