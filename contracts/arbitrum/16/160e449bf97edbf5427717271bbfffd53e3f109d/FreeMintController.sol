// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC721Rails} from "./IERC721Rails.sol";
import {IPermissions} from "./IPermissions.sol";
import {Operations} from "./Operations.sol";
// module utils
import {SetupController} from "./SetupController.sol";
import {PermitController} from "./PermitController.sol";
import {FeeController} from "./FeeController.sol";

/// @title Station Network FreeMintController Contract
/// @author symmetry (@symmtry69), frog (@0xmcg), 👦🏻👦🏻.eth
/// @dev Provides a modular contract to handle collections who wish for their membership mints to be
/// free of charge, save for Station Network's base fee

contract FreeMintController is SetupController, PermitController, FeeController {
    /*=============
        STORAGE
    =============*/

    /// @dev collection => permits disabled, permits are enabled by default
    mapping(address => bool) internal _disablePermits;

    /*============
        EVENTS
    ============*/

    /// @dev Events share names but differ in parameters to differentiate them between controllers
    event SetUp(address indexed collection, bool indexed enablePermits);

    /*============
        CONFIG
    ============*/

    /// @param _newOwner The owner of the FeeControllerV2, an address managed by Station Network
    /// @param _feeManager The FeeManager's address
    constructor(address _newOwner, address _feeManager) PermitController() FeeController(_newOwner, _feeManager) {}

    /// @dev Function to set up and configure a new collection
    /// @param collection The new collection to configure
    /// @param enablePermits A boolean to represent whether this collection will repeal or support grant functionality
    function setUp(address collection, bool enablePermits) public canSetUp(collection) {
        if (_disablePermits[collection] != !enablePermits) {
            _disablePermits[collection] = !enablePermits;
        }
        emit SetUp(collection, enablePermits);
    }

    /// @dev convenience function for setting up when creating collections, relies on auth done in public setUp
    function setUp(bool enablePermits) external {
        setUp(msg.sender, enablePermits);
    }

    /*==========
        MINT
    ==========*/

    /// @dev Function to mint a single collection token to the caller, ie a user
    function mint(address collection) external payable {
        _batchMint(collection, msg.sender, 1);
    }

    /// @dev Function to mint a single collection token to a specified recipient
    function mintTo(address collection, address recipient) external payable {
        _batchMint(collection, recipient, 1);
    }

    /// @dev Function to mint collection tokens in batches to the caller, ie a user
    /// @notice returned tokenId range is inclusive
    function batchMint(address collection, uint256 amount) external payable {
        _batchMint(collection, msg.sender, amount);
    }

    /// @dev Function to mint collection tokens in batches to a specified recipient
    /// @notice returned tokenId range is inclusive
    function batchMintTo(address collection, address recipient, uint256 amount) external payable {
        _batchMint(collection, recipient, amount);
    }

    /*===============
        INTERNALS
    ===============*/

    /// @dev Internal function to which all external user + client facing batchMint functions are routed.
    /// @param collection The token collection to mint from
    /// @param recipient The recipient of successfully minted tokens
    /// @param quantity The quantity of tokens to mint
    function _batchMint(address collection, address recipient, uint256 quantity)
        internal
        usePermits(_encodePermitContext(collection))
    {
        require(quantity > 0, "ZERO_AMOUNT");

        // calculate fee, require fee sent to this contract, transfer collection's revenue to payoutAddress
        // for free mints there is no payoutAddress && payment token is network token
        _collectFeeAndForwardCollectionRevenue(collection, address(0), address(0), recipient, quantity, 0);

        // mint NFTs
        IERC721Rails(collection).mintTo(recipient, quantity);
    }

    /*=============
        PERMITS
    =============*/

    function _encodePermitContext(address collection) internal pure returns (bytes memory context) {
        return abi.encode(collection);
    }

    function _decodePermitContext(bytes memory context) internal pure returns (address collection) {
        return abi.decode(context, (address));
    }

    function signerCanPermit(address signer, bytes memory context) public view override returns (bool) {
        address collection = _decodePermitContext(context);
        return IPermissions(collection).hasPermission(Operations.MINT_PERMIT, signer);
    }

    function requirePermits(bytes memory context) public view override returns (bool) {
        address collection = _decodePermitContext(context);
        return !_disablePermits[collection];
    }
}

