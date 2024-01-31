// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.0;

import "./IEEVToken.sol";
import "./ERC20PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

/**
  Pausable ERC20 with added restriction that the token cannot be transferred 
  except to addresses in allowedRecipients
 */
contract EEVToken is ERC20PausableUpgradeable, OwnableUpgradeable, IEEVToken {
    mapping (address => bool) allowedRecipients;
    bool allowAllRecipients;

    function initialize() external initializer {
      __ERC20_init("EEVToken", "EEV");
      __ERC20Pausable_init();
      __Ownable_init();
    }

    // Pausable
    function pause() external onlyOwner {
      _pause();
    }

    function unpause() external onlyOwner {
      _unpause();
    }

    function mint(address to, uint256 amount) external virtual override onlyOwner{
      _mint(to, amount);
    }

    function setAllowAllRecipients(bool allowAll) external virtual override onlyOwner {
      allowAllRecipients = allowAll;
    }

    function addRecipient(address allowedAddress) external virtual override onlyOwner {
      allowedRecipients[allowedAddress] = true;
    }

    function removeRecipient(address allowedAddress) external virtual override onlyOwner {
      allowedRecipients[allowedAddress] = false;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
      super._beforeTokenTransfer(from, to, amount);

      require(from == address(0) || allowAllRecipients || allowedRecipients[to], "EEVToken: Invalid recipient");
    }
}

