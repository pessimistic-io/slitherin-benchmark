// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {IVault} from "./IVault.sol";
import {IwETH} from "./IwETH.sol";

/**
 * @notice Contract that allows users to deposit and redeem native ETH on the Jones wETH vault
 */
contract JonesWETHVaultV3Adapter is Ownable, ReentrancyGuard {
    IVault public vault;
    IwETH public wETH;
    IERC20 public share;

    /**
     * @param _vault The vault address
     * @param _wETH The wETH address
     * @param _governor The address of the owner of the adapter
     */
    constructor(
        address _vault,
        address _wETH,
        address _governor
    ) {
        if (_vault == address(0)) {
            revert INVALID_ADDRESS();
        }

        if (_wETH == address(0)) {
            revert INVALID_ADDRESS();
        }

        if (_governor == address(0)) {
            revert INVALID_ADDRESS();
        }

        vault = IVault(_vault);
        wETH = IwETH(_wETH);
        share = IERC20(vault.share());

        // Set the new owner
        _transferOwnership(_governor);
    }

    /**
     * @notice Wraps ETH and deposits into the Jones wETH vault
     * @dev Will revert if the contract is not whitelisted on the vault
     * @param _receiver The address that will receive the shares
     */
    function deposit(address _receiver) public payable virtual nonReentrant {
        _senderIsEligible();

        if (msg.value == 0) {
            revert INVALID_ETH_AMOUNT();
        }

        // Wrap the incoming ETH
        wETH.deposit{value: msg.value}();

        // Deposit and transfer shares to `msg.sender`
        wETH.approve(address(vault), msg.value);
        vault.deposit(msg.value, _receiver);
    }

    /**
     * @notice Redeems wETH from the Jones wETH vault and unwraps it
     * @dev Will revert fail if the contract is not whitelisted on the vault
     * @param _shares The amount of shares to burn
     * @param _receiver The address that will receive the ETH
     */
    function redeem(uint256 _shares, address _receiver)
        public
        payable
        virtual
        nonReentrant
    {
        if (_shares == 0) {
            revert INVALID_SHARES_AMOUNT();
        }

        // Transfer the `_shares` to the adapter
        share.transferFrom(msg.sender, address(this), _shares);

        // Redeem the `_shares` for `assets`
        share.approve(address(vault), _shares);
        uint256 assets = vault.redeem(_shares, address(this), address(this));

        // Unwrap the wETH
        wETH.withdraw(assets);

        // Transfer the unwrapped ETH to `_receiver`
        payable(_receiver).transfer(assets);
    }

    /**
     * @notice Updates the current vault to a new one
     * @dev Will revert if it's not called by `owner`
     * @param _newVault the address of the new vault
     */
    function updateVault(address _newVault) external onlyOwner {
        if (_newVault == address(0)) {
            revert INVALID_ADDRESS();
        }

        vault = IVault(_newVault);
        share = IERC20(vault.share());
    }

    /**
     * @notice Check if the message sender is a smart contract, if it is it will check if the
     * address is whitelisted on the vault contract
     * @dev This is needed because the adapter will be whitelisted so it can be used by other
     * contracts to bypass the vault whitelist
     */
    function _senderIsEligible() internal view {
        if (msg.sender != tx.origin) {
            if (!vault.whitelistedContract(msg.sender)) {
                revert UNAUTHORIZED();
            }
        }
    }

    receive() external payable {}

    error INVALID_ETH_AMOUNT();
    error INVALID_SHARES_AMOUNT();
    error UNAUTHORIZED();
    error INVALID_ADDRESS();
}

