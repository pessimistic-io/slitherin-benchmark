// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Base64.sol";

/// @title Ethereum Breakfast Sandwich
/// @author cryptodollarmenu.com
/// @notice A $ETH Breakfast Sandwich can be staked to earn $CDM.
contract EthereumBreakfastSandwich is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    /// @notice The price of one Breakfast Sandwich.
    uint256 private price = 10000000000000000; // 0.01 Ether

    /// @notice The maximum number of Breakfast Sandwiches available for minting.
    uint256 public constant MAX_TOKENS = 10_000;

    /// @notice The maximum number of Breakfast Sandwiches that can be purchased per transaction.
    uint256 public constant MAX_PER_PURCHASE = 1;

    /// @notice A mapping of an address to a boolean indicating whether that address has acquired a Breakfast Sandwich.
    /// @dev This value is not unset at any point to avoid multiple purchases per address.
    mapping(address => bool) public activeWallet;

    /// @notice Create the Breakfast Sandwich contract.
    constructor() ERC721("Ethereum Breakfast Sandwich", "EBS") Ownable() {}

    /// @notice Enter your wallet address to see which Breakfast Sandwiches you own.
    /// @param _owner The wallet address of a Breakfast Sandwich token owner.
    /// @return An array of the Breakfast Sandwich tokenIds owned by the address.
    function tokensOfOwner(address _owner) external view returns(uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    /// @notice Mint a Breakfast Sandwich.
    function mint(uint256 _count) public payable nonReentrant {
        uint256 totalSupply = totalSupply();
        require(_count > 0 && _count < MAX_PER_PURCHASE + 1);
        require(totalSupply + _count < MAX_TOKENS + 1);
        require(msg.value >= price.mul(_count), "Value sent is not correct");
        require(activeWallet[_msgSender()] == false, "Address is already active");
        for(uint256 i = 0; i < _count; i++){
            _safeMint(_msgSender(), totalSupply + i);
            activeWallet[_msgSender()] = true;
        }
    }

    /// @notice The contract owner can withdraw ETH accumulated in the contract.
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    /// @dev Required override for ERC721Enumerable.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Generates the tokenURI for each Breakfast Sandwich.
    /// @param tokenId The Breakfast Sandwich token for which a URI is to be generated.
    /// @return The tokenURI formatted as a string.
    function tokenURI(uint256 tokenId) public pure override returns (string memory) {
        string memory background = "ipfs://bafkreigteky5inwb4h5ywm274lulvacdsti7vzbex2eslh2lr4dhch4eqa";
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Ethereum Breakfast Sandwich #', toString(tokenId), '", "description": "460 calories. Ingredients: An ERC721 token that features a warm, freshly toasted English muffin topped with a savory hot sausage patty and a slice of melted American cheese. On top of this, we place a freshly cracked Grade A egg. Pair it with our Premium Roast Coffee!", "image": "', background, '"}'))));
        string memory o = string(abi.encodePacked('data:application/json;base64,', json));
        return o;
    }

    /// @dev Required override for ERC721Enumerable.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /// @notice Returns an uint256 value as a string.
    /// @param value The uint256 value to have a type change.
    /// @return A string of the inputted uint256 value.
    function toString(uint256 value) internal pure returns (string memory) {
    // Inspired by OraclizeAPI's implementation - MIT license
    // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

}

