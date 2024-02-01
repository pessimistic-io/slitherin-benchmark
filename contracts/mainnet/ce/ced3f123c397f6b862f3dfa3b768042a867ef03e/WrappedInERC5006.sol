// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import "./IERC1155MetadataURI.sol";
import "./ERC5006Upgradeable.sol";
import "./IWrappedInERC5006.sol";

contract WrappedInERC5006 is ERC5006Upgradeable, IWrappedInERC5006 {
    address public originalAddress;

    function initializeWrap(address originalAddress_) public initializer {
        recordLimit = 100;
        originalAddress = originalAddress_;
    }

    function stake(
        uint256 tokenId,
        uint256 amount,
        address to
    ) public {
        IERC1155(originalAddress).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            amount,
            ""
        );
        _mint(to, tokenId, amount, "");
    }

    function redeem(
        uint256 tokenId,
        uint256 amount,
        address to
    ) public {
        _burn(msg.sender, tokenId, amount);
        IERC1155(originalAddress).safeTransferFrom(
            address(this),
            to,
            tokenId,
            amount,
            ""
        );
    }

    function stakeAndCreateUserRecord(
        uint256 tokenId,
        uint64 amount,
        address to,
        uint64 expiry
    ) external returns (uint256) {
        stake(tokenId, amount, msg.sender);
        return createUserRecord(msg.sender, to, tokenId, amount, expiry);
    }

    function redeemRecord(uint256 recordId, address to) external {
        uint256 tokenId = userRecordOf(recordId).tokenId;
        uint256 amount = userRecordOf(recordId).amount;
        deleteUserRecord(recordId);
        redeem(tokenId, amount, to);
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceId == type(IWrappedIn).interfaceId ||
            ERC5006Upgradeable.supportsInterface(interfaceId);
    }
}

