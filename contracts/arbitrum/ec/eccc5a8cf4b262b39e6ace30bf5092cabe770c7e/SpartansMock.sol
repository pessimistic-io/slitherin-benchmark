//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import "./Spartans.sol";

contract SpartansMock is Spartans {
    constructor()
        Spartans(
            msg.sender,
            msg.sender,
            500,
            "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/"
        )
    {}

    function mint(address to, uint256 amount) external {
        _safeMint(to, amount);
    }

    function contractURI() external pure returns (string memory) {
        return "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq";
    }
}

