// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC721AUpgradeable} from "./ERC721AUpgradeable.sol";
import {UUPSUpgradeable} from "./utils_UUPSUpgradeable.sol";
import {SafeOwnableUpgradeable} from "./utils_SafeOwnableUpgradeable.sol";
import {Registry} from "./Registry.sol";
import {CommonError} from "./CommonError.sol";

contract DegenShovel is
    SafeOwnableUpgradeable,
    UUPSUpgradeable,
    ERC721AUpgradeable
{
    event BaseURISet(string);

    Registry public registry;
    string private _baseURI_;

    uint256[48] private _gap;

    function initialize(
        string calldata name_,
        string calldata symbol_,
        address owner_, // upgrade owner
        address registry_
    ) public initializerERC721A initializer {
        if (owner_ == address(0) || registry_ == address(0)) {
            revert CommonError.ZeroAddressSet();
        }

        __ERC721A_init(name_, symbol_);
        __Ownable_init_unchained(owner_);

        registry = Registry(registry_);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function mint(
        address to,
        uint256 quantity
    ) external onlyPortal returns (uint256 startTokenId) {
        startTokenId = _nextTokenId();
        _mint(to, quantity);
    }

    function burn(uint256 tokenId) external onlyPortal {
        // burn directly and dismiss approve check as it's only called by portal
        _burn(tokenId);
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        _baseURI_ = uri;
        emit BaseURISet(uri);
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        return string(abi.encodePacked(_baseURI_, _toString(tokenId), ".json"));
    }

    // tokenId start from 1
    function _startTokenId() internal view override returns (uint256) {
        return 1 + (block.chainid * 1e18);
    }

    function _checkSigner() internal view {
        if (!registry.checkIsSigner(msg.sender)) {
            revert CommonError.NotSigner();
        }
    }

    modifier onlySigner() {
        _checkSigner();
        _;
    }

    modifier onlyPortal() {
        if (msg.sender != address(registry.getPortal())) {
            revert CommonError.NotPortal();
        }
        _;
    }
}

