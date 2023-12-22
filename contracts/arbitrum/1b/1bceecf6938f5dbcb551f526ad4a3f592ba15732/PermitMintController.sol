// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Multicall} from "./Multicall.sol";
import {IERC20Rails} from "./IERC20Rails.sol";
import {IERC721Rails} from "./IERC721Rails.sol";
import {IERC1155Rails} from "./IERC1155Rails.sol";
import {IPermissions} from "./IPermissions.sol";
import {Operations} from "./Operations.sol";
import {PermitController} from "./PermitController.sol";
import {SetupController} from "./SetupController.sol";

/// @title Station PermitMintController Contract
/// @author frog (@0xmcg), 👦🏻👦🏻.eth
/// @dev Mint tokens entirely for free with signature-based authentication
/// @dev Supports all three 0xRails token standard implementations: ERC20, ERC721, ERC1155
/// @notice As this controller is entirely fee-less via enforced permits, it does not make use 
/// of the FeeManager (which charges a baseline default mint fee) nor the permit controller mapping
contract PermitMintController is PermitController, SetupController, Multicall {

    /*==========
        MINT
    ==========*/

    /// @dev Function to mint ERC20 collection tokens to a specified recipient
    /// @notice Can only be called successfully with data signed by a key explicitly granted permission
    /// by an authorized address on the target collection
    function mintToERC20(address collection, address recipient, uint256 amount)
        external
        payable
        usePermits(_encodePermitContext(collection))
    {
        require(amount > 0, "ZERO_AMOUNT");
        IERC20Rails(collection).mintTo(recipient, amount);
    }

    /// @dev Function to mint ERC721 collection tokens to a specified recipient
    /// @notice Can only be called successfully with data signed by a key explicitly granted permission
    /// by an authorized address on the target collection
    function mintToERC721(address collection, address recipient, uint256 amount)
        external
        payable
        usePermits(_encodePermitContext(collection))
    {
        require(amount > 0, "ZERO_AMOUNT");
        IERC721Rails(collection).mintTo(recipient, amount);
    }

    /// @dev Function to mint ERC20 collection tokens to a specified recipient
    /// @notice Can only be called successfully with data signed by a key explicitly granted permission
    /// by an authorized address on the target collection
    function mintToERC1155(address collection, address recipient, uint256 tokenId, uint256 amount)
        external
        payable
        usePermits(_encodePermitContext(collection))
    {
        require(amount > 0, "ZERO_AMOUNT");
        IERC1155Rails(collection).mintTo(recipient, tokenId, amount);
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

    function requirePermits(bytes memory) public pure override returns (bool) {
        return true;
    }
}

