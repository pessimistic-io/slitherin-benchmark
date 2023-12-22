pragma solidity ^0.8.14;

// SPDX-License-Identifier: MIT

import "./ERC721.sol";

import {IMultiplierNFT} from "./IMultiplierNFT.sol";
import {ILootboxTicket} from "./ILootboxTicket.sol";
import {IERC20} from "./IERC20.sol";

contract LootboxTicket is ERC721("Lootbox Tickets","TICKETS"), ILootboxTicket {
    address public immutable multiplierNFT;
    address public darwin;
    address public dev;
    uint public lastTicketId;

    constructor() {
        multiplierNFT = msg.sender;
    }

    function initialize(address _dev, address _darwin) external {
        require(msg.sender == multiplierNFT, "LootboxTicket: CALLER_NOT_MULTIPLIER");
        require(dev == address(0) && darwin == address(0), "LootboxTicket: ALREADY_INITIALIZED");
        require(_dev != address(0) && _darwin != address(0), "LootboxTicket: ZERO_ADDRESS");
        dev = _dev;
        darwin = _darwin;
    }

    function mint(address _to) external {
        require(msg.sender == dev, "LootboxTicket: CALLER_IS_NOT_DEV");
        _safeMint(_to, lastTicketId);
        lastTicketId++;
    }

    function openLootBox(uint _ticketId) external {
        uint darwinAmount;
        uint multiplier;
        (multiplier, darwinAmount) = _getRandomMultiplierOrDarwin();
        if (multiplier > 0) {
            IMultiplierNFT(multiplierNFT).mint(msg.sender, multiplier);
        }
        if (darwinAmount > 0) {
            IERC20(darwin).transfer(msg.sender, darwinAmount);
        }
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

        return (seed % 10_000_000);
    }

    function _getRandomMultiplierOrDarwin() private view returns(uint m, uint d) {
        uint rand = _pseudoRand();
        if (rand < 90_000) {
            uint r = rand % 9;
            d = 2_000 + r * 1_000;
        } else if (rand < 2_340_000) {
            uint r = rand % 90;
            d = 110 + r * 10;
        } else if (rand < 3_590_000) {
            uint r = rand % 25;
            d = 76 + r;
        } else if (rand < 4_965_000) {
            uint r = rand % 25;
            d = 51 + r;
        } else if (rand < 6_465_000) {
            uint r = rand % 25;
            d = 26 + r;
        } else if (rand < 8_340_000) {
            uint r = rand % 25;
            d = 1 + r;
        } else if (rand < 8_340_010) {
            m = 500;
        } else if (rand < 8_340_110) {
            m = 100;
        } else if (rand < 8_350_110) {
            m = 50;
        } else if (rand < 8_500_000) {
            m = 25;
        } else {
            m = 10;
        }
    }
}
