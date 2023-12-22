// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IDistToken.sol";
import "./AccessHandler.sol";
import "./ERC20.sol";

/**
 * @title Dist Token
 * @author Deepp Dev Team
 * @notice Abstract ERC20 Token class to account for deposited/staked tokens.
 * @notice It is protected from minting except by an assigned role.
 * @notice This is meant to be extended to use for LPToken and GovToken.
 * @notice Accesshandler is Initializable.
 */
abstract contract DistToken is IDistToken, ERC20, AccessHandler {

    address immutable public tokenAdd;
    uint8 immutable private _decimals;

    /**
     * @notice Simple constructor, just sets the admin and inits token.
     * @param inToken is the matching ERC20 token to account for.
     * @param inName is the ERC20 token name.
     * @param inSymbol is the ERC20 token symbol.
     * @param inDecimals is the ERC20 number of decimals.
     */
    constructor(
        address inToken,
        string memory inName,
        string memory inSymbol,
        uint8 inDecimals
    )
        AccessHandler()
        ERC20(inName, inSymbol)
    {
        tokenAdd = inToken;
        _decimals = inDecimals;
    }


    /**
     * @notice initialize and set the admin and the handler of the tokens.
     * @param tokenHandler is the address that gets the Minter role.
     */
    function init(address tokenHandler)
        external
        virtual
        notInitialized
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (tokenHandler != address(0)) {
            _grantRole(MINTER_ROLE, tokenHandler);
        }

        BaseInitializer.initialize();
    }


    /**
     * @notice Add a handler of the tokens.
     * @param tokenHandler is the address that gets the Minter role.
     */
    function addHandler(address tokenHandler)
        external
        virtual
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(MINTER_ROLE, tokenHandler);
    }

    /**
     * @notice Remove a handler of the tokens.
     * @param tokenHandler is the address that is removed as handler.
     */
    function removeHandler(address tokenHandler)
        external
        virtual
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _revokeRole(MINTER_ROLE, tokenHandler);
    }

    /**
     * @notice Mint additional tokens. Restrict access by role.
     * @param to is the address that receives the new tokens.
     * @param amount is the amount of tokens to mint.
     */
    function mint(address to, uint256 amount)
        external
        virtual
        override
        onlyRole(MINTER_ROLE)
    {
        _mint(to, amount);
    }

    /**
     * @notice Destroys `amount` tokens from the caller.
     * @param amount is the amount of tokens to burn.
     */
    function burn(uint256 amount) external virtual override {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Destroys `amount` tokens from `account`, deducting from
     *         the caller's allowance.
     * @param account is the owner of the tokens to burn.
     * @param amount is the amount of tokens to burn.
     */
    function burnFrom(address account, uint256 amount)
        external
        virtual
        override
    {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /**
     * @notice A simple getter the converts the token add to an interface.
     * @return IERC20 the token interface.
     */
    function token() external view returns (IERC20) {
        return IERC20(tokenAdd);
    }

    /**
     * @notice Returns the number of decimals used to get its user representation.
     *         Overrides the standard ERC20 value of 18.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

