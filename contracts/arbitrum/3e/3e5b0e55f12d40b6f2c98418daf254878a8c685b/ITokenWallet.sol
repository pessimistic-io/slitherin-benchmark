// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";

/**
 * @title ITokenWallet
 * @dev Interface for the TokenWallet contract, which holds tokens as a token sale wallet
 * and allows for safe transfers to recipients. Only the owner or an authorized contract
 * can transfer tokens from this wallet.
 */
interface ITokenWallet {
    event TokensTransferred(address indexed to, uint256 amount);
    event UpdatedAuthorizedContract(address indexed newAuthorizedContract);
    event UpdatedTokenAddress(address indexed newTokenAddress);

    /**
     * @dev Sets the authorized contract address that can initiate transfers.
     * @param _authorizedContract The address of the contract to be authorized.
     */
    function setAuthorizedContract(address _authorizedContract) external;

    /**
     * @dev Sets the token address for the wallet.
     * @param _tokenAddress The address of the token to be managed by the wallet.
     */
    function setTokenAddress(address _tokenAddress) external;

    /**
     * @dev Returns the token address.
     * @return The address of the token managed by the wallet.
     */
    function getTokenAddress() external view returns (address);

    /**
     * @dev Safely transfers tokens from the wallet to the specified recipient.
     * Only the owner or an authorized contract can initiate transfers.
     * @param _to The address of the recipient.
     * @param _amount The amount of tokens to be transferred.
     */
    function safeTransfer(address _to, uint256 _amount) external;

    /**
     * @dev Returns the token balance of contract.
     * @return The token balance of token wallet contract.
     */
    function available() external view returns (uint256);
}

