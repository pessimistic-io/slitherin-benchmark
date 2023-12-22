// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./Pausable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

// .___ ____  __.___  ________    _____  .___
// |   |    |/ _|   |/  _____/   /  _  \ |   |
// |   |      < |   /   \  ___  /  /_\  \|   |
// |   |    |  \|   \    \_\  \/    |    \   |
// |___|____|__ \___|\______  /\____|__  /___|
//             \/           \/         \/

contract RewardVault is Ownable {
    using SafeERC20 for IERC20;

    /**
     * @dev Mapping of addresses that are authorized to add distribute rewards.
     */
    mapping(address => bool) public authorizedAddresses;

    /**
     * @dev Only authorized addresses can call a function with this modifier.
     */
    modifier onlyAuthorized() {
        require(authorizedAddresses[msg.sender], "Not authorized.");
        _;
    }

    /**
     * @dev Sets or revokes authorized address.
     * @param addr Address we are setting.
     * @param isAuthorized True is setting, false if we are revoking.
     */
    function setAuthorizedAddress(address addr, bool isAuthorized)
        external
        onlyOwner
    {
        authorizedAddresses[addr] = isAuthorized;
    }

    function transfer(
        address token,
        address to,
        uint256 amount
    ) public onlyAuthorized {
        IERC20(token).safeTransfer(to, amount);
    }
}

