// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ERC20.sol";


contract EscrowUSDEX is ERC20, Ownable {

    address public minter;

    event MinterSetted(address indexed minter);

    constructor(
        uint256 initialSupply
    ) ERC20("EscrowUSDEX", "esUSDEX") {
        require(initialSupply > 0, "EscrowUSDEX: InitialSupply not positive");
        _mint(msg.sender, initialSupply);
       
    }

    function burn(address from, uint256 amount) external returns (bool) {
        require(msg.sender == from, "EscrowUSDEX: Can't burn from other wallets");
        _burn(from, amount);
        return true;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        require(msg.sender == minter, "EscrowUSDEX: Can be executed only by minters");
        require(amount > 0, "EscrowUSDEX: Amount not positive");
        _mint(to, amount);
        return true;
    }

    function setMinter(address _minter) external onlyOwner returns (bool) {
        minter = _minter;
        emit MinterSetted(_minter);
        return true;
    }
}

