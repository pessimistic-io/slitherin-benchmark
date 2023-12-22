// SPDX-License-Identifier: GPL-3.0
//author: Johnleouf21
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Strings.sol";

contract Tsan is ERC20, Ownable {

    using Strings for uint;

    mapping(address => bool) admins;

    uint public maxSupply = (1000000000 * 10 ** decimals());
    uint public dev_marketSupply = (850000000 * 10 ** decimals());
    uint public teamSupply = (50000000 * 10 ** decimals());

    constructor() ERC20("Tsan Token", "TSAN") {
        _mint(0xBB8A3435c6A42fF6576920805B36f578aeCa4b58, dev_marketSupply);
        _mint(0x61BE2F1413Ee095e5EC2BdB2a840d2334183E7a4, teamSupply);
        _mint(msg.sender, 100000 * 10 ** decimals());
    }

    function mint(address _to, uint _amount) external {
        require(admins[msg.sender], "Cannot mint if not admin");
        require(totalSupply() + _amount <= maxSupply, "Amount exceed maxSupply");
        _mint(_to, _amount);
    }

    function addAdmin(address _admin) external onlyOwner {
        admins[_admin] = true;
    }

    function removeAdmin(address _admin) external onlyOwner {
        admins[_admin] = false;
    }
}
