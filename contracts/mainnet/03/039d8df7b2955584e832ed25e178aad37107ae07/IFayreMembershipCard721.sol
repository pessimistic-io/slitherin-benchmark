// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./extensions_IERC721Enumerable.sol";

interface IFayreMembershipCard721 is IERC721Enumerable {
    function symbol() external view returns(string memory);

    function membershipCardMintTimestamp(uint256 tokenId) external view returns(uint256);
}
