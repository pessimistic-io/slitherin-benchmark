// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";

contract Plexus is ERC20("Plexus", "PLX"), Ownable {
    address private minter;

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    modifier onlyMinter() {
        require(msg.sender == minter || msg.sender == owner());
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    constructor() public {
        uint256 initSupply = 5 * (10 ** 8) * (10 ** 18);
        _mint(owner(), initSupply);
    }
}

