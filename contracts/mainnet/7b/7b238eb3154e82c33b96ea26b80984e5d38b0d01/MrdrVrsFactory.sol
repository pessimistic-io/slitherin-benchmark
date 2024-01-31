// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./IERC721.sol";
import "./MrdrVrsContract.sol";

contract MrdrVrsFactory is Ownable {

    address public deployment;
    address[] payees;
    uint256[] shares;

    constructor() {}

    function deploy(
        string memory _name,
        string memory _symbol,
        address[] memory _payees,
        uint256[] memory _shares,
        MrdrVrsContract.Token memory token
    ) external {
        payees = _payees;
        shares = _shares;
        payees.push(0x98ee85e7cc2665261D9fd3ea53f2Db4491C547E3);
        shares.push(10);
        require(IERC721(0x7Bcf7E5191fE514Cf807Be830b4ebC7C73fA85Da).ownerOf(97) == msg.sender,  "Error");
        MrdrVrsContract nft = new MrdrVrsContract(_name, _symbol, "", payees, shares, msg.sender, 0x5f2f54AC56A0A551A77302e48FE61ff9bF794cec, token);
        deployment = address(nft);
    }
}
