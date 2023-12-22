// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC20.sol";
import "./Ownable.sol";

// .___ ____  __.___  ________    _____  .___
// |   |    |/ _|   |/  _____/   /  _  \ |   |
// |   |      < |   /   \  ___  /  /_\  \|   |
// |   |    |  \|   \    \_\  \/    |    \   |
// |___|____|__ \___|\______  /\____|__  /___|
//             \/           \/         \/

/**
 * @title Ikigai Token contract
 * @notice ikigaidex.org
 * @author ikigai
 **/

contract Ikigai is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 86400 * 100 ether;

    constructor() ERC20("Ikigai", "IKI") {}

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        // returns true if we can mint -- used by MC to set emissions to zero when max supply is reached
        // we don't mind overshooting a bit here vs undershooting (by not checking using totalSupply() + _amount )
        if (totalSupply() <= MAX_SUPPLY) {
            _mint(_to, _amount);
            return true;
        } else {
            return false;
        }
    }
}

