pragma solidity 0.8.19;

import { ERC20 } from "./ERC20.sol";

contract Yang is ERC20 {
    address public owner;

    constructor() ERC20("Yang", "YANG", 18) {
    }

    function mint(uint256 amount) external {
        // Require that the amount is lte 10**20
        require(amount <= 100 ether);

        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
