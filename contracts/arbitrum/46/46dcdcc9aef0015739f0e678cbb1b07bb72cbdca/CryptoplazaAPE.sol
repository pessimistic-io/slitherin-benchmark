// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./ERC721.sol";
import "./IERC4906.sol";
import "./ERC721Royalty.sol";
import "./Ownable.sol";

contract CryptoplazaAPE is ERC721Royalty, IERC4906,  Ownable {
    IERC20 public immutable usdcToken;

    string private baseURI;
    uint256 immutable MAX_SUPPLY;
    uint256 private _numAvailableTokens;
    uint96 private royaltyFee;
    mapping(uint => uint) private _availableTokens;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseUri,
        uint96 _royaltyFee,
        uint256 _maxSupply,
        IERC20 _usdcToken
    ) ERC721(_name, _symbol) {
        baseURI = _baseUri;
        MAX_SUPPLY = _maxSupply;
        usdcToken = _usdcToken;
        _numAvailableTokens = _maxSupply;
        royaltyFee = _royaltyFee;
        _setDefaultRoyalty(_msgSender(),  royaltyFee);
    }

    function safeMint(address to) external {
        require(
            _numAvailableTokens != 0,
            "CryptoplazaAPE: Minting limit reached"
        );
        if (_msgSender() != owner()) {
            uint256 mintPrice = getMintPrice();
            require(
                usdcToken.balanceOf(_msgSender()) >= mintPrice,
                "CryptoplazaAPE: Insufficient USDC balance"
            );
            require(
                usdcToken.allowance(_msgSender(), address(this)) >= mintPrice,
                "CryptoplazaAPE: Insufficient USDC allowance"
            );
            bool success = usdcToken.transferFrom(
                _msgSender(),
                owner(),
                mintPrice
            );
            require(success, "CryptoplazaAPE: USDC transfer failed");
        }

        _mintRandom(to);

        emit BatchMetadataUpdate(0,MAX_SUPPLY);
    }

    function _mintRandom(address to) internal virtual {
        uint updatedNumAvailableTokens = _numAvailableTokens;
        uint256 tokenId = getRandomAvailableTokenId(
            to,
            updatedNumAvailableTokens
        );
        _safeMint(to, tokenId);
        --updatedNumAvailableTokens;
        _numAvailableTokens = updatedNumAvailableTokens;
    }

    function getRandomAvailableTokenId(
        address to,
        uint updatedNumAvailableTokens
    ) internal returns (uint256) {
        uint256 randomNum = uint256(
            keccak256(
                abi.encode(
                    to,
                    tx.gasprice,
                    block.number,
                    block.timestamp,
                    blockhash(block.number - 1),
                    address(this),
                    updatedNumAvailableTokens
                )
            )
        );
        uint256 randomIndex = randomNum % updatedNumAvailableTokens;
        return getAvailableTokenAtIndex(randomIndex, updatedNumAvailableTokens);
    }

    // Implements https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle. Code taken from CryptoPhunksV2
    function getAvailableTokenAtIndex(
        uint256 indexToUse,
        uint updatedNumAvailableTokens
    ) internal returns (uint256) {
        uint256 valAtIndex = _availableTokens[indexToUse];
        uint256 result;
        if (valAtIndex == 0) {
            // This means the index itself is still an available token
            result = indexToUse;
        } else {
            // This means the index itself is not an available token, but the val at that index is.
            result = valAtIndex;
        }

        uint256 lastIndex = updatedNumAvailableTokens - 1;
        uint256 lastValInArray = _availableTokens[lastIndex];
        if (indexToUse != lastIndex) {
            // Replace the value at indexToUse, now that it's been used.
            // Replace it with the data from the last index in the array, since we are going to decrease the array size afterwards.
            if (lastValInArray == 0) {
                // This means the index itself is still an available token
                _availableTokens[indexToUse] = lastIndex;
            } else {
                // This means the index itself is not an available token, but the val at that index is.
                _availableTokens[indexToUse] = lastValInArray;
            }
        }
        if (lastValInArray != 0) {
            // Gas refund courtsey of @dievardump
            delete _availableTokens[lastIndex];
        }

        return result;
    }

    function getMintPrice() public view returns (uint256) {
        if (MAX_SUPPLY - _numAvailableTokens < 10) {
            return 5000e6;
        } else if (MAX_SUPPLY - _numAvailableTokens < 40) {
            return 7500e6;
        } else if (MAX_SUPPLY - _numAvailableTokens < 50) {
            return 10000e6;
        } else {
            return 15000e6;
        }
    }

    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
        emit BatchMetadataUpdate(0,MAX_SUPPLY);
    }

    function setNewRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function emitUpdateEvent(uint256 tokenId) public {
         emit MetadataUpdate(tokenId);
    }

    function totalSupply() public view virtual returns (uint256) {
        return MAX_SUPPLY - _numAvailableTokens;
    }

    function maxSupply() public view virtual returns (uint256) {
        return MAX_SUPPLY;
    }

    // The following functions are overrides

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _burn(uint256 tokenId) internal override {
        super._burn(tokenId);
    }

    function _transferOwnership(address newOwner) internal override {
        _setDefaultRoyalty(newOwner,  royaltyFee);
        super._transferOwnership(newOwner);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Royalty, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}

