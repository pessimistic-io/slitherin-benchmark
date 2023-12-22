// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract WTF is ERC20, Ownable {
    mapping (address => bool) private _whitelist;
    bool private _transferEnabled = true;

    constructor() ERC20("WTFCOIN", "WTF") {
        _mint(msg.sender, 42000 * 15000 * 10 ** decimals());
    }

    function addToWhitelist(address account) public onlyOwner {
        _whitelist[account] = true;
    }

    function removeFromWhitelist(address account) public onlyOwner {
        _whitelist[account] = false;
    }

    function enableTransfers() public onlyOwner {
        _transferEnabled = true;
    }

    function disableTransfers() public onlyOwner {
        _transferEnabled = false;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        require(_transferEnabled || _whitelist[from], "WTF: transfers are disabled");
    }
}

