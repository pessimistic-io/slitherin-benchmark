// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./ERC20.sol";
import { Initializable } from "./Initializable.sol";

import { mPendleConvertorBaseUpg } from "./mPendleConvertorBaseUpg.sol";

/// @title mPendleConvertor simply mints 1 mPendle for each mPendle convert.
/// @author Magpie Team
/// @notice mPENDLE is a token minted when 1 PENDLE deposit on penpie, the deposit is irreversible, user will get mPendle instead.

contract mPendleConvertorSideChain is Initializable, mPendleConvertorBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ Constructor ============ */

    function __mPendleConvertorSideChain_init(
        address _pendleStaking,
        address _pendle,
        address _mPendleOFT,
        address _masterPenpie
    ) public initializer {
        __Ownable_init();
        pendleStaking = _pendleStaking;
        pendle = _pendle;
        mPendleOFT = _mPendleOFT;
        masterPenpie = _masterPenpie;
    }

    function withdrawToAdmin() external onlyOwner {
        uint256 allPendle = IERC20(pendle).balanceOf(address(this));
        IERC20(pendle).safeTransfer(owner(), allPendle);
        emit PendleWithdrawToAdmin(owner(), allPendle);
    }
}

