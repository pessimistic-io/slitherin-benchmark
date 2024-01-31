// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./AccessControl.sol";
import "./Address.sol";
import "./AuthorizeAccess.sol";
import "./OperatorAccess.sol";
import "./INftCollection.sol";

/** @title NftMinter.
 */
contract NftMinter is AuthorizeAccess, OperatorAccess {
    using Address for address;

    uint8 public constant STATUS_NOT_INITIALIZED = 0;
    uint8 public constant STATUS_READY = 1;
    uint8 public constant STATUS_CLOSED = 2;

    uint8 public currentStatus = STATUS_NOT_INITIALIZED;

    uint256 public maxSupply;
    uint256 public availableSupply;

    INftCollection public nftCollection;

    // modifier to allow execution by owner or operator
    modifier onlyOwnerOrOperator() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) || hasRole(OPERATOR_ROLE, _msgSender()),
            "Not an owner or operator"
        );
        _;
    }

    constructor(INftCollection nftCollection_) {
        nftCollection = nftCollection_;
    }

    function setStatus(uint8 status_) external onlyOwnerOrOperator {
        currentStatus = status_;
    }

    function _mint(uint256 quantity, address to) internal {
        require(availableSupply >= quantity, "Not enough supply");
        availableSupply -= quantity;
        nftCollection.mint(to, quantity);
    }

    function _syncSupply() internal {
        uint256 totalSupply = nftCollection.totalSupply();
        maxSupply = nftCollection.maxSupply();
        availableSupply = maxSupply - totalSupply;
    }

    function syncSupply() external onlyOwnerOrOperator {
        _syncSupply();
    }
}

