// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155Burnable.sol";

interface ITickets is IERC1155Burnable {
    function getFullPrice(uint256 id) external view returns (uint256);

    function getMinPrice(uint256 id) external view returns (uint256);

    function getPrice(uint256 id, uint256 amount) external view returns (uint256);

    function getBidsBalance(address bids, uint256 id) external view returns (uint256);

    function mintWhenBidding(
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external payable;

    function mintWithETH(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external payable;

    function addProfit(uint256 id, uint256 amount) external;

    function withdrawWETH(uint256 id, uint256 amount) external;
}

