// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Errors.sol";

contract VestingToken is ERC20, Ownable {
    constructor() ERC20("BRI Vesting TOKEN", "BRIX") Ownable(msg.sender) {}

    /**
     * @dev Sets decimal places for token to just 9 places instead of default 18
     */

    function decimals() public view virtual override returns (uint8) {
        return 9; // Same decimals as for the token we will be selling (BRI)
    }

    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_) external onlyOwner {
        _burn(from_, amount_);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
        if (from != address(0) && to != address(0)) revert Blocked();
    }
}

