// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";

/**
    .------..------..------..------..------..------..------.
    |A.--. ||R.--. ||B.--. ||J.--. ||A.--. ||C.--. ||K.--. |
    | (\/) || :(): || :(): || :(): || (\/) || :/\: || :/\: |
    | :\/: || ()() || ()() || ()() || :\/: || :\/: || :\/: |
    | '--'A|| '--'R|| '--'B|| '--'J|| '--'A|| '--'C|| '--'K|
    `------'`------'`------'`------'`------'`------'`------'
    A Decentralized BlackJack Game On Arbitrum
    Hosted on IPFS Here: https://morning-field-4798.on.fleek.co/
    Players Rewarded in CHIPZ Tokens for Playing.
    CHIPZ Tokens are ERC20 Tokens on the Arbitrum Network.
    CHIPZ Tokens are also listed on Sushiswap.
    Max Supply 100000 Deflationary as all profits from arBjack are used to buyback and burn CHIPZ.

    Join the Discord: https://discord.gg/fkczvXRnE3

 */

contract CHIPZ is ERC20 {

    uint8 _decimals;

    constructor() ERC20("ArbJack", "CHIPZ") {
        _decimals = 18;
        _mint(msg.sender, 100000 * 10 ** decimals());
    }

    function decimals() public view virtual override returns (uint8) {
        if (_decimals > 0) return _decimals;
        return 18;
    }


}
