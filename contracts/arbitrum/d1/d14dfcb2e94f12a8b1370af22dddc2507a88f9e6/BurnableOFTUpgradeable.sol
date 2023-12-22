// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IERC20.sol";
import "./OFTUpgradeable.sol";

contract BurnableOFTUpgradeable is OFTUpgradeable {
    /* ========== GOVERNANCE ========== */
    function initialize(string memory _name, string memory _symbol, uint256 _initialSupply, address _lzEndpoint) public initializer {
        __OFTUpgradeable_init(_name, _symbol, _lzEndpoint);
        if (_initialSupply > 0) {
            _mint(_msgSender(), _initialSupply);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function burn(uint256 _amount) external {
        burnFrom(msg.sender, _amount);
    }

    function burnFrom(address _account, uint256 _amount) public {
        OFTUpgradeable._debitFrom(_account, 0, "", _amount);
    }

    /* ========== EMERGENCY ========== */
    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }
}

