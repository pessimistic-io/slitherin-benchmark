// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IGovToken.sol";
import "./AccessHandler.sol";
import "./ERC20.sol";

/**
 * @title Governance Token (GOV)
 * @author Deepp Dev Team
 * @notice Simple ERC20 Token class used to account for governance.
 * @notice It is protected from minting except by an assigned role.
 * @notice This is a sub contract for the DaoMain app.
 * @notice Accesshandler is Initializable.
 */
contract GovToken is IGovToken, ERC20, AccessHandler {

    /**
     * @notice Simple constructor, just sets the admin and inits token.
     * @param initialSupply is the initial amount of tokens to mint.
     * @param inName is the ERC20 token name.
     * @param inSymbol is the ERC20 token symbol.
     */
    constructor(
        uint256 initialSupply,
        string memory inName,
        string memory inSymbol
    ) ERC20(inName, inSymbol) {
        _mint(msg.sender, initialSupply);
        BaseInitializer.initialize();
    }

    /**
     * @notice Mint additional tokens. Restrict access by role.
     * @param to is the address that receives the new tokens.
     * @param amount is the amount of tokens to mint.
     */
    function mint(address to, uint256 amount)
        external
        override
        isInitialized
        onlyRole(MINTER_ROLE)
    {
        _mint(to, amount);
    }
}

