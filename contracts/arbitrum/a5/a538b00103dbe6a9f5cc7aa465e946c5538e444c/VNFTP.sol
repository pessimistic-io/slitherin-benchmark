// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract VNFTP is ERC20Upgradeable, OwnableUpgradeable {
    mapping(address => bool) public whitelist;

    function initialize() external initializer {
        __ERC20_init("VNFTP", "VNFTP");
        __Ownable_init();
    }

    function reward(address _beneficiary, uint256 _amount) external onlyOwner {
        _mint(_beneficiary, _amount);
    }

    /**
     * @dev whitelisted address is able to transfer tokens
     */
    function addWhitelist(address _user) external onlyOwner {
        whitelist[_user] = true;
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal view override {
        require(_from == address(0) || whitelist[_from], "transfers disabled");
    }
}

