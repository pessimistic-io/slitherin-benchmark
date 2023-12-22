// SPDX-License-Identifier: MIT
// Website: https://array.capital/
// Twitter: https://twitter.com/array_capital
// Telegram: https://t.me/array_capital
// Medium: https://medium.com/@arraycapital
// Discord: https://discord.com/invite/HM9PKQs6xM
// Pitch Deck: https://drive.google.com/file/d/1dYaXqY6ik5l4B0DyGmxskcZsPCTX-jJ9/view
// Terms and conditions: https://drive.google.com/file/d/1oJrGzfx_j-ALod-09J0XIh3jqpsGGwwo/view

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Pausable.sol";
import "./AccessControl.sol";
import "./ERC20Capped.sol";

contract Array is ERC20Capped, Pausable, AccessControl {
    using SafeMath for uint256;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("Array", "Array") ERC20Capped(100000000e18) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _mint(msg.sender, 20000000e18);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}

