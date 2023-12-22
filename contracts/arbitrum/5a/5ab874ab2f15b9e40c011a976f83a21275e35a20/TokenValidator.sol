// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Address.sol";
import "./ITokenValidator.sol";
import "./AccessHandler.sol";
// For debugging only
//

/**
 * @title  Token Validator
 * @author Deepp Dev Team
 * @notice An access control contract. It restricts access to otherwise public
 *         methods, by checking for assigned roles to tokens. Some other
 *         token validations are also perform (contract and 0 address).
 * @notice This is a util contract for the BookieMain app.
 */
abstract contract TokenValidator is ITokenValidator, AccessHandler {
    using Address for address;

    address internal constant DUMMY_ADDRESS = address(1);

    // Mapping used to pair DistToken <-> ERC20Token, not used to validate
    // tokenAdd (key) => distTokenAdd (value)
    mapping(address => address) internal allowedTokens;
    // (value) => (key), for cases where we dont use IDistToken,
    // and need to find the key token from the value token
    mapping(address => address) internal reversedTokens;

    // Checks are only performed, if an allowed token pair is added
    // or by manual enabling.
    bool internal enabledValidation = false;

    /**
     * Error for using a zero address token.
     */
    error BadTokenZero();

    /**
     * Error for using a address that is not a token (not a contract).
     */
    error InvalidToken(address tokenAdd);

    /**
     * Error for using a not allowed token.
     * @param tokenAdd is the address of the token type.
     */
    error TokenNotAllowed(address tokenAdd);

    /**
     * @notice Modifier that checks that only allowed distTokens are used.
     * @param inDistToken The DistToken to verify.
     */
    modifier onlyAllowedDistToken(address inDistToken) {
        if (!getInitialized()) {
            revert NotInitialized();
        }
        address tokenAdd = IDistToken(inDistToken).tokenAdd();
        if (reversedTokens[inDistToken] != tokenAdd) {
            // To avoid an unintented accept of a DistToken with matching key/currency token
            revert TokenNotAllowed({tokenAdd: inDistToken});
        }
        if (!hasRole(TOKEN_ROLE, tokenAdd)) {
            revert TokenNotAllowed({tokenAdd: inDistToken});
        }
        _;
    }

    /**
     * @notice Modifier that checks that only allowed valueTokens are used.
     * @notice ValueToken refers to the keyToken/valueToken pair in allowedTokens.
     * @param inValueToken The token to verify.
     */
    modifier onlyAllowedValueToken(address inValueToken) {
        if (!getInitialized()) {
            revert NotInitialized();
        }
        address tokenAdd = reversedTokens[inValueToken];
        if (!hasRole(TOKEN_ROLE, tokenAdd)) {
            revert TokenNotAllowed({tokenAdd: inValueToken});
        }
        _;
    }

    /**
     * @notice Modifier that checks that only allowed tokens are used.
     * @param inToken The token to verify.
     */
    modifier onlyAllowedToken(address inToken) {
        if (!getInitialized()) {
            revert NotInitialized();
        }
        if (inToken == address(0)) {
            revert BadTokenZero();
        }
        if (!isERC20(inToken)) {
            revert InvalidToken({tokenAdd: inToken});
        }
        if (enabledValidation && !hasRole(TOKEN_ROLE, inToken)) {
            revert TokenNotAllowed({tokenAdd: inToken});
        }
        _;
    }

    /**
     * @notice Simple constructor, just calls Accasshandler constructor.
     */
    constructor() AccessHandler() {
    }


    /**
     * @notice Add a distToken and the referenced token to the allowed list.
     * @param inDistToken The DistToken to add to the allowed list.
     */
    function addDistToken(IDistToken inDistToken)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _addTokenPair(inDistToken.tokenAdd(), address(inDistToken));
    }

    /**
     * @notice Add a distToken and the referenced token to the allowed list.
     * @param inTokenAdd The token to add to the allowed list.
     */
    function addSingleToken(address inTokenAdd)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // We are only interested in the key token in this case,
        // but the value cannot be the 0 addresse
        _addTokenPair(inTokenAdd, DUMMY_ADDRESS);
    }

    /**
     * @notice Add a pair of ERC20 tokens to the list of allowed tokens.
     * @param inKeyToken The token address as key in the allowed list.
     * @param inValueToken The token address as value in the allowed list.
     */
    function addTokenPair(address inKeyToken, address inValueToken)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // We are only interested in the key token in this case,
        // but the value cannot be the 0 addresse
        _addTokenPair(inKeyToken, inValueToken);
    }

    /**
     * @notice Remove a distToken and ERC20 token from the list.
     * @param inDistToken The DistToken to remove from the allowed list.
     */
    function removeDistToken(IDistToken inDistToken)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Remove the token from the role list of accepted tokens.
        revokeRole(AccessHandler.TOKEN_ROLE, inDistToken.tokenAdd());
        // Clear the allowed list entry.
        delete reversedTokens[address(inDistToken)];
        delete allowedTokens[inDistToken.tokenAdd()];
    }

    /**
     * @notice Remove an ERC20 token key (and value token?) from the list.
     * @param inTokenAdd The token to remove from the allowed list.
     */
    function removeToken(address inTokenAdd)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Its not inportant if the value token was the dummy or a
        // regular ERC20 or a DistToken. We just clear the data.
        // Remove the key token from the role list of accepted tokens.
        revokeRole(AccessHandler.TOKEN_ROLE, inTokenAdd);
        // Clear the allowed role list entry.
        delete reversedTokens[allowedTokens[inTokenAdd]];
        delete allowedTokens[inTokenAdd];
    }

    /**
     * @notice Enable the token validation.
     */
    function enableValidation()
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        enabledValidation = true;
    }

    /**
     * @notice Disable the token validation.
     */
    function disableValidation()
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        enabledValidation = false;
    }

    /**
     * @notice Checks if an allowed distToken address is supplied.
     * @param inDistToken The DistToken to check.
     * @return bool True if the dist token is allowed, false if not.
     */
    function isAllowedDistToken(address inDistToken)
        external
        view
        override
        returns (bool)
    {
        if (!getInitialized()) {
            revert NotInitialized();
        }
        if (reversedTokens[inDistToken] != IDistToken(inDistToken).tokenAdd()) {
            // To avoid an unintented accept of a DistToken with matching key/currency token
            return false;
        }
        return _isAllowedToken(reversedTokens[inDistToken]);
    }

    /**
     * @notice Checks if an allowed valueToken address is supplied.
     * @notice ValueToken refers to the keyToken/valueToken pair in allowedTokens.
     * @param inValueToken The token to check.
     * @return bool True if the token is allowed, false if not.
     */
    function isAllowedValueToken(address inValueToken)
        external
        view
        override
        returns (bool)
    {
        if (!getInitialized()) {
            revert NotInitialized();
        }
        return _isAllowedToken(reversedTokens[inValueToken]);
    }

    /**
     * @notice Checks if an allowed token address is supplied.
     * @param inToken The token to check.
     * @return bool True if the token is allowed, false if not.
     */
    function isAllowedToken(address inToken)
        external
        view
        override
        returns (bool)
    {
        if (!getInitialized()) {
            revert NotInitialized();
        }
        return _isAllowedToken(inToken);
    }

    /**
     * @notice Checks if an allowed token address is supplied.
     * @param inToken The token to check.
     * @return bool True if the token is allowed, false if not.
     */
    function _isAllowedToken(address inToken)
        internal
        view
        returns (bool)
    {
        if (inToken == address(0)) {
            return false;
        }
        if (!isERC20(inToken)) {
            return false;
        }
        if (enabledValidation) {
            return hasRole(TOKEN_ROLE, inToken);
        }
        return true;
    }

    /**
     * @notice Add a pair of ERC20 tokens to the list of allowed tokens.
     * @param inKeyToken The token address as key in the allowed list.
     * @param inValueToken The token address as value in the allowed list.
     */
    function _addTokenPair(address inKeyToken, address inValueToken)
        internal
    {
        if (inValueToken == address(0)) {
            revert BadTokenZero();
        }
        if (inKeyToken == address(0)) {
            revert BadTokenZero();
        }
        if (!(inValueToken == DUMMY_ADDRESS || isERC20(inValueToken))) {
            revert InvalidToken({tokenAdd: inValueToken});
        }
        if (!isERC20(inKeyToken)) {
            revert InvalidToken({tokenAdd: inKeyToken});
        }
        // Check if the tokens are added already, we dont want overwrites.
        if (allowedTokens[inKeyToken] != address(0)) {
            revert InvalidToken({tokenAdd: inKeyToken});
        }
        if (reversedTokens[inValueToken] != address(0)) {
            revert InvalidToken({tokenAdd: inValueToken});
        }

        // Add the token to the role list of accepted tokens.
        grantRole(AccessHandler.TOKEN_ROLE, inKeyToken);
        // Pair the new key token, with the matching value token.
        allowedTokens[inKeyToken] = inValueToken;
        if (inValueToken != DUMMY_ADDRESS) {
            // and reversed.
            reversedTokens[inValueToken] = inKeyToken;
        }

        enabledValidation = true;
    }

    /**
     * @notice Check if an addresse is for an (ERC20 token) contract.
     * @param inToken The token address to check.
     * @return bool True if the address is compliant, false if not.
     */
    function isERC20(address inToken)
        internal
        view
        returns (bool)
    {
        // Since OZ ERC does not implement EIP165, we just make a contract check.
        return inToken.isContract();
    }
}

