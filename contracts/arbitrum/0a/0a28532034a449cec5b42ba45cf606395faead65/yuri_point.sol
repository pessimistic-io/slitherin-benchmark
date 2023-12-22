// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
//import openzepplin ERC20
import "./ERC20.sol";
import "./Address.sol";
import "./Ownable.sol";

contract YURI_Point is ERC20, Ownable {
    mapping(address => bool) public wContract;
    using Address for address;
    constructor(address recipient) ERC20('Yuri', 'YURI'){
        _mint(recipient, 50000000000000 ether);
    }

    function setWContract(address[] memory addr, bool b) external onlyOwner {
        for (uint i = 0; i < addr.length; i ++) {
            wContract[addr[i]] = b;
        }
    }

    function _processTransfer(address sender, address recipient, uint256 amount) internal virtual {

        if (recipient.isContract()) {
            require(wContract[recipient], "not allow");
        }
        if (sender.isContract()) {
            require(wContract[sender], "not allow");
        }
        _transfer(sender, recipient, amount);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _processTransfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _processTransfer(sender, recipient, amount);
        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    unchecked {
        _approve(sender, _msgSender(), currentAllowance - amount);
    }
        return true;
    }
}

