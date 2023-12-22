// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/// @title Stumble Upon Rumble - Boxing Glove
/// @author @whiteoakkong
/// @notice 100% Free Mint. Single Phase. Mapping for allowlist - L2 storage < L1 Calldata. Operator Filterer Enabled for Royalty Control.

import {ERC721A} from "./ERC721A.sol";
import {ERC2981} from "./ERC2981.sol";
import {Ownable2Step} from "./Ownable2Step.sol";
import {Pausable} from "./Pausable.sol";
import {Strings} from "./Strings.sol";
import {DefaultOperatorFilterer} from "./DefaultOperatorFilterer.sol";

contract SURGloves is
    ERC721A("SUR: Boxing Gloves", "GLOVES"),
    Ownable2Step,
    Pausable,
    DefaultOperatorFilterer,
    ERC2981
{
    using Strings for uint256;

    uint256 public maxSupply;

    string public baseURI;
    string private uriExtension;

    mapping(address caller => bool status) public allowed;

    event AllowlistUpdated(address[] addresses, uint256 timestamp);
    event SupplyReduced(uint256 supply, uint256 timestamp);

    constructor(uint256 _maxSupply) {
        maxSupply = _maxSupply;
        togglePause();
    }

    /// @notice Allows users to mint a SUR token.
    /// @dev The function checks that the total minted quantity is less than maxSupply,
    /// the caller is allowed to mint, the caller has not already minted a token, and that the contract is not paused.
    function mint() external whenNotPaused {
        require(_totalMinted() < maxSupply, "Invalid quantity");
        require(allowed[msg.sender], "Invalid minter");
        require(_numberMinted(msg.sender) < 1, "Already minted");
        _mint(msg.sender, 1);
    }

    // ========== ACCESS CONTROLLED ==========

    /// @notice Mints SUR tokens to a specified address.
    /// @dev This function can only be called by the contract owner.
    /// @param quantity The number of tokens to mint.
    /// @param to The address to receive the minted tokens.
    function adminMint(uint256 quantity, address to) external onlyOwner {
        require(_totalMinted() + quantity <= maxSupply, "Invalid quantity");
        _safeMint(to, quantity);
    }

    /// @notice Updates the URI extension.
    /// @dev This function can only be called by the contract owner.
    /// @param _ext The new URI extension.
    function updateExtension(string memory _ext) external onlyOwner {
        uriExtension = _ext;
    }

    /// @notice Sets the baseURI for the contract.
    /// @dev This function can only be called by the contract owner.
    /// @param baseURI_ The new baseURI.
    function setBaseURI(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    /// @notice Sets the default royalty for the SUR tokens.
    /// @dev This function can only be called by the contract owner.
    /// @param recipient The recipient of the royalties.
    /// @param basisPoints The percentage (in basis points) of the royalties.
    function setCollectionRoyalty(address recipient, uint96 basisPoints) external onlyOwner {
        _setDefaultRoyalty(recipient, basisPoints);
    }

    /// @notice Updates the allowlist of minters.
    /// @dev This function can only be called by the contract owner.
    /// @param _addresses The new list of allowed minters.
    function setAllowlist(address[] memory _addresses) external onlyOwner {
        uint256 arrayLength = _addresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            allowed[_addresses[i]] = true;
        }
        emit AllowlistUpdated(_addresses, block.timestamp);
    }

    // ========== UTILITY ==========

    /// @notice Returns the tokenURI of a specific SUR token.
    /// @dev The function checks that the token exists before returning the tokenURI.
    /// @param _tokenId The id of the SUR token.
    /// @return The tokenURI of the SUR token.
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "Token does not exist.");
        return string(abi.encodePacked(baseURI, Strings.toString(_tokenId), uriExtension));
    }

    /// @notice Returns the total number of SUR tokens minted for an address.
    /// @param _address The address to query.
    /// @return The total number of SUR tokens minted for the address.
    function getNumberMinted(address _address) external view returns (uint256) {
        return _numberMinted(_address);
    }

    // ============ OPERATOR-FILTER-OVERRIDES ============

    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public payable override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public payable override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /// @dev Checks whether the contract supports a specific interface.
    /// @param interfaceId The id of the interface.
    /// @return A boolean indicating whether the contract supports the interface.
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A, ERC2981) returns (bool) {
        // Supports the following `interfaceId`s:
        // - IERC165: 0x01ffc9a7
        // - IERC721: 0x80ac58cd
        // - IERC721Metadata: 0x5b5e139f
        // - IERC2981: 0x2a55205a
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    /// @notice Toggles the pause state of the contract.
    /// @dev This function can only be called by the contract owner.
    function togglePause() public onlyOwner {
        bool status = paused();
        if (!status) _pause();
        else _unpause();
    }

    /// @notice Reduce the maxSupply variable to _supply.
    /// @dev This function can only be called by the contract owner.
    /// @param _supply The new maxSupply.
    function reduceSupply(uint256 _supply) external onlyOwner {
        require(_supply <= maxSupply, "Invalid supply");
        maxSupply = _supply;
    }
}

