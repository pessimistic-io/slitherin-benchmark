// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract WTF is ERC20, Ownable {
    bool public isApproveEnabled = false;

    constructor() ERC20("WTFCOIN", "WTF") {
        _mint(msg.sender, 42000 * 15000 * 10 ** decimals());
    }

    function enableApprove() public onlyOwner {
        isApproveEnabled = true;
    }

    function disableApprove() public onlyOwner {
        isApproveEnabled = false;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        require(isApproveEnabled, "NOT GAME TIME");
        return super.approve(spender, amount);
    }
}

