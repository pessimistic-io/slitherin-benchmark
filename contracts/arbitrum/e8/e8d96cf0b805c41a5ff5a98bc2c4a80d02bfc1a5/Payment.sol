// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IERC20.sol";
import "./ERC20_IERC20Upgradeable.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./AccountsFactory.sol";
import "./IPayment.sol";

contract Payment is Ownable, AccountsFactory, IPayment {
    using SafeERC20 for IERC20;
    using Address for address payable;
    mapping(uint256 => bool) used;

    constructor(address implementation) AccountsFactory(implementation) {}

    //public function accept eth
    receive() external payable {}

    fallback() external payable {}

    /**
     * withdrawEth to an address
     * @param to destination address
     * @param amount amount to send
     */

    function withdrawEth(
        address to,
        uint256 amount
    ) external override onlyOwner {
        payable(to).sendValue(amount);
    }

    /**
     * send ETH to several users;
     * @param to array of destinations
     * @param amount array of amounts
     */
    function withdrawEth(
        address[] calldata to,
        uint256[] calldata amount
    ) external override onlyOwner {
        for (uint8 i = 0; i < to.length; i++) {
            payable(to[i]).sendValue(amount[i]);
        }
    }

    /**
     * withdraw Tokens to an address
     * @param to destination address
     * @param amount amout to send
     * @param token token to send
     */
    function withdrawToken(
        address to,
        uint256 amount,
        IERC20 token
    ) external override onlyOwner {
        token.safeTransfer(to, amount);
    }

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
    ) external override onlyOwner {
        for (uint8 i = 0; i < to.length; i++) {
            token.safeTransfer(to[i], amount[i]);
        }
    }

    /**
     * withdraw several amounts of several tokens to several addresses
     * @param tokens sendToken list;
     */
    function withdrawToken(
        sendToken[] calldata tokens
    ) external override onlyOwner {
        for (uint8 i = 0; i < tokens.length; i++) {
            if (address(tokens[i].token) == address(0)) {
                payable(tokens[i].to).sendValue(tokens[i].amount);
            } else {
                tokens[i].token.safeTransfer(tokens[i].to, tokens[i].amount);
            }
        }
    }

    /**
     * Move tokens from several account to this wallet
     * @param flush Array of Flush params
     */

    function collect(Collector[] calldata flush) external override {
        for (uint8 i = 0; i < flush.length; i++) {
            if (flush[i].token == address(0)) {
                flush[i].from.flush();
            } else {
                flush[i].from.flushToken(flush[i].token);
            }
        }
    }

    /**
     * Allow address to spend an accounts balance;
     * @param account  account contract to spend
     * @param token account balance to spend
     * @param spender the address spending tokens
     */
    function approveAccount(
        IAccount account,
        IERC20Upgradeable token,
        address spender
    ) public onlyOwner {
        account.approve(token, spender);
    }

    /**
     * Allow spender to spend from  multiple accounts
     * @param accounts account contract to spend
     * @param token account balance to spend
     * @param spender the address spending tokens
     */

    function approveAccount(
        IAccount[] calldata accounts,
        IERC20Upgradeable token,
        address spender
    ) public onlyOwner {
        for (uint8 i = 0; i < accounts.length; i++) {
            accounts[i].approve(token, spender);
        }
    }

    /**
     * Allow spender to spend from  several tokens
     * @param account account contract to spend
     * @param tokens account balance to spend
     * @param spender the address spending tokens
     */

    function approveAccount(
        IAccount account,
        IERC20Upgradeable[] calldata tokens,
        address spender
    ) public onlyOwner {
        for (uint8 i = 0; i < tokens.length; i++) {
            account.approve(tokens[i], spender);
        }
    }

    function approve(
        IERC20Upgradeable token,
        address spender
    ) public onlyOwner {
        token.approve(spender, type(uint256).max);
    }

    function approve(
        IERC20Upgradeable[] calldata tokens,
        address spender
    ) public onlyOwner {
        for (uint8 i = 0; i < tokens.length; i++) {
            tokens[i].approve(spender, type(uint256).max);
        }
    }

    function transferAccountOwnership(
        IAccount account,
        address to
    ) public onlyOwner {
        account.transferOwnership(to);
    } 
    
    function transferAccountOwnership(
        IAccount[] calldata account,
        address to
    ) public onlyOwner {
         for (uint8 i = 0; i < account.length; i++) {
             account[i].transferOwnership(to);
        }
       
    }
}

