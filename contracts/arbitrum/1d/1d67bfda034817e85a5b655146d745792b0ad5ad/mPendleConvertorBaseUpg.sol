// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./ERC20.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { IMasterPenpie } from "./IMasterPenpie.sol";

import "./IPendleStaking.sol";
import "./IMintableERC20.sol";
import "./ILocker.sol";

/// @title mPendleConvertor simply mints 1 mPendle for each mPendle convert.
/// @author Magpie Team
/// @notice mPENDLE is a token minted when 1 PENDLE deposit on penpie, the deposit is irreversible, user will get mPendle instead.

abstract contract mPendleConvertorBaseUpg is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public pendleStaking;
    address public mPendleOFT;
    address public pendle;
    address public masterPenpie;

    uint256 public constant DENOMINATOR = 10000;
    uint256 immutable stakeMode = 1;
    uint256 immutable lockMode = 2;

    address public mPendleSV;

    /* ============ Events ============ */

    event mPendleConverted(address indexed user, uint256 amount, uint256 mode);
    event PendleStakingSet(address indexed _pendleStaking);
    event PendleConverted(uint256 _pendleAmount, uint256 _vePendleAmount);
    event PendleWithdrawToAdmin(address indexed user, uint256 amount);
    event mPendleSVUpdated(address indexed _mPendleSV);

    /* ============ Errors ============ */

    error MasterPenpieNotSet();
    error PendleStakingNotSet();
    error AddressZero();
    error MPendleSVNotSet();

    /* ============ External Functions ============ */

    /// @notice deposit PENDLE in magpie finance and get mPENDLE at a 1:1 rate
    /// @param _amount the amount of pendle
    /// @param _mode 0 doing nothing, 1 is convert and stake
    function convert(
        address _for,
        uint256 _amount,
        uint256 _mode
    ) external whenNotPaused nonReentrant {
        IERC20(pendle).safeTransferFrom(msg.sender, address(this), _amount);

        if (_mode == stakeMode) {
            if (masterPenpie == address(0)) revert MasterPenpieNotSet();
            IMintableERC20(mPendleOFT).mint(address(this), _amount);
            IERC20(mPendleOFT).safeApprove(address(masterPenpie), _amount);
            IMasterPenpie(masterPenpie).depositFor(
                address(mPendleOFT),
                _for,
                _amount
            );
            emit mPendleConverted(_for, _amount, _mode);
        } else if(_mode == lockMode) {
            if (mPendleSV == address(0)) revert MPendleSVNotSet();
            IMintableERC20(mPendleOFT).mint(address(this), _amount);
            IERC20(mPendleOFT).safeApprove(address(mPendleSV), _amount);
            ILocker(mPendleSV).lockFor(_amount,_for);
            emit mPendleConverted(_for, _amount, _mode);
        } else {
            IMintableERC20(mPendleOFT).mint(_for, _amount);
            emit mPendleConverted(_for, _amount, 0);
        }
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setPendleStaking(address _pendleStaking) external onlyOwner {
        if (_pendleStaking == address(0)) revert AddressZero();
        pendleStaking = _pendleStaking;

        emit PendleStakingSet(pendleStaking);
    }

    function setmPendleSV(address _mPendleSV) external onlyOwner {
        if (_mPendleSV == address(0)) revert AddressZero();
        mPendleSV = _mPendleSV;

        emit mPendleSVUpdated(_mPendleSV);
    }
}

