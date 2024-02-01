// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721Receiver.sol";

interface IWrapNFT is IERC721Receiver {
    event Stake(
        address nftAddress,
        uint256 tokenId,
        address from,
        address holder
    );

    event Redeem(address nftAddress, uint256 tokenId, address to);

    function originalAddress() external view returns (address);

    function stake(
        uint256 tokenId,
        address from,
        address holder
    ) external returns (uint256);

    function redeem(uint256 tokenId, address to) external;
}

