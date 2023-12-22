// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;
import "./ERC20_IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IAccount.sol";
import "./IPayment.sol";

/**
 * Contract that will forward any incoming Ether to the creator of the contract
 *
 */
contract Account is IAccount, Initializable, OwnableUpgradeable {
    // Address to which any funds sent to this contract will be forwarded
    using AddressUpgradeable for address payable;
    address payable public coldWallet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    error TokenBalanceIsZero();

    constructor() {
        // lock the proxy
        _disableInitializers();
    }

    /**
     * Initialize the contract, and sets the destination address to that of the creator
     */
    function initialize() external override initializer {
        coldWallet = payable(_msgSender());
        __Ownable_init();
        flush();
    }

    /**
     * Default function; Gets called when data is sent but does not match any other function
     */
    fallback() external payable {
        flush();
    }

    /**
     * Default function; Gets called when Ether is deposited with no data, and forwards it to the parent address
     */
    receive() external payable {
        flush();
    }

    /**
     * Flush a tokens balance to
     * @param token Token to flush
     */
    function flushToken(address token) external {
        IERC20Upgradeable instance = IERC20Upgradeable(token);
        uint256 forwarderBalance = instance.balanceOf(address(this));
        if (forwarderBalance == 0) revert TokenBalanceIsZero();
        instance.safeTransfer(coldWallet, forwarderBalance);
    }

    function flushToken(address[] calldata tokens) external {
        for (uint8 i = 0; i < tokens.length; i++) {
            IERC20Upgradeable instance = IERC20Upgradeable(tokens[i]);
            uint256 forwarderBalance = instance.balanceOf(address(this));
            if (forwarderBalance > 0)
                instance.safeTransfer(coldWallet, forwarderBalance);
        }
    }
    /**
     * Flush the entire balance of the contract to the parent address.
     */
    function flush() public override {
        uint256 value = address(this).balance;
        if (value > 0) {
            coldWallet.sendValue(value);
        }
    }

    function approve(IERC20Upgradeable token, address spender) public onlyOwner  {
        token.approve(spender, type(uint256).max);
    }

    function approve(IERC20Upgradeable[] calldata tokens, address spender) public onlyOwner {
        for (uint8 i = 0; i < tokens.length; i++) {
            tokens[i].approve(spender, type(uint256).max);
        }
    }

    function transferOwnership(address newOwner) public  onlyOwner override(OwnableUpgradeable, IAccount) {
        super.transferOwnership(newOwner);
    }
     

}

