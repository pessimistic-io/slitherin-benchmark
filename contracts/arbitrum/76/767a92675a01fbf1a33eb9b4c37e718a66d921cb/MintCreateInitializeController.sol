// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC6551Registry} from "./ERC6551Registry.sol";
import {IERC6551AccountInitializer} from "./IERC6551AccountInitializer.sol";
import {IERC721Rails} from "./IERC721Rails.sol";
import {IERC721} from "./IERC721.sol";
import {IPermissions} from "./IPermissions.sol";
import {Operations} from "./Operations.sol";
// module utils
import {PermitController} from "./PermitController.sol";
import {SetupController} from "./SetupController.sol";
import {ERC6551AccountController} from "./ERC6551AccountController.sol";
import {IAccountGroup} from "./IAccountGroup.sol";

contract MintCreateInitializeController is PermitController, SetupController, ERC6551AccountController {
    struct MintParams {
        address collection;
        address recipient;
        address registry;
        address accountProxy;
        bytes32 salt;
    }

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

    constructor() PermitController() {}

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

    /// @dev Mint a single ERC721Rails token and create+initialize its tokenbound account
    function mintAndCreateAccount(MintParams calldata mintParams)
        external
        usePermits(_encodePermitContext(mintParams.collection))
        returns (address account, uint256 newTokenId)
    {
        address accountGroup = address(bytes20(mintParams.salt));
        address accountImpl = IAccountGroup(accountGroup).getDefaultAccountImplementation();
        require(accountImpl.code.length > 0);

        newTokenId = IERC721Rails(mintParams.collection).mintTo(mintParams.recipient, 1);
        account = _createAccount(
            mintParams.registry,
            mintParams.accountProxy,
            mintParams.salt,
            block.chainid,
            mintParams.collection,
            newTokenId
        );
        _initializeAccount(account, accountImpl, bytes(""));
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

    function requirePermits(bytes memory context) public view override returns (bool) {
        address collection = _decodePermitContext(context);
        return
            !_disablePermits[collection] && !IPermissions(collection).hasPermission(Operations.MINT_PERMIT, msg.sender);
    }

    function signerCanPermit(address signer, bytes memory context) public view override returns (bool) {
        address collection = _decodePermitContext(context);
        return IPermissions(collection).hasPermission(Operations.MINT_PERMIT, signer);
    }
}

