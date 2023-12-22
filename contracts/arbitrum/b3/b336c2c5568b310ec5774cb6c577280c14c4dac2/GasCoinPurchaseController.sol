// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC721Rails} from "./IERC721Rails.sol";
import {IPermissions} from "./IPermissions.sol";
import {Operations} from "./Operations.sol";

import {SetupController} from "./SetupController.sol";
import {PermitController} from "./PermitController.sol";
import {FeeController} from "./FeeController.sol";
import {PayoutAddressExtension} from "./PayoutAddressExtension.sol";

/// @title Station Network GasCoinPurchaseController Contract
/// @author symmetry (@symmtry69), frog (@0xmcg), 👦🏻👦🏻.eth
/// @dev Provides a modular contract to handle collections who wish for their membership mints to be
/// paid in the native currency of the chain this contract is deployed to

contract GasCoinPurchaseController is SetupController, PermitController, FeeController {
    /*=============
        STORAGE
    =============*/

    /// @dev collection => permits disabled, permits are enabled by default
    mapping(address => bool) internal _disablePermits;
    /// @dev Mapping of collections to their mint's native currency price
    mapping(address => uint256) public prices;

    /*============
        EVENTS
    ============*/

    /// @dev Events share names but differ in parameters to differentiate them between controllers
    event SetUp(address indexed collection, uint256 price, bool indexed enablePermits);

    /*============
        CONFIG
    ============*/

    /// @param _newOwner The owner of the FeeControllerV2, an address managed by Station Network
    /// @param _feeManager The FeeManager's address
    constructor(address _newOwner, address _feeManager) PermitController() FeeController(_newOwner, _feeManager) {}

    /// @dev Function to set up and configure a new collection's purchase prices
    /// @param collection The new collection to configure
    /// @param price The price in this chain's native currency for this collection's mints
    /// @param enablePermits A boolean to represent whether this collection will repeal or support grant functionality
    function setUp(address collection, uint256 price, bool enablePermits) public canSetUp(collection) {
        if (prices[collection] != price) {
            prices[collection] = price;
        }
        if (_disablePermits[collection] != !enablePermits) {
            _disablePermits[collection] = !enablePermits;
        }

        emit SetUp(collection, price, enablePermits);
    }

    /// @dev convenience function for setting up when creating collections, relies on auth done in public setUp
    function setUp(uint256 price, bool enablePermits) external {
        setUp(msg.sender, price, enablePermits);
    }

    /*==========
        MINT
    ==========*/

    /// @dev Function to get a collection's mint price in native currency price
    function priceOf(address collection) public view returns (uint256 price) {
        price = prices[collection];
        require(price > 0, "NO_PRICE");
    }

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
    function batchMint(address collection, uint256 quantity) external payable {
        _batchMint(collection, msg.sender, quantity);
    }

    /// @dev Function to mint collection tokens in batches to a specified recipient
    /// @notice returned tokenId range is inclusive
    function batchMintTo(address collection, address recipient, uint256 quantity) external payable {
        _batchMint(collection, recipient, quantity);
    }

    /*===============
        INTERNALS
    ===============*/

    /// @dev Internal function to which all external user + client facing batchMint functions are routed.
    /// @param collection The token collection to mint from
    /// @param recipient The recipient of successfully minted tokens
    /// @param quantity The quantity of tokens to mint
    /// @notice returned tokenId range is inclusive
    function _batchMint(address collection, address recipient, uint256 quantity)
        internal
        usePermits(_encodePermitContext(collection))
    {
        require(quantity > 0, "ZERO_QUANTITY");

        // prevent accidentally unset payoutAddress
        address payoutAddress = PayoutAddressExtension(collection).payoutAddress();
        require(payoutAddress != address(0), "MISSING_PAYOUT_ADDRESS");

        // reverts if collection has not been setUp()
        uint256 unitPrice = priceOf(collection);

        // calculate fee, require fee sent to this contract, transfer collection's revenue to payoutAddress
        _collectFeeAndForwardCollectionRevenue(collection, payoutAddress, address(0), recipient, quantity, unitPrice);

        // mint NFTs
        IERC721Rails(collection).mintTo(recipient, quantity);
    }

    /*============
        PERMIT
    ============*/

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

