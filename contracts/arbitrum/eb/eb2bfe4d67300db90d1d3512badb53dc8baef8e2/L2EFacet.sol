// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {WithStorage} from "./LibStorage.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

contract L2EFacet is WithStorage {
    using SafeERC20 for IERC20;

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    function setL2EToken(address token) external onlyOwner {
        ls().l2eToken = token;
    }

    function setL2ERatio(uint256 ratio) external onlyOwner {
        require(0 <= ratio && ratio <= 100, "ratio must be 0 to 100");
        ls().l2eRatio = ratio;
    }

    function payoutL2E(
        address _player,
        address _wagerToken,
        uint256 _wager,
        uint256 _payout
    ) external returns (uint256 l2eAmount) {
        require(bs().isGame[msg.sender], "Not authorized");
        uint8 wagerTokenDecimals = IERC20Metadata(_wagerToken).decimals();
        uint8 l2eTokenDecimals = IERC20Metadata(ls().l2eToken).decimals();
        uint8 decimalDiff;
        if (_wager <= _payout) {
            return 0;
        }
        if (wagerTokenDecimals < l2eTokenDecimals) {
            decimalDiff = l2eTokenDecimals - wagerTokenDecimals;
        }

        l2eAmount = (((_wager - _payout) * ls().l2eRatio) / 100) * (10 ** decimalDiff);
        uint256 l2eTokenBalance = IERC20Metadata(ls().l2eToken).balanceOf(address(this));
        if (l2eAmount > 0 && l2eTokenBalance >= l2eAmount) {
            IERC20(ls().l2eToken).safeTransfer(_player, l2eAmount);
        }
    }
}

