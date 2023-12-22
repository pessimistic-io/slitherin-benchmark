// SPDX-License-Identifier: none
pragma solidity ^0.8.18;

import { IFCO } from "./FCO.sol";

contract LubAuction {   

    // ------------------------------- STORAGE -------------------------------
    
    IFCO public fco;
    
    // ------------------------------- CONSTRUCT -------------------------------

    constructor(IFCO fco_) {
        fco = fco_;
    }

    function bid(uint128 amount) public {
        fco.auctionUse(msg.sender, amount);
    }

    function withdraw(uint128 amount) public {
        fco.auctionReturn(msg.sender, amount, address(0));
    }

    function payout(uint128 amount) public {
        fco.auctionReturn(msg.sender, amount, msg.sender);
    }
}
