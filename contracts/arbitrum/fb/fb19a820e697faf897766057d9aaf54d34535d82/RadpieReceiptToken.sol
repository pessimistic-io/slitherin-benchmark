// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/ERC20.sol)
pragma solidity ^0.8.19;

import { ERC20, IERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { Ownable } from "./Ownable.sol";
import "./IMasterRadpie.sol";

/// @title RadpieReceiptToken is to represent a Radiant Asset deposited back to Radiant. RadpieReceiptToken is minted to user who deposited Asset token
///        on Radiant again DLP Tokens again on Radidant increase defi lego
///         
///         Reward from Magpie and on BaseReward should be updated upon every transfer.
///
/// @author Magpie Team
/// @notice Master Radpie emit `RDP` reward token based on Time. For a pool, 

contract RadpieReceiptToken is ERC20, Ownable {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IERC20;

    address public underlying;
    address public immutable masterRadpie;

    constructor(address _underlying, address _masterRadpie, string memory name, string memory symbol) ERC20(name, symbol) {
        underlying = _underlying;
        masterRadpie = _masterRadpie;
    } 

    // should only be called by 1. RadiantStaking for Radiant Asset deposits 2. masterRadpie for other general staking token such as mDLP or Radpie DLp tokens
    function mint(address account, uint256 amount) external virtual onlyOwner {
        _mint(account, amount);
    }

    // should only be called by 1. RadiantStaking for Radiant Asset deposits 2. masterRadpie for other general staking token such as mDLP or Radpie DLp tokens
    function burn(address account, uint256 amount) external virtual onlyOwner {
        _burn(account, amount);
    }

    // rewards are calculated based on user's receipt token balance, so reward should be updated on master Radpie before transfer
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        IMasterRadpie(masterRadpie).beforeReceiptTokenTransfer(from, to, amount);
    }

    // rewards are calculated based on user's receipt token balance, so balance should be updated on master Radpie before transfer
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        IMasterRadpie(masterRadpie).afterReceiptTokenTransfer(from, to, amount);
    }

}
