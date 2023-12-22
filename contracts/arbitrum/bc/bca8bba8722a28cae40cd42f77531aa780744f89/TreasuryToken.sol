// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// contracts from OpenZeppelin Contracts (last updated v4.8.0)
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./SafeMath.sol";

/**
 * @title Treasury Token
 * @author Satoshi LIRA Team
 * @custom:security-contact contact@satoshilira.io
 */
contract TreasuryToken is Ownable, ERC20 {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    address public token;
    uint public rate;

    bool public isMintable = false;

    constructor (
        string memory name_,
        string memory symbol_,
        address token_,
        uint rate_
    ) ERC20(name_, symbol_) {
        token = token_;
        rate = rate_;
    }

    /**
     * Treasury tokens have 8 decimals, we override the default ERC20
     */
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    /**
     * Mint a treasury tokens locking the asocciated token
     * @param to the address who receive the treasury tokens
     * @param amount amount of associaced token to lock
     */
    function mint(address to, uint amount) public onlyOwner {
        ERC20(token).safeTransferFrom(owner(), address(this), amount.mul(rate));

        _mint(to, amount);
    }

    /**
     * Burn LIRA tokens only, the burn will not send back WBTC
     * 
     * @param amount of LIRA tokens to burn
     */
    function burn(uint256 amount) public onlyOwner {
        _burn(owner(), amount);
    }

    /**
     * Emergecy function to recover tokens sended in the contract by mistake
     * @param tokenAddress ERC20 address, cannot be the WBTC address
     */
    function emergencyWithdraw(address tokenAddress) public onlyOwner {
        require(tokenAddress != token, "TreasuryToken: cannot withdraw locked token");

        ERC20(tokenAddress).safeTransfer(owner(), ERC20(tokenAddress).balanceOf(address(this)));
    }
}

