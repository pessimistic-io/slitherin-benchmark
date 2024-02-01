// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import "./IWrappedIn.sol";
import "./IERC5006.sol";

interface IWrappedInERC5006 is IERC5006, IWrappedIn {
    function stakeAndCreateUserRecord(
        uint256 tokenId,
        uint64 amount,
        address to,
        uint64 expiry
    ) external returns (uint256);

    function redeemRecord(uint256 recordId, address to) external;

    function originalAddress() external view returns (address);
}

