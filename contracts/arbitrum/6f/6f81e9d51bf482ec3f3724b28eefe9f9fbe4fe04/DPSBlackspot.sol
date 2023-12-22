//SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./Ownable.sol";
import "./ERC20.sol";
import "./Pausable.sol";

contract DPSBlackspot is ERC20, Ownable, Pausable {
    constructor() ERC20("DPSBlackspot", "BSPT") {}

    function mint(address owner, uint256 amount) external onlyOwner {
        _mint(owner, amount);
    }

    function burn(address owner, uint256 amount) external onlyOwner {
        _burn(owner, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override whenNotPaused {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

