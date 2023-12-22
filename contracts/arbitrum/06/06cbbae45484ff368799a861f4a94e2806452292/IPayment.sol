// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./IERC20.sol";
import "./IAccount.sol";
import "./IAccountsFactory.sol";

interface IPayment is IAccountsFactory {

    struct sendToken {
        IERC20 token;
        address to;
        uint256 amount;
    }

    struct Collector {
        address token;
        IAccount from;
    }

    /**
     * send ETH to several users;
     * @param to array of destinations
     * @param amount array of amounts
     */
    function withdrawEth(
        address[] calldata to,
        uint256[] calldata amount
    ) external;

    /**
     * withdrawEth to an address
     * @param to destination address
     * @param amount amount to send
     */

    function withdrawEth(address to, uint256 amount) external;

    /**
     * withdraw Tokens to an address
     * @param to destination address
     * @param amount amout to send
     * @param token token to send
     */
    function withdrawToken(address to, uint256 amount, IERC20 token) external;

    /**
     * withdraw Token to several addresses
     * @param to array of destination address
     * @param amount array of amounts to send
     * @param token token to send
     */
    function withdrawToken(
        address[] calldata to,
        uint256[] calldata amount,
        IERC20 token
    ) external;

    /**
     * withdraw several amounts of several tokens to several addresses
     * @param tokens sendToken list;
     */
    function withdrawToken(sendToken[] calldata tokens) external;

    function collect(Collector[] calldata flush) external;
}

