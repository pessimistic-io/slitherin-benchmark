// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./Ownable.sol";
import "./ERC20.sol";

contract KaToken is ERC20, Ownable {

    uint256 private constant _maxSupply = 1000_0000_0000 * 10 ** 18;

    uint256 private constant burnFee = 200;
    address public  constant burnAddress = 0x000000000000000000000000000000000000dEaD;

    address private dep;
    bool public inBurning = true;

    constructor() ERC20("KaToken", "KaToken") {
        dep = _msgSender();
        _mint(dep, _maxSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return _aaTransfer(_msgSender(), to, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _aaTransfer(sender, recipient, amount);
    }

    function _aaTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        if (!inBurning && from != dep && to != dep) {
            uint256 burnAmount = amount * burnFee / 10000;
            amount -= burnAmount;
            _transfer(from, burnAddress, burnAmount);   
        }

        _transfer(from, to, amount);
        return true;
    }

    function setBurning(bool _isBurning) public onlyOwner {
        inBurning = _isBurning;
    }

    receive() external payable {}
}
