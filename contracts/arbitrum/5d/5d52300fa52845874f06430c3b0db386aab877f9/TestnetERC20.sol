// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./ERC20.sol";
import "./Ownable.sol";

/// @title TestnetERC20
/// @author Trader Joe
/// @dev ONLY FOR TESTS
contract TestnetERC20 is ERC20, Ownable {
    uint8 private decimalsOverride;

    /// @dev Constructor
    /// @param _decimals The number of decimals for this token
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        decimalsOverride = _decimals;
    }

    /// @dev Define the number of decimals
    /// @return The number of decimals
    function decimals() public view override returns (uint8) {
        return decimalsOverride;
    }

    /// @dev Mint _amount to _to.
    /// @param _to The address that will receive the mint
    /// @param _amount The amount to be minted
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}

