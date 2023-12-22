// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./ERC20Upgradeable.sol";
import "./BaseVault.sol";

/// @title Glitter Finance mint/burn vault
/// @author Ackee Blockchain
/// @notice Mint/burn vault which uses external ERC20
contract MintBurnVault is BaseVault, ERC20Upgradeable {
    uint8 tokenDecimals;

    constructor() initializer {}

    /// @notice Initializer function
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _router Router address
    /// @param _owner Owner address
    /// @param _recoverer Recoverer address
    function initialize(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        IRouter _router,
        address _owner,
        address _recoverer
    ) public virtual initializer {
        __BaseVault_initialize(_router, _owner, _recoverer);
        __ERC20_init(_name, _symbol);
        tokenDecimals = _decimals;
    }

    /// @notice Deposit implementation - burn
    /// @param _from Sender address
    /// @param _amount Token amount
    function _depositImpl(address _from, uint256 _amount) internal override {
        _burn(_from, _amount);
    }

    /// @notice Release implementation - mint
    /// @param _to Destination address
    /// @param _amount Token amount
    function _releaseImpl(address _to, uint256 _amount) internal override {
        _mint(_to, _amount);
    }

    function token() external view override returns (IERC20) {
        return IERC20(address(this));
    }

    /// @notice Get token decimals
    /// @return Token decimals
    function decimals()
        public
        view
        override(ERC20Upgradeable, IVault)
        returns (uint8)
    {
        return tokenDecimals;
    }
}

