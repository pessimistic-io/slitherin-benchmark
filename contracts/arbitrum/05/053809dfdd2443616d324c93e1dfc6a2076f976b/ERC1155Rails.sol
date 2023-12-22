// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Address} from "./Address.sol";

import {Rails} from "./Rails.sol";
import {Ownable, Ownable} from "./Ownable.sol";
import {Access} from "./Access.sol";
import {ERC1155} from "./ERC1155.sol";
import {TokenMetadata} from "./TokenMetadata.sol";
import {     ITokenURIExtension, IContractURIExtension } from "./IMetadataExtensions.sol";
import {Operations} from "./Operations.sol";
import {PermissionsStorage} from "./PermissionsStorage.sol";
import {IERC1155Rails} from "./IERC1155Rails.sol";
import {Initializable} from "./Initializable.sol";

/// @notice This contract implements the Rails pattern to provide enhanced functionality for ERC1155 tokens.
contract ERC1155Rails is Rails, Ownable, Initializable, TokenMetadata, ERC1155, IERC1155Rails {
    /// @notice Declaring this contract `Initializable()` invokes `_disableInitializers()`,
    /// in order to preemptively mitigate proxy privilege escalation attack vectors
    constructor() Initializable() {}

    /// @dev Owner address is implemented using the `Ownable` contract's function
    function owner() public view override(Access, Ownable) returns (address) {
        return Ownable.owner();
    }

    /// @notice Cannot call initialize within a proxy constructor, only post-deployment in a factory
    /// @inheritdoc IERC1155Rails
    function initialize(address owner_, string calldata name_, string calldata symbol_, bytes calldata initData)
        external
        initializer
    {
        _setName(name_);
        _setSymbol(symbol_);
        if (initData.length > 0) {
            /// @dev if called within a constructor, self-delegatecall will not work because this address does not yet have
            /// bytecode implementing the init functions -> revert here with nicer error message
            if (address(this).code.length == 0) {
                revert CannotInitializeWhileConstructing();
            }
            // make msg.sender the owner to ensure they have all permissions for further initialization
            _transferOwnership(msg.sender);
            Address.functionDelegateCall(address(this), initData);
            // if sender and owner arg are different, transfer ownership to desired address
            if (msg.sender != owner_) {
                _transferOwnership(owner_);
            }
        } else {
            _transferOwnership(owner_);
        }
    }

    /*==============
        METADATA
    ==============*/

    /// @dev Function to return the name of a token implementation
    /// @return _ The returned ERC1155 name string
    function name() public view override(ERC1155, TokenMetadata) returns (string memory) {
        return TokenMetadata.name();
    }

    /// @dev Function to return the symbol of a token implementation
    /// @return _ The returned ERC1155 symbol string
    function symbol() public view override(ERC1155, TokenMetadata) returns (string memory) {
        return TokenMetadata.symbol();
    }

    /// @inheritdoc Rails
    function supportsInterface(bytes4 interfaceId) public view override(Rails, ERC1155) returns (bool) {
        return Rails.supportsInterface(interfaceId) || ERC1155.supportsInterface(interfaceId);
    }

    /// @notice Contracts inheriting ERC1155 are required to implement `uri()`
    /// @dev Function to return the ERC1155 uri using extended tokenURI logic
    /// from the `TokenURIExtension` contract
    /// @param tokenId The token ID for which to query a URI
    /// @return _ The returned tokenURI string
    function uri(uint256 tokenId) public view override returns (string memory) {
        // to avoid clashing selectors, use standardized `ext_` prefix
        return ITokenURIExtension(address(this)).ext_tokenURI(tokenId);
    }

    /// @dev Returns the contract URI for this ERC20 token, a modern standard for NFTs
    /// @notice Uses extended contract URI logic from the `ContractURIExtension` contract
    /// @return _ The returned contractURI string
    function contractURI() public view override returns (string memory) {
        // to avoid clashing selectors, use standardized `ext_` prefix
        return IContractURIExtension(address(this)).ext_contractURI();
    }

    /*=============
        SETTERS
    =============*/

    /// @inheritdoc IERC1155Rails
    function mintTo(address recipient, uint256 tokenId, uint256 value) external onlyPermission(Operations.MINT) {
        _mint(recipient, tokenId, value, "");
    }

    /// @inheritdoc IERC1155Rails
    function burnFrom(address from, uint256 tokenId, uint256 value) external {
        if (!hasPermission(Operations.BURN, msg.sender)) {
            _checkCanTransfer(from);
        }
        _burn(from, tokenId, value);
    }

    /*===========
        GUARD
    ===========*/

    /// @dev Hook called before token transfers. Calls into the given guard.
    /// Provides one of three token operations and its accompanying data to the guard.
    function _beforeTokenTransfers(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        view
        override
        returns (address guard, bytes memory beforeCheckData)
    {
        bytes8 operation;
        if (from == address(0)) {
            operation = Operations.MINT;
        } else if (to == address(0)) {
            operation = Operations.BURN;
        } else {
            operation = Operations.TRANSFER;
        }
        bytes memory data = abi.encode(msg.sender, from, to, ids, values);

        return checkGuardBefore(operation, data);
    }

    /// @dev Hook called after token transfers. Calls into the given guard.
    function _afterTokenTransfers(address guard, bytes memory checkBeforeData) internal view override {
        checkGuardAfter(guard, checkBeforeData, ""); // no execution data
    }

    /*===================
        AUTHORIZATION
    ===================*/

    /// @dev Check for `Operations.TRANSFER` permission before ownership and approval
    function _checkCanTransfer(address from) internal virtual override {
        if (!hasPermission(Operations.TRANSFER, msg.sender)) {
            super._checkCanTransfer(from);
        }
    }

    /// @dev Restrict Permissions write access to the `Operations.PERMISSIONS` permission
    function _checkCanUpdatePermissions() internal view override {
        _checkPermission(Operations.PERMISSIONS, msg.sender);
    }

    /// @dev Restrict Guards write access to the `Operations.GUARDS` permission
    function _checkCanUpdateGuards() internal view override {
        _checkPermission(Operations.GUARDS, msg.sender);
    }

    /// @dev Restrict calls via Execute to the `Operations.EXECUTE` permission
    function _checkCanExecuteCall() internal view override {
        _checkPermission(Operations.CALL, msg.sender);
    }

    /// @dev Restrict ERC-165 write access to the `Operations.INTERFACE` permission
    function _checkCanUpdateInterfaces() internal view override {
        _checkPermission(Operations.INTERFACE, msg.sender);
    }

    /// @dev Restrict TokenMetadata write access to the `Operations.METADATA` permission
    function _checkCanUpdateTokenMetadata() internal view override {
        _checkPermission(Operations.METADATA, msg.sender);
    }

    /// @dev Only the `owner` possesses Extensions write access
    function _checkCanUpdateExtensions() internal view override {
        // changes to core functionality must be restricted to owners to protect admins overthrowing
        _checkOwner();
    }

    /// @dev Only the `owner` possesses UUPS upgrade rights
    function _authorizeUpgrade(address) internal view override {
        // changes to core functionality must be restricted to owners to protect admins overthrowing
        _checkOwner();
    }
}

