// SPDX-License-Identifier: GPL-2.0-or-later
// (C) Florence Finance, 2023 - https://florence.finance/
pragma solidity 0.8.17;

import "./ONFT721Upgradeable.sol";
import "./CountersUpgradeable.sol";

contract DukeNFT is Initializable, ONFT721Upgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /// @notice The starting value for token IDs.
    uint256 public tokenIdRangeStart;

    /// @notice The ending value for token IDs.
    uint256 public tokenIdRangeEnd;

    /// @notice Counter for generating new token IDs.
    CountersUpgradeable.Counter public _tokenIdCounter;

    /// @notice Mapping of token IDs to their properties.
    mapping(uint256 => TokenProperties) public tokenProperties;

    /// @notice Mapping of addresses to whether they have minted a token.
    mapping(address => bool) public hasMinted;

    /// @notice The base URI for the token metadata.
    string public baseURI;

    /// @dev Struct to hold token properties.
    struct TokenProperties {
        uint256 referrerTokenId;
        uint256[50] __gap;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract.
     * @param _tokenIdRangeStart The start of the token ID range.
     * @param _tokenIdRangeEnd The end of the token ID range.
     * @param _lzEndpoint LayerZero endpoint for ONFT.
     * @param _minGasToTransfer Minimum gas required for transferring ONFT.
     */
    function initialize(uint256 _tokenIdRangeStart, uint256 _tokenIdRangeEnd, address _lzEndpoint, uint256 _minGasToTransfer, string calldata baseURI_) public initializer {
        __ONFT721Upgradeable_init("Duke Of Florence Finance", "DUKE", _minGasToTransfer, _lzEndpoint);
        tokenIdRangeStart = _tokenIdRangeStart;
        tokenIdRangeEnd = _tokenIdRangeEnd;
        _tokenIdCounter._value = _tokenIdRangeStart;
        baseURI = baseURI_;
    }

    /// @dev Returns the base URI for the token metadata.
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /// @dev Sets the base URI for the token metadata.
    /// @param baseURI_ the base URI to set.
    function setBaseURI(string calldata baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    /// @dev Function to safely mint a token within the chains designated ID range.
    function safeMintTo(address to, uint256 referrerTokenId) public {
        require(!hasMinted[_msgSender()], "DukeNFT: address has already minted");
        hasMinted[_msgSender()] = true;
        uint256 tokenId = _tokenIdCounter.current();
        require(tokenId >= tokenIdRangeStart && tokenId <= tokenIdRangeEnd, "DukeNFT: tokenId out of bounds");
        _tokenIdCounter.increment();
        tokenProperties[tokenId].referrerTokenId = referrerTokenId;
        _safeMint(to, tokenId);
    }

    /// @notice Mints a new token to the sender.
    function safeMint(uint256 referrerTokenId) external {
        safeMintTo(_msgSender(), referrerTokenId);
    }

    /// @dev Checks if the contract supports a given interface.
    function supportsInterface(bytes4 interfaceId) public view override(ONFT721Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Retrieves the score of a token.
    /// @param tokenId The ID of the token.
    function getReferrerTokenId(uint256 tokenId) public view returns (uint256) {
        return tokenProperties[tokenId].referrerTokenId;
    }

    /// @notice Retrieves the next available token ID.
    function getNextTokenId() external view returns (uint256) {
        return _tokenIdCounter.current();
    }
}

