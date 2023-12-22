// SPDX-License-Identifier: BUSL-1.1
// omnisea-contracts v0.1

pragma solidity ^0.8.7;

import "./ERC721URIStorage.sol";
import "./ERC721.sol";
import "./IOmniERC721.sol";
import { CreateParams } from "./ERC721Structs.sol";
import "./Ownable.sol";

/**
 * @title OmniERC721
 * @author Omnisea
 * @custom:version 0.1
 * @notice OmniERC721 is ERC721 contract with mint function restricted for TokenFactory.
 *         The above makes it suited for handling (validation & execution) cross-chain actions.
 */
contract OmniERC721 is IOmniERC721, ERC721URIStorage, Ownable {
    using Strings for uint256;

    event PermanentURI(string _value, uint256 indexed _id);

    string public collectionName;
    uint256 public override createdAt;
    uint256 public override totalSupply;
    address public override creator;
    uint256 public override dropFrom;
    uint256 public dropTo;
    string public collectionURI;
    string public fileURI;
    uint256 public override mintPrice;
    string public override assetName;
    uint256 public override tokenIds;
    mapping (address => uint256[]) public mintedBy;
    address public tokenFactory;
    string public tokensURI;
    string public _notRevealedURI;

    /**
     * @notice Sets the TokenFactory, and creates ERC721 collection contract.
     *
     * @param _symbol A collection symbol.
     * @param params See CreateParams struct in ERC721Structs.sol.
     * @param _creator A collection creator.
     * @param _tokenFactoryAddress Address of the TokenFactory linked with CollectionRepository.
     */
    constructor(
        string memory _symbol,
        CreateParams memory params,
        address _creator,
        address _tokenFactoryAddress
    ) ERC721(params.name, _symbol) {
        tokenFactory = _tokenFactoryAddress;
        creator = _creator;
        tokensURI = params.tokensURI;
        totalSupply = bytes(tokensURI).length > 0 ? params.totalSupply : 0;
        mintPrice = params.price;
        createdAt = block.timestamp;
        collectionName = params.name;
        collectionURI = params.uri;
        assetName = params.assetName;
        fileURI = params.fileURI;
        _setDates(params.from, params.to);
    }

    /**
     * @notice Returns the baseURI for the IPFS-restricted tokenURI creation.
     */
    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://";
    }

    /**
     * @notice Returns contract-level metadata URI.
     */
    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked(_baseURI(), collectionURI));
    }

    /**
     * @notice Returns metadata URI of a specific token.
     *
     * @param tokenId ID of a token.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "!token");

        if (bytes(_notRevealedURI).length > 0) {
            return _notRevealedURI;
        }

        return bytes(tokensURI).length > 0
            ? string(abi.encodePacked(_baseURI(), tokensURI, "/", tokenId.toString(), "/metadata.json"))
            : contractURI();
    }

    /**
     * @notice Mints ERC721 token.
     *
     * @param owner ERC721 token owner.
     */
    function mint(address owner) override external {
        _validateMint();
        tokenIds++;
        _safeMint(owner, tokenIds);
        mintedBy[owner].push(tokenIds);
        emit PermanentURI(tokenURI(tokenIds), tokenIds);
    }

    /**
     * @notice Validates ERC721 token mint.
     */
    function _validateMint() internal view {
        require(msg.sender == tokenFactory);
        if (totalSupply > 0) require(totalSupply > tokenIds);
        if (dropFrom > 0) require(block.timestamp >= dropFrom);
        if (dropTo > 0) require(block.timestamp <= dropTo);
    }

    /**
     * @notice Validates and sets minting dates.
     *
     * @param from Minting start date.
     * @param to Minting end date.
     */
    function _setDates(uint256 from, uint256 to) internal {
        if (from > 0) {
            require(from >= (block.timestamp - 1 days));
            dropFrom = from;
        }
        if (to > 0) {
            require(to > from && to > block.timestamp);
            dropTo = to;
        }
    }

    /**
     * @notice Getter of the tokens minted by the user.
     *
     * @param user User who minted tokens.
     */
    function getMintedBy(address user) public view returns (uint256[] memory) {
        return mintedBy[user];
    }

    /**
     * @notice Sets Metadata URI as non-revealable.
     *
     * @param _uri notRevealedURI.
     */
    function setNotRevealedURI(string memory _uri) external {
        require(msg.sender == creator);
        require(tokenIds == 0, "tokenIds > 0");
        _notRevealedURI = _uri;
    }

    /**
     * @notice Removes notRevealedURI making collection's metadata revealed.
     */
    function reveal() external {
        require(msg.sender == creator);
        _notRevealedURI = "";
    }
}
