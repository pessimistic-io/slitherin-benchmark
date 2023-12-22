// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Counters.sol";
import {Utils} from "./Utils.sol";

contract Event is ERC1155, Ownable, Utils {
    using Counters for Counters.Counter;
    address public manager;
    Counters.Counter private _tokenIds;
    string public name;
    string public description;
    uint256 public start;
    uint256 public finish;
    string public location;

    mapping(uint256 => uint256) ticket_prices;
    mapping(address => bool) public hasBought;

    constructor(address creator, string[] memory tickets, uint256[] memory amounts, string memory _uri, uint256[] memory prices, EventDetails memory details) ERC1155(_uri) {
       manager = creator;
        name = details._name;
        description = details._description;
        location = details._location;
        start = details._start;
        finish = details._end;
        transferOwnership(manager);
        for (uint256 i = 0; i < tickets.length; i++) {
            _tokenIds.increment();
            uint256 newTokenId = _tokenIds.current();
            _mint(manager, newTokenId, amounts[i], "");
            ticket_prices[i] = prices[i];
        }
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function addTicket(uint256 amount) public onlyOwner {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _mint(manager, newTokenId, amount, "");
    }

    function hasTicket(address user) public view returns (int256) {
        for (int256 i = 0; i < int256(_tokenIds.current()); i++) {
            if (balanceOf(user, uint256(i)) > 0) {
                return i;
            }
        }
        return -1;
    }

    function buyTicket(uint256 ticket, uint256 amount) external payable {
        require(
            balanceOf(manager, ticket) >= amount,
            "Not enough tickets left!"
        );
        require(
            msg.value >= ticket_prices[ticket] * amount,
            "Not enough to buy tickets!"
        );

        _safeTransferFrom(manager, msg.sender, ticket, amount, "0x0");
    }

    // Need to figure out permissions, avoid people minting all tickets!
    function transferTicket(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) public {
        _safeTransferFrom(from, to, id, amount, "0x0");
    }

    function getTotalTicketTypes() public view returns (uint256) {
        return _tokenIds.current();
    }

    function sweep() public onlyOwner {
        uint256 _balance = address(this).balance;
        payable(manager).transfer(_balance);
    }
}
