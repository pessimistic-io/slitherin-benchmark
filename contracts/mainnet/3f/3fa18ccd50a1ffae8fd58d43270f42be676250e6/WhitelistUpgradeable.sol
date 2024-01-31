// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./SafeMathUpgradeable.sol";

abstract contract WhitelistUpgradeable is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    struct WhitelistInfo {
        uint256 totalAmount;
        uint256 usedAmount;
    }

    mapping(address => WhitelistInfo) private _whitelist;

    /**
     * @dev Emitted when adding whitelist.
     * @param account The address to add in whitelist.
     * @param amount The whitelist amount of address to add.
     */
    event AddWhiteList(address account, uint256 amount);

    /**
     * @dev Emitted when using whitelist.
     * @param account The address to using whitelist.
     */
    event UseWhitelist(address account);

    /**
     * @dev Throws if called by any account other than the whitlist.
     */
    modifier onlyWhitelist() {
        require(checkWhitelist(_msgSender()), "Whitelist: caller is not the whitelist");
        _;
    }

    /**
     * @dev Returns true if the account is the whitlist.
     * @param account The address to check whitelist
     */
    function checkWhitelist(address account) public view virtual returns (bool) {
        return _availableAmount(account) > 0;
    }

    /**
     * @dev Returns whitelist count of the account
     * @param account The address to check whitelist count
     */
    function whitelist(address account) public view virtual returns (WhitelistInfo memory) {
        return _whitelist[account];
    }

    /**
     * @dev Add a account in whitelist.
     * @param account The address to add in whitelist.
     * @param amount The whitelist amount of address to add.
     */
    function _addWhitelist(address account, uint256 amount) internal virtual {
        require(account != address(0), "Whitelist: address is tho zero address");

        _whitelist[account].totalAmount = _whitelist[account].totalAmount + amount;
        emit AddWhiteList(account, amount);
    }

    /**
     * @dev Add a batch of addresses in whitelist.
     * @param accountList A batch of the address to add in whitelist.
     * @param amountList A batch of the whitelist amount of address to add.
     */
    function _addWhitelistBatch(address[] calldata accountList, uint256[] calldata amountList) internal virtual {
        require(accountList.length == amountList.length, "");

        for (uint256 i = 0; i < accountList.length ;i++) {
            require(accountList[i] != address(0), "Whitelist: address is tho zero address");

            _whitelist[accountList[i]].totalAmount = _whitelist[accountList[i]].totalAmount + amountList[i];
            emit AddWhiteList(accountList[i], amountList[i]);
        }
    }

    /**
     * @dev Add used amount of a account in whitelist.
     * @param account The address to using whitelist.
     */
    function _usedWhitelist(address account) internal virtual {
        require(checkWhitelist(account), "Whitelist: account is not the whitelist");

        _whitelist[account].usedAmount++;
        emit UseWhitelist(account);
    }

    /**
     * @dev Remove a account in whitelist.
     * @param account The address to remove in whitelist.
     */
    function _availableAmount(address account) internal view virtual returns (uint256) {
        return _whitelist[account].totalAmount.sub(_whitelist[account].usedAmount);
    }
}
