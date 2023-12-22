// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./MintableBaseToken.sol";
import "./UUPSUpgradeable.sol";

contract rUSD is MintableBaseToken, UUPSUpgradeable {
    mapping(address => bool) public blacklist;
    uint256[50] private __gap;

    event SetBlacklist(address account, bool isBlacklist);

    function initialize() public reinitializer(2) {
        _initialize("Roseon USD", "RUSD", 0);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {

    }

    function id() external pure returns (string memory _name) {
        return "RUSD";
    }

    function setBlacklist(address _account, bool _isBlacklist) external onlyOwner {
        blacklist[_account] = _isBlacklist;
        emit SetBlacklist(_account, _isBlacklist);
    }

    function _checkBlacklist(address _account) internal view {
        require(!blacklist[_account], "Blacklist");
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override whenNotPaused {
        if (!isMinter[msg.sender]) {
            _checkBlacklist(msg.sender);
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual override {
        _checkBlacklist(owner);
        super._spendAllowance(owner, spender, amount);
    }
}
