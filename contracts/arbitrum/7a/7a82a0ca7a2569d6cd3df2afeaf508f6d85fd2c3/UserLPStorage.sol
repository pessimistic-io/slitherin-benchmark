//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Libs
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";

/**
 * Olds unused user funds from LP vault.
 */
contract UserLPStorage is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public unusedDeposited;

    uint256 public unusedExited;

    IERC20 public lpToken;

    address public vault;

    constructor(address _lpToken) {
        lpToken = IERC20(_lpToken);
    }

    /**
     * Set vault that does the operations
     * @param _vault vault
     */
    function setVault(address _vault) public onlyOwner {
        vault = _vault;
    }

    /**
     * Stores amount when the user signaled exit
     * @param _value amount to store
     */
    function storeRefund(uint256 _value) public nonReentrant onlyVault {
        unusedExited += _value;
        lpToken.safeTransferFrom(vault, address(this), _value);
        emit StoredRefund(msg.sender, _value);
    }

    /**
     * Called when the user claims an exit.
     * @param _to user address
     * @param _value value sent to user
     */
    function refundCustomer(address _to, uint256 _value) public nonReentrant onlyVault {
        if (_value > unusedExited) {
            revert NOT_ENOUGH_BALANCE();
        }
        unusedExited -= _value;
        lpToken.safeTransfer(_to, _value);
        emit Refunded(msg.sender, _value, _to);
    }

    /**
     * Called when a user cancels a deposit.
     * @param _to user address
     * @param _value value sent to user
     */
    function refundDeposit(address _to, uint256 _value) public nonReentrant onlyVault {
        if (_value > unusedDeposited) {
            revert NOT_ENOUGH_BALANCE();
        }
        unusedDeposited -= _value;
        lpToken.safeTransfer(_to, _value);
        emit RefundedDeposit(msg.sender, _value, _to);
    }

    /**
     * Stores a user deposit before the funds are used next epoch.
     * @param _value value stored
     */
    function storeDeposit(uint256 _value) public nonReentrant onlyVault {
        unusedDeposited += _value;
        lpToken.safeTransferFrom(vault, address(this), _value);
        emit StoredDeposit(msg.sender, _value);
    }

    /**
     * Sends all stored unused deposits to the vault (refunds are not sent)
     */
    function depositToVault() public nonReentrant onlyVault {
        if (unusedDeposited != 0) {
            lpToken.safeTransfer(vault, unusedDeposited);
            emit DepositToVault(msg.sender, unusedDeposited);
        }
        unusedDeposited = 0;
    }

    /**
     * Sends a specific amount of deposits to the vault (refunds are not sent)
     * @param _value amount to send
     */
    function depositToVault(uint256 _value) public nonReentrant onlyVault {
        if (_value > unusedDeposited) {
            revert NOT_ENOUGH_BALANCE();
        }
        lpToken.safeTransfer(vault, _value);
        unusedDeposited -= _value;
        emit DepositToVault(msg.sender, _value);
    }

    function emergencyWithdraw(address _to) public onlyOwner {
        uint256 value = lpToken.balanceOf(address(this));
        lpToken.safeTransfer(_to, value);
    }

    // ============================== Events ==============================

    /**
     * @notice Emmited when a refund is stored in this contract
     * @param _vault vault that stored
     * @param _value value that was stored
     */
    event StoredRefund(address _vault, uint256 _value);

    /**
     * @notice Emmited when a deposit is stored in this contract
     * @param _vault vault that stored
     * @param _value value that was stored
     */
    event StoredDeposit(address _vault, uint256 _value);

    /**
     * @notice Emmited when a claim is sent to the user
     * @param _vault vault that stored
     * @param _value value that was stored
     * @param _user user that received the funds
     */
    event Refunded(address _vault, uint256 _value, address _user);

    /**
     * @notice Emmited when a deposit for a future epoch is sent to the user
     * @param _vault vault that stored
     * @param _value value that was stored
     * @param _user user that received the funds
     */
    event RefundedDeposit(address _vault, uint256 _value, address _user);

    /**
     * @notice Emmited when the vault requests funds for next epoch
     * @param _vault vault that stored
     * @param _value value that was stored
     */
    event DepositToVault(address _vault, uint256 _value);

    // ============================== Modifiers ==============================

    modifier onlyVault() {
        if (msg.sender != vault) {
            revert Only_Vault();
        }
        _;
    }

    // ============================== Erors ==============================

    error Only_Vault(); // Only vault
    error NOT_ENOUGH_BALANCE();
}

