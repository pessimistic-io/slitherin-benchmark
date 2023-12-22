// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// contracts from OpenZeppelin Contracts (last updated v4.8.0)
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./SafeMath.sol";

/**
 * @title Satoshi LIRA Token
 * @author Satoshi LIRA Team
 * @custom:security-contact contact@satoshilira.io
 * 
 * The final vision is to have built the all-in-one tool for the creation of a completely decentralized and free community.
 * To know more about the ecosystem you can find us on https://satoshilira.io don't trust, verify!
 */
contract LIRA is ERC20("Satoshi LIRA", "LIRA"), Ownable {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    address public wbtc;

    constructor(address wbtc_) {
        wbtc = wbtc_;

        // mint the presale to deployer address
        _mint(_msgSender(), 1_160_000_000 * 10 ** 8);
    }

    /**
     * LIRA have 8 decimals, we override the default ERC20
     */
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    /**
     * Mint LIRA tokens depositing WBTC
     * 
     * LIRA will be minted at rate: 1 Satoshi = 1 LIRA
     * 
     * @param amount of WBTC to lock in the contract to mint LIRA
     */
    function mint(uint256 amount) public onlyOwner {
        ERC20(wbtc).safeTransferFrom(owner(), address(this), amount);
        _mint(owner(), amount * 10 ** 8);
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
     * @param token ERC20 address, cannot be the WBTC address
     */
    function emergencyWithdraw(address token) public onlyOwner {
        require(token != wbtc, "LIRA: cannot withdraw wbtc");

        ERC20(token).safeTransfer(owner(), ERC20(token).balanceOf(address(this)));
    }
}

