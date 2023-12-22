// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract NftperpWhitelist is OwnableUpgradeable {
    mapping(address => bool) private _whitelistMap;

    function initialize() external initializer {
        __Ownable_init();
    }

    function setWhitelist(address[] memory _wls, bool[] memory _statuses) external onlyOwner {
        uint256 len = _wls.length;
        require(len == _statuses.length, "length mismatch");
        for (uint256 i; i < len; ) {
            address wl = _wls[i];
            bool status = _statuses[i];
            bool currentStatus = _whitelistMap[wl];
            if (status != currentStatus) {
                _whitelistMap[wl] = status;
            }
            unchecked {
                ++i;
            }
        }
    }

    function isWhitelist(address _trader) external view returns (bool) {
        return _whitelistMap[_trader];
    }

    function recoverTokens(address _token, uint256 _amount) external onlyOwner {
        _token.call(abi.encodeWithSignature("transfer(address,uint256)", owner(), _amount));
    }
}

