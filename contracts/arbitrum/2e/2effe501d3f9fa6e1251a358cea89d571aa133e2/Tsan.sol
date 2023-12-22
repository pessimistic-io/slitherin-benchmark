// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";

contract Tsan is ERC20, Ownable {

    mapping(address => bool) admins;

    constructor() ERC20("Tsan Token", "TSAN") {
        
    }

    function mint(address _to, uint _amount) external {
        require(admins[msg.sender], "Cannot mint if not admin");
        _mint(_to, _amount);
    }

    function addAdmin(address _admin) external onlyOwner {
        admins[_admin] = true;
    }

    function removeAdmin(address _admin) external onlyOwner {
        admins[_admin] = false;
    }
}
