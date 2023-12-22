// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IWETH} from "./IWETH.sol";
import {IReferralStorage} from "./IReferralStorage.sol";
import {AdminUpgradeable} from "./AdminUpgradeable.sol";
import {IFeeSettlement} from "./IFeeSettlement.sol";
import {Constants} from "./Constants.sol";
import {IZLKDiscountReader} from "./IZLKDiscountReader.sol";

contract FeeSettlement is IFeeSettlement, ReentrancyGuard, AdminUpgradeable {
    using SafeERC20 for IERC20;
    using SafeTransferLib for address;

    address public immutable weth;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_FEE_POINTS = 30; // 0.3%

    IReferralStorage public referralStorage;
    uint256 public feeShare; // e.g. 10 for 0.1%
    uint256 public feeDiscount; // e.g. 2000 for 20%
    uint256 public feeRebate; // e.g. 5000 for 50%/50%, 2500 for 75% fee/25% rebate
    address public feeTo;

    IZLKDiscountReader public zlkDiscountReader;

    error InvalidFeeShare();
    error InvalidFeeDiscount();
    error InvalidFeeRebate();
    error InsufficientOutAmount();

    event PayRebates(
        address trader,
        address referrer,
        address tokenOut,
        uint256 discountAmount,
        uint256 rebateAmount
    );
    event SetReferralStorage(IReferralStorage referralStorage);
    event SetZLKDiscountReader(IZLKDiscountReader zlkDiscountReader);
    event SetFeeShare(uint256 feeShare);
    event SetFeeDiscount(uint256 feeDiscount);
    event SetFeeRebate(uint256 feeRebate);
    event SetFeeTo(address feeTo);

    constructor(
        address _weth, 
        IReferralStorage _referralStorage,
        uint256 _feeShare,
        uint256 _feeDiscount,
        uint256 _feeRebate,
        address _feeTo
    ) {
        weth = _weth;
        referralStorage = _referralStorage;

        if (_feeShare > MAX_FEE_POINTS) revert InvalidFeeShare();
        if (_feeDiscount > BASIS_POINTS) revert InvalidFeeDiscount();
        if (_feeRebate > BASIS_POINTS) revert InvalidFeeRebate();
        feeShare = _feeShare;
        feeDiscount = _feeDiscount;
        feeRebate = _feeRebate;
        feeTo = _feeTo;
        _initializeAdmin(msg.sender);
    }

    /// @notice To receive ETH from router
    receive() external payable {}

    /// @notice Executes the fee settlement, including pay referrer rebates
    /// @param tokenOut Address of the output token
    /// @param amountOutMin Minimum amount of the output token
    /// @param from Trader address
    /// @param to Receiver address
    function processSettlement(
        address tokenOut,
        uint256 amountOutMin,
        address from,
        address to
    ) external override nonReentrant {
        bool isNative = tokenOut == Constants.NATIVE_ADDRESS;
        uint256 amount = isNative 
            ? address(this).balance 
            : IERC20(tokenOut).balanceOf(address(this));
        if (amount < amountOutMin) revert InsufficientOutAmount();
        (, address referrer) = referralStorage.getReferralInfo(from);
        uint256 basisfee = (amount * feeShare) / BASIS_POINTS;
        if (address(zlkDiscountReader) != address(0)) {
            (uint256 zlkdiscount, uint256 basis) = zlkDiscountReader.getZLKDiscount(from);
            basisfee = (basisfee * (basis - zlkdiscount)) / basis;
        }
        uint256 fee = referrer == address(0) 
            ? basisfee
            : (basisfee * (BASIS_POINTS - feeDiscount)) / BASIS_POINTS;
        if (amount - fee < amountOutMin) {
            // ensure that fee do not cause the transaction to fail 
            fee = amount - amountOutMin;
        }
        if (referrer != address(0)) {
            uint256 rebateAmount = (fee * feeRebate) / BASIS_POINTS;
            if (isNative) {
                IWETH(weth).deposit{value: fee}();
                IERC20(weth).safeTransfer(referrer, rebateAmount);
                IERC20(weth).safeTransfer(feeTo, IERC20(weth).balanceOf(address(this)));
            } else {
                IERC20(tokenOut).safeTransfer(referrer, rebateAmount);
                IERC20(tokenOut).safeTransfer(feeTo, fee - rebateAmount);
            }
            emit PayRebates(from, referrer, tokenOut, basisfee - fee, rebateAmount);
        } else {
            if (isNative) {
                IWETH(weth).deposit{value: fee}();
                IERC20(weth).safeTransfer(feeTo, IERC20(weth).balanceOf(address(this)));
            } else {
                IERC20(tokenOut).safeTransfer(feeTo, fee);
            }
        }
        if (isNative) {
            to.safeTransferETH(amount - fee);
        } else {
            IERC20(tokenOut).safeTransfer(to, amount - fee);
        }
    }

    // @notice Set referralStorage by admin
    /// @param _referralStorage ReferralStorage address
    function setReferralStorage(IReferralStorage _referralStorage) external onlyAdmin {
        referralStorage = _referralStorage;
        emit SetReferralStorage(_referralStorage);
    }

    // @notice Set zlkDiscountReader by admin
    /// @param _zlkDiscountReader ZLKDiscountReader address
    function setZLKDiscountReader(IZLKDiscountReader _zlkDiscountReader) external onlyAdmin {
        zlkDiscountReader = _zlkDiscountReader;
        emit SetZLKDiscountReader(_zlkDiscountReader);
    }

    /// @notice Set feeShare by admin
    /// @param _feeShare Percent of fee
    function setFeeShare(uint256 _feeShare) external onlyAdmin {
        if (_feeShare > MAX_FEE_POINTS) revert InvalidFeeShare();
        feeShare = _feeShare;
        emit SetFeeShare(_feeShare);
    }

    /// @notice Set feeDicount by admin
    /// @param _feeDiscount Percent of feeDiscount
    function setFeeDiscount(uint256 _feeDiscount) external onlyAdmin {
        if (_feeDiscount > BASIS_POINTS) revert InvalidFeeDiscount();
        feeDiscount = _feeDiscount;
        emit SetFeeDiscount(_feeDiscount);
    }

    /// @notice Set feeRebate by admin
    /// @param _feeRebate Percent of feeRebate
    function setFeeRebate(uint256 _feeRebate) external onlyAdmin {
        if (_feeRebate > BASIS_POINTS) revert InvalidFeeRebate();
        feeRebate = _feeRebate;
        emit SetFeeRebate(_feeRebate);
    }

    /// @notice Set feeTo by admin
    /// @param _feeTo FeeTo address
    function setFeeTo(address _feeTo) external onlyAdmin {
        feeTo = _feeTo;
        emit SetFeeTo(_feeTo);
    }
}

