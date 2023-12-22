// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IFeeBankCharger.sol";
import "./IFeeBank.sol";

/// @title Contract with fee mechanism for solvers to pay for using the system
contract FeeBank is IFeeBank, Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();

    IERC20 private immutable _token;
    IFeeBankCharger private immutable _charger;

    mapping(address => uint256) private _accountDeposits;

    constructor(IFeeBankCharger charger_, IERC20 inch_, address owner_) {
        if (address(charger_) == address(0)) revert ZeroAddress();
        if (address(inch_) == address(0)) revert ZeroAddress();
        _charger = charger_;
        _token = inch_;
        transferOwnership(owner_);
    }

    function availableCredit(address account) external view returns (uint256) {
        return _charger.availableCredit(account);
    }

    /**
     * @notice Increment sender's availableCredit in Settlement contract.
     * @param amount The amount of 1INCH sender pay for incresing.
     * @return totalAvailableCredit The total sender's availableCredit after deposit.
     */
    function deposit(uint256 amount) external returns (uint256 totalAvailableCredit) {
        return _depositFor(msg.sender, amount);
    }

    /**
     * @notice Increases account's availableCredit in Settlement contract.
     * @param account The account whose availableCredit is increased by the sender.
     * @param amount The amount of 1INCH sender pay for incresing.
     * @return totalAvailableCredit The total account's availableCredit after deposit.
     */
    function depositFor(address account, uint256 amount) external returns (uint256 totalAvailableCredit) {
        return _depositFor(account, amount);
    }

    /**
     * @notice See {deposit}. This method uses permit for deposit without prior approves.
     * @param amount The amount of 1INCH sender pay for incresing.
     * @param permit The data with sender's permission via token.
     * @return totalAvailableCredit The total sender's availableCredit after deposit.
     */
    function depositWithPermit(uint256 amount, bytes calldata permit) external returns (uint256 totalAvailableCredit) {
        return depositForWithPermit(msg.sender, amount, permit);
    }

    /**
     * @notice See {depositFor} and {depositWithPermit}.
     */
    function depositForWithPermit(
        address account,
        uint256 amount,
        bytes calldata permit
    ) public returns (uint256 totalAvailableCredit) {
        _token.safePermit(permit);
        return _depositFor(account, amount);
    }

    /**
     * @notice Returns unspent availableCredit.
     * @param amount The amount of 1INCH sender returns.
     * @return totalAvailableCredit The total sender's availableCredit after withdrawal.
     */
    function withdraw(uint256 amount) external returns (uint256 totalAvailableCredit) {
        return _withdrawTo(msg.sender, amount);
    }

    /**
     * @notice Returns unspent availableCredit to specific account.
     * @param account The account which get withdrawaled tokens.
     * @param amount The amount of withdrawaled tokens.
     * @return totalAvailableCredit The total sender's availableCredit after withdrawal.
     */
    function withdrawTo(address account, uint256 amount) external returns (uint256 totalAvailableCredit) {
        return _withdrawTo(account, amount);
    }

    /**
     * @notice Admin method returns commissions spent by users.
     * @param accounts Accounts whose commissions are being withdrawn.
     * @return totalAccountFees The total amount of accounts commissions.
     */
    function gatherFees(address[] memory accounts) external onlyOwner returns (uint256 totalAccountFees) {
        uint256 accountsLength = accounts.length;
        unchecked {
            for (uint256 i = 0; i < accountsLength; ++i) {
                address account = accounts[i];
                uint256 accountDeposit = _accountDeposits[account];
                uint256 availableCredit_ = _charger.availableCredit(account);
                _accountDeposits[account] = availableCredit_;
                totalAccountFees += accountDeposit - availableCredit_;  // overflow is impossible due to checks in FeeBankCharger
            }
        }
        _token.safeTransfer(msg.sender, totalAccountFees);
    }

    function _depositFor(address account, uint256 amount) internal returns (uint256 totalAvailableCredit) {
        if (account == address(0)) revert ZeroAddress();
        _token.safeTransferFrom(msg.sender, address(this), amount);
        unchecked {
            _accountDeposits[account] += amount;  // overflow is impossible due to limited _token supply
        }
        totalAvailableCredit = _charger.increaseAvailableCredit(account, amount);
    }

    function _withdrawTo(address account, uint256 amount) internal returns (uint256 totalAvailableCredit) {
        totalAvailableCredit = _charger.decreaseAvailableCredit(msg.sender, amount);
        unchecked {
            _accountDeposits[msg.sender] -= amount;  // overflow is impossible due to checks in FeeBankCharger
        }
        _token.safeTransfer(account, amount);
    }
}

