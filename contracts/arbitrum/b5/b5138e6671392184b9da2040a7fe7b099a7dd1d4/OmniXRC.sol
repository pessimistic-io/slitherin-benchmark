// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";

contract OmniXRC is ERC20, Ownable {
    mapping(address => bool) public whiteLists;

    modifier onlyWhiteList() {
        require(whiteLists[msg.sender], "OmniXRC: invalid governor");
        _;
    }

    constructor (
        address community,
        address ecosystem,
        address team,
        address market
    ) ERC20("OmniXRC", "OXRC") {
        uint256 baseAmount = 210000 * 1e18;
        _mint(community, baseAmount * 50);
        _mint(ecosystem, baseAmount * 30);
        _mint(team, baseAmount * 10);
        _mint(market, baseAmount * 10);
    }

    function mint(address account, uint256 amount) external onlyWhiteList {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyWhiteList {
        _burn(account, amount);
    }

    function setWhiteList(address governor) external onlyOwner {
        whiteLists[governor] = true;
    }

    function revokeWhiteList(address governor) external onlyOwner {
        whiteLists[governor] = false;
    }
}
