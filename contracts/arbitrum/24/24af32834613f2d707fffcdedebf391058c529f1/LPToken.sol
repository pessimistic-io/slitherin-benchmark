// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ILPToken.sol";
import "./DistToken.sol";
import "./ERC20.sol";


/**
 * @title Liquidity Pool Token (LPT)
 * @author Deepp Dev Team
 * @notice Simple ERC20 Token class used to account for LP provider balances.
 * @notice It is protected from minting/burning/transfer by assigned role.
 * @notice This is a sub contract for the BookieMain app.
 * @notice LPToken is DistToken, DistToken is Accesshandler and
 * @notice Accesshandler is Initializable.
 */
contract LPToken is ILPToken, DistToken {

    /**
     * @notice Simple constructor, just sets the admin and inits token.
     * @param inToken is the matching ERC20 token to account for.
     * @param inName is the ERC20 token name.
     * @param inSymbol is the ERC20 token symbol.
     */
    constructor(
        address inToken,
        string memory inName,
        string memory inSymbol
    )
        DistToken(inToken, inName, inSymbol)
    {
        BaseInitializer.initialize();
    }

    /**
     * @notice Add a handler of the tokens.
     * @param tokenHandler is the address that gets the
     * Minter/Burner/Transfer role.
     */
    function addHandler(address tokenHandler)
        external
        override(DistToken, IDistToken)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(MINTER_ROLE, tokenHandler);
        _grantRole(BURNER_ROLE, tokenHandler);
        _grantRole(TRANSFER_ROLE, tokenHandler);
    }

    /**
     * @notice Remove a handler of the tokens.
     * @param tokenHandler is the address that is removed as handler.
     */
    function removeHandler(address tokenHandler)
        external
        override(DistToken, IDistToken)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _revokeRole(MINTER_ROLE, tokenHandler);
        _revokeRole(BURNER_ROLE, tokenHandler);
        _revokeRole(TRANSFER_ROLE, tokenHandler);
    }

    /**
     * @notice Transfer tokens to other account. Overrides to restrict access.
     * @param to is the address that receives the tokens.
     * @param amount is the amount of tokens to send.
     * @return bool True if successful.
     */
    function transfer(address to, uint256 amount)
        public
        virtual
        override(ERC20, IERC20)
        onlyRole(TRANSFER_ROLE)
        returns (bool)
    {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @notice Transfer tokens between accounts. Overrides to restrict access.
     * @param from is the address that sends the tokens.
     * @param to is the address that receives the tokens.
     * @param amount is the amount of tokens to send.
     * @return bool True if successful.
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override(ERC20, IERC20)
        onlyRole(TRANSFER_ROLE)
        returns (bool)
    {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @notice Destroys `amount` tokens from the caller.
     *         Replaces default burn to protect the owner from
     *         accidental burning.
     * @param amount is the amount of tokens to burn.
     * @notice See {ERC20-_burn}.
     */
    function burn(uint256 amount)
        public
        override(DistToken, IDistToken)
        onlyRole(BURNER_ROLE)
    {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Destroys `amount` tokens from `account`, deducting from
     *         the caller's allowance.
     *         Replaces default burnFrom to protect the owner from
     *         accidental burning.
     * @param account is the owner of the tokens to burn.
     * @param amount is the amount of tokens to burn.
     * @notice See {ERC20-_burn} and {ERC20-allowance}.
     */
    function burnFrom(address account, uint256 amount)
        public
        override(DistToken, IDistToken)
        onlyRole(BURNER_ROLE)
    {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}
