// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {PWNFaucet20} from "./PWNFaucet20.sol";
import {PWNFaucet721} from "./PWNFaucet721.sol";
import {PWNFaucet1155} from "./PWNFaucet1155.sol";


contract PWNFaucet {

    PWNFaucet20 public t20;
    PWNFaucet721 public t721;
    PWNFaucet1155 public t1155;


    constructor() {
        t20 = new PWNFaucet20("PWN Faucet Token", "PWNf20");
        t721 = new PWNFaucet721("PWN Faucet NFT", "PWNf721");
        t1155 = new PWNFaucet1155();
    }


    /// @dev Drip 100 fungible, 2 non-fungible, and 10 semi-fungible token to the receiver.
    /// @param receiver The address of the receiver.
    function drip(address receiver) external {
        t20.mint(receiver, 100e18);

        t721.mint(receiver);
        t721.mint(receiver);

        t1155.mint(receiver, 10);
    }

}

