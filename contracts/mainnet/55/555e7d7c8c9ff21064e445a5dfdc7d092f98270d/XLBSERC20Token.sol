pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "./ERC20.sol";
import "./IERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./ERC2771Recipient.sol";

contract XLBSERC20Token is ERC20, ERC20Burnable, Ownable, AccessControl{
    bytes32 public constant CAN_MINT = keccak256("CAN_MINT");

    constructor() ERC20("XLBS", "XLBS") {
        // caller is not the owner! First deploy everything, then transfer ownership of contracts to gnosis safe! ( if you'd like automated setup )
        transferOwnership(address(0x8963B6f4e897c0E1378EC8C38D516215595f6fBc));
        _setupRole(DEFAULT_ADMIN_ROLE, owner());
    }
    function mint(address to, uint256 amount) external {
      require(hasRole(CAN_MINT, _msgSender()), "Caller cannot mint");
      _mint(to, amount);
    }

    function addMinter(address account) external onlyOwner {
        grantRole(CAN_MINT, account);
    }

    function removeMinter(address account) external onlyOwner {
        revokeRole(CAN_MINT, account);
    }
}   
