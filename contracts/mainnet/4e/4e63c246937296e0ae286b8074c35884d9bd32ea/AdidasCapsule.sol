// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./IERC721.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./ERC2981.sol";
import "./DefaultOperatorFilterer.sol";
import {IOperatorFilterRegistry} from "./IOperatorFilterRegistry.sol";

interface ITMAirdrop {
    function burn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract AdidasCapsule is ERC721, ERC721Enumerable, ERC2981, Ownable, DefaultOperatorFilterer {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private supply;

    string public baseUri = "";
    string public uriSuffix = ".json";

    // Token name
    string private _name;
    // Token symbol
    string private _symbol;
    // V1 contract address
    address private v1Contract;

    constructor(string memory __name, string memory __symbol, address _address, string memory _baseUri, string memory _uriSuffix) ERC721(__name, __symbol) {
        _name = __name;
        _symbol = __symbol;
        v1Contract = _address;
        baseUri = _baseUri;
        uriSuffix = _uriSuffix;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function setNameAndSymbol(string memory __name, string memory __symbol) public onlyOwner {
        _name = __name;
        _symbol = __symbol;
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory currentBaseURI = _baseURI();
        return string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix));
    }

    function burn(uint256 _tokenId) public {
        require(msg.sender == ownerOf(_tokenId), "Only token owner can burn");
        _burn(_tokenId);
    }

    // Burns and Mints, also requires Approval
    function burnToMint(uint256[] memory _tokenIds) public {
        for (uint256 i; i<_tokenIds.length;) {
            ITMAirdrop(v1Contract).burn(_tokenIds[i]);
            _safeMint(msg.sender, _tokenIds[i]);
            unchecked{
               i++;
            }
        }    
    }

    // Token Ownership
    function walletOfCapsuleOwner(address _owner, uint256 _startingIndex, uint256 _endingIndex) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = ITMAirdrop(v1Contract).balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        uint256 currentTokenId = _startingIndex;
        uint256 ownedTokenIndex = 0;

        uint256 capsuleSupply = _endingIndex;

        if (ownerTokenCount > 0) {
            while (ownedTokenIndex < ownerTokenCount && currentTokenId < capsuleSupply) {
                try ITMAirdrop(v1Contract).ownerOf(currentTokenId) returns (address currentTokenOwner) {
                    if (currentTokenOwner == _owner) {
                        ownedTokenIds[ownedTokenIndex] = currentTokenId;
                        unchecked {
                            ownedTokenIndex++;
                        }
                    }
                } catch {
                    // Do nothing for now
                }
                unchecked {
                    currentTokenId++;
                }
            }
        } 
        return ownedTokenIds;
    }

    function walletOfOwner(address _owner) public view returns (uint256[] memory){
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i<ownerTokenCount;){
            ownedTokenIds[i] = tokenOfOwnerByIndex(_owner, i);
            unchecked {
                i++;
            }
        }
        return ownedTokenIds;
    }

    // URI methods
    function _baseURI() internal view virtual override returns (string memory) {
        return baseUri;
    }

    function setBaseUri(string memory _baseUri) public onlyOwner {
        baseUri = _baseUri;
    }

    function setUriSuffix(string memory _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    // Operator Registry Controls
    function setOperatorFilterRegistry(address _registry) public onlyOwner {
        operatorFilterRegistry = IOperatorFilterRegistry(_registry);
    }

    function updateOperator(address _operator, bool _filtered) public onlyOwner {
        operatorFilterRegistry.updateOperator(address(this), _operator, _filtered);
    }

    // Royalities
    function setRoyalties(address recipient, uint96 value) public onlyOwner {
        _setDefaultRoyalty(recipient, value);
    }

    // @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Registry Validated Transfers 
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId 
    )
        internal
        virtual
        override(ERC721,ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }
}
