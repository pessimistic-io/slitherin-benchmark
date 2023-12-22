pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC20Permit.sol";
import "./ERC20Votes.sol";

contract FATToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 private _cap = 100000000e18;

    constructor() ERC20("Funarcade Token", "FAT") ERC20Permit("Funarcade Token") {
        // premint entire supply to treasury
        _mint(msg.sender, _cap);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}
