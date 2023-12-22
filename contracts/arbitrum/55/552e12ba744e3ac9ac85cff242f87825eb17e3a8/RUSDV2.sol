// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./MintableBaseTokenV2.sol";
import "./UUPSUpgradeable.sol";

contract RUSD is MintableBaseTokenV2, UUPSUpgradeable {
    mapping(address => bool) public blacklist;
    uint256[50] private __gap;

    event SetBlacklist(address account, bool isBlacklist);

    function initialize() public initializer {
        _initialize("Roseon USD", "RUSD", 0);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {

    }

    function id() external pure returns (string memory _name) {
        return "RUSD";
    }

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _checkBlacklist(msg.sender);
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _checkBlacklist(_sender);
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function _checkBlacklist(address _account) internal view {
        require(!blacklist[_account], "Blacklist");
    }

    function setBlacklist(address _account, bool _isBlacklist) external onlyOwner {
        blacklist[_account] = _isBlacklist;
        emit SetBlacklist(_account, _isBlacklist);
    }
}

