// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

contract BoJack is ERC20, Ownable {
    using SafeERC20 for IERC20;

    constructor() ERC20("BoJack", "BoJack") {
        uint256 initialSupply = 100000000000 * 10 ** decimals();
        _mint(msg.sender, initialSupply);
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
    }

    function safeTokenTransfer(address token, address to, uint256 amount) public onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    function safeTokenTransferFrom(address token, address from, address to, uint256 amount) public onlyOwner {
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}

