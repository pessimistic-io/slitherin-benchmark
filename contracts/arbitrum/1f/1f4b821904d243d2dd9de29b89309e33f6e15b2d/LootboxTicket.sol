pragma solidity ^0.8.14;

// SPDX-License-Identifier: MIT

import "./ERC721.sol";

import {IMultiplierNFT} from "./IMultiplierNFT.sol";
import {IERC20} from "./IERC20.sol";

contract LootboxTicket is ERC721("Lootbox Tickets","TICKETS") {
    address public darwin;
    address public dev;
    uint public lastTicketId;

    constructor(address _darwin) {
        require(_darwin != address(0), "LootboxTicket: ZERO_ADDRESS");
        dev = msg.sender;
        darwin = _darwin;
    }

    function mint(address _to) external {
        require(msg.sender == dev, "LootboxTicket: CALLER_IS_NOT_DEV");
        _safeMint(_to, lastTicketId);
        lastTicketId++;
    }

    function openLootBox(uint _ticketId) external {
        uint darwinAmount;
        darwinAmount = _getRandomDarwin();
        IERC20(darwin).transfer(msg.sender, darwinAmount);
        _safeBurn(_ticketId);
    }

    function _safeBurn(uint _ticketId) internal {
        require(_isApprovedOrOwner(_msgSender(), _ticketId), "LootboxTicket: CALLER_NOT_TICKET_OWNER");

        _burn(_ticketId);
    }

    function _pseudoRand() private view returns(uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp +
                    block.difficulty +
                    ((
                        uint256(keccak256(abi.encodePacked(block.coinbase)))
                    ) / (block.timestamp)) +
                    block.gaslimit +
                    ((uint256(keccak256(abi.encodePacked(tx.origin)))) /
                        (block.timestamp)) +
                    block.number +
                    ((uint256(keccak256(abi.encodePacked(address(this))))) /
                        (block.timestamp)) +
                    ((uint256(keccak256(abi.encodePacked(msg.sender)))) /
                        (block.timestamp))
                )
            )
        );

        return (seed % 1_000);
    }

    function _getRandomDarwin() private view returns(uint d) {
        uint rand = _pseudoRand();
        d = rand + 1;
    }
}
