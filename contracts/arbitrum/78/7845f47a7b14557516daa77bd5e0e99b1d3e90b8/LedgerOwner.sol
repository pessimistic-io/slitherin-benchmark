// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Ownable.sol";
import "./Errors.sol";
import "./IBrightPoolLedger.sol";
import "./BrightPoolWarden.sol";

/**
 * @dev An abstract class defining what ledger owner contracts has to have in common
 */
abstract contract LedgerOwner is Ownable {
    IBrightPoolLedger private _ledger;

    BrightPoolWarden private _warden;

    /**
     * @dev The admin address that is allowed to change cron and backend addresses
     */
    address private _admin;

    /**
     * @dev Event emitted upon ledger change commit
     */
    event NewLedger(address indexed ledger);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyLedger() {
        if (msg.sender != address(_ledger)) revert Restricted();
        _;
    }

    /**
     * @dev The modifier restricting method to be run by admin address only
     */
    modifier onlyAdmin() {
        if (_msgSender() != _admin) revert Restricted();
        _;
    }

    /**
     * @dev The modifier restricting method to be run by admin address only
     */
    modifier onlyAdminOrOwner() {
        if (_msgSender() != _admin && _msgSender() != owner()) revert Restricted();
        _;
    }

    constructor(address owner_, address admin_, BrightPoolWarden warden_) Ownable(owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        if (admin_ == address(0)) revert ZeroAddress();
        if (address(warden_) == address(0)) revert ZeroAddress();
        _warden = warden_;
        _admin = admin_;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function ledger() public view virtual returns (IBrightPoolLedger) {
        return _ledger;
    }

    /**
     * @dev Method changing an oracle. Only contract owner can do that.
     *
     * @param ledger_ New contract ledger. Might be address(0) to stop mint/burning mechanism.
     */
    function setLedger(IBrightPoolLedger ledger_) external virtual onlyAdminOrOwner {
        if (address(ledger_) == address(0)) revert ZeroAddress();
        // slither-disable-start reentrancy-no-eth
        // slither-disable-start reentrancy-events
        if (
            (address(_ledger) == address(0) && _warden.awaitingValue("ledger") == address(0))
                || _warden.changeValue(address(ledger_), "ledger", msg.sender)
        ) {
            _ledger = ledger_;
            emit NewLedger(address(ledger_));
        }
        // slither-disable-end reentrancy-events
        // slither-disable-end reentrancy-no-eth
    }

    function _setLedger(IBrightPoolLedger ledger_) internal {
        _ledger = ledger_;
    }

    function _getWarden() internal view returns (BrightPoolWarden) {
        return _warden;
    }
}

