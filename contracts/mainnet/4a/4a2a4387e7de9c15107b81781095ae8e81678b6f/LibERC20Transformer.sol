// SPDX-License-Identifier: Apache-2.0

/*
    Copyright 2022 0xPlasma Alliance
*/

/***
 *      ______             _______   __                                             
 *     /      \           |       \ |  \                                            
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______  
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \ 
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *                                                                                  
 *                                                                                  
 *                                                                                  
 */
 
pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

import "./IERC20TokenV06.sol";
import "./LibERC20TokenV06.sol";


library LibERC20Transformer {

    using LibERC20TokenV06 for IERC20TokenV06;

    /// @dev ETH pseudo-token address.
    address constant internal ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @dev ETH pseudo-token.
    IERC20TokenV06 constant internal ETH_TOKEN = IERC20TokenV06(ETH_TOKEN_ADDRESS);
    /// @dev Return value indicating success in `IERC20Transformer.transform()`.
    ///      This is just `keccak256('TRANSFORMER_SUCCESS')`.
    bytes4 constant internal TRANSFORMER_SUCCESS = 0x13c9929e;

    /// @dev Transfer ERC20 tokens and ETH.
    /// @param token An ERC20 or the ETH pseudo-token address (`ETH_TOKEN_ADDRESS`).
    /// @param to The recipient.
    /// @param amount The transfer amount.
    function transformerTransfer(
        IERC20TokenV06 token,
        address payable to,
        uint256 amount
    )
        internal
    {
        if (isTokenETH(token)) {
            to.transfer(amount);
        } else {
            token.compatTransfer(to, amount);
        }
    }

    /// @dev Check if a token is the ETH pseudo-token.
    /// @param token The token to check.
    /// @return isETH `true` if the token is the ETH pseudo-token.
    function isTokenETH(IERC20TokenV06 token)
        internal
        pure
        returns (bool isETH)
    {
        return address(token) == ETH_TOKEN_ADDRESS;
    }

    /// @dev Check the balance of an ERC20 token or ETH.
    /// @param token An ERC20 or the ETH pseudo-token address (`ETH_TOKEN_ADDRESS`).
    /// @param owner Holder of the tokens.
    /// @return tokenBalance The balance of `owner`.
    function getTokenBalanceOf(IERC20TokenV06 token, address owner)
        internal
        view
        returns (uint256 tokenBalance)
    {
        if (isTokenETH(token)) {
            return owner.balance;
        }
        return token.balanceOf(owner);
    }

    /// @dev RLP-encode a 32-bit or less account nonce.
    /// @param nonce A positive integer in the range 0 <= nonce < 2^32.
    /// @return rlpNonce The RLP encoding.
    function rlpEncodeNonce(uint32 nonce)
        internal
        pure
        returns (bytes memory rlpNonce)
    {
        // See https://github.com/ethereum/wiki/wiki/RLP for RLP encoding rules.
        if (nonce == 0) {
            rlpNonce = new bytes(1);
            rlpNonce[0] = 0x80;
        } else if (nonce < 0x80) {
            rlpNonce = new bytes(1);
            rlpNonce[0] = byte(uint8(nonce));
        } else if (nonce <= 0xFF) {
            rlpNonce = new bytes(2);
            rlpNonce[0] = 0x81;
            rlpNonce[1] = byte(uint8(nonce));
        } else if (nonce <= 0xFFFF) {
            rlpNonce = new bytes(3);
            rlpNonce[0] = 0x82;
            rlpNonce[1] = byte(uint8((nonce & 0xFF00) >> 8));
            rlpNonce[2] = byte(uint8(nonce));
        } else if (nonce <= 0xFFFFFF) {
            rlpNonce = new bytes(4);
            rlpNonce[0] = 0x83;
            rlpNonce[1] = byte(uint8((nonce & 0xFF0000) >> 16));
            rlpNonce[2] = byte(uint8((nonce & 0xFF00) >> 8));
            rlpNonce[3] = byte(uint8(nonce));
        } else {
            rlpNonce = new bytes(5);
            rlpNonce[0] = 0x84;
            rlpNonce[1] = byte(uint8((nonce & 0xFF000000) >> 24));
            rlpNonce[2] = byte(uint8((nonce & 0xFF0000) >> 16));
            rlpNonce[3] = byte(uint8((nonce & 0xFF00) >> 8));
            rlpNonce[4] = byte(uint8(nonce));
        }
    }

    /// @dev Compute the expected deployment address by `deployer` at
    ///      the nonce given by `deploymentNonce`.
    /// @param deployer The address of the deployer.
    /// @param deploymentNonce The nonce that the deployer had when deploying
    ///        a contract.
    /// @return deploymentAddress The deployment address.
    function getDeployedAddress(address deployer, uint32 deploymentNonce)
        internal
        pure
        returns (address payable deploymentAddress)
    {
        // The address of if a deployed contract is the lower 20 bytes of the
        // hash of the RLP-encoded deployer's account address + account nonce.
        // See: https://ethereum.stackexchange.com/questions/760/how-is-the-address-of-an-ethereum-contract-computed
        bytes memory rlpNonce = rlpEncodeNonce(deploymentNonce);
        return address(uint160(uint256(keccak256(abi.encodePacked(
            byte(uint8(0xC0 + 21 + rlpNonce.length)),
            byte(uint8(0x80 + 20)),
            deployer,
            rlpNonce
        )))));
    }
}

