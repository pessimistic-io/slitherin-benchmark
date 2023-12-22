// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Initializable.sol";

import "./IController.sol";
import "./IFeeManager.sol";
import "./ILiquidityPool.sol";
import "./ITradePair.sol";
import "./IUserManager.sol";
import "./UnlimitedOwnable.sol";
import "./Constants.sol";

contract FeeManager is IFeeManager, UnlimitedOwnable, Initializable {
    using SafeERC20 for IERC20;

    /* ========== CONSTANTS ========== */

    /// @notice Maximum fee size that can be set is 50%.
    uint256 private constant MAX_FEE_SIZE = 50_00;

    /// @notice Stakers fee size
    uint256 public constant STAKERS_FEE_SIZE = 18_00;

    /// @notice Dev fee size
    uint256 public constant DEV_FEE_SIZE = 12_00;

    /// @notice Insurance fund fee size
    uint256 public constant INSURANCE_FUND_FEE_SIZE = 10_00;

    /* ========== STATE VARIABLES ========== */

    /// @notice Controller contract.
    IController public immutable controller;

    /// @notice manages fees per user.
    IUserManager public immutable userManager;

    /// @notice Referral fee size.
    /// @dev Denominated in BPS
    uint256 public referralFee;

    /// @notice Address to collect the stakers fees to.
    address public stakersFeeAddress;

    /// @notice Address to collect the dev fees to.
    address public devFeeAddress;

    /// @notice Address to collect the insurance fund fees to.
    address public insuranceFundFeeAddress;

    /// @notice Stores what fee size of the stakers fee does a whitelabel get
    mapping(address => uint256) public whitelabelFees;

    /// @notice Stores custom referral fee for users
    mapping(address => uint256) public customReferralFee;

    // Storage gap
    uint256[50] __gap;

    /**
     * @notice Constructs the FeeManager contract.
     * @param unlimitedOwner_ The global owner of Unlimited Protocol.
     * @param controller_ Controller contract.
     * @param userManager_ User manager contract.
     */
    constructor(IUnlimitedOwner unlimitedOwner_, IController controller_, IUserManager userManager_)
        UnlimitedOwnable(unlimitedOwner_)
    {
        controller = controller_;
        userManager = userManager_;
    }

    /**
     * @notice Initializes the FeeManager contract.
     * @param referralFee_ Referral fee size.
     * @param stakersFeeAddress_ Address to collect the stakers fees to.
     * @param devFeeAddress_ Address to collect the dev fees to.
     * @param insuranceFundFeeAddress_ Address to collect the insurance fund fees to.
     */
    function initialize(
        uint256 referralFee_,
        address stakersFeeAddress_,
        address devFeeAddress_,
        address insuranceFundFeeAddress_
    ) external onlyOwner initializer {
        _updateStakersFeeAddress(stakersFeeAddress_);
        _updateDevFeeAddress(devFeeAddress_);
        _updateInsuranceFundFeeAddress(insuranceFundFeeAddress_);

        _updateReferralFee(referralFee_);
    }

    /**
     * @notice Update referral fee.
     * @param referralFee_ Referral fee size in BPS.
     */
    function updateReferralFee(uint256 referralFee_) external onlyOwner {
        _updateReferralFee(referralFee_);
    }

    /**
     * @notice Update referral fee.
     * @param referralFee_ Fee size in BPS.
     */
    function _updateReferralFee(uint256 referralFee_) private {
        _checkFeeSize(referralFee_);

        referralFee = referralFee_;

        emit UpdatedReferralFee(referralFee_);
    }

    /**
     * @notice Update stakers fee address.
     * @param stakersFeeAddress_ Stakers fee address.
     */
    function updateStakersFeeAddress(address stakersFeeAddress_) external onlyOwner {
        _updateStakersFeeAddress(stakersFeeAddress_);
    }

    /**
     * @notice Update stakers fee address.
     * @param stakersFeeAddress_ Stakers fee address.
     */
    function _updateStakersFeeAddress(address stakersFeeAddress_) private nonZeroAddress(stakersFeeAddress_) {
        stakersFeeAddress = stakersFeeAddress_;

        emit UpdatedStakersFeeAddress(stakersFeeAddress_);
    }

    /**
     * @notice Update dev fee address.
     * @param devFeeAddress_ Dev fee address.
     */
    function updateDevFeeAddress(address devFeeAddress_) external onlyOwner {
        _updateDevFeeAddress(devFeeAddress_);
    }

    /**
     * @notice Update dev fee address.
     * @param devFeeAddress_ Dev fee address.
     */
    function _updateDevFeeAddress(address devFeeAddress_) private nonZeroAddress(devFeeAddress_) {
        devFeeAddress = devFeeAddress_;

        emit UpdatedDevFeeAddress(devFeeAddress_);
    }

    /**
     * @notice Update insurance fund fee address.
     * @param insuranceFundFeeAddress_ Insurance fund fee address.
     */
    function updateInsuranceFundFeeAddress(address insuranceFundFeeAddress_) external onlyOwner {
        _updateInsuranceFundFeeAddress(insuranceFundFeeAddress_);
    }

    /**
     * @notice Update insurance fund fee address.
     * @param insuranceFundFeeAddress_ Insurance fund fee address.
     */
    function _updateInsuranceFundFeeAddress(address insuranceFundFeeAddress_)
        private
        nonZeroAddress(insuranceFundFeeAddress_)
    {
        insuranceFundFeeAddress = insuranceFundFeeAddress_;

        emit UpdatedInsuranceFundFeeAddress(insuranceFundFeeAddress_);
    }

    /**
     * @notice Update insurance fund fee address.
     * @param whitelabelAddress_ Whitelabel address.
     * @param feeSize_ Whitelabel fee size.
     */
    function setWhitelabelFees(address whitelabelAddress_, uint256 feeSize_) external onlyOwner {
        _checkFeeSize(feeSize_);
        whitelabelFees[whitelabelAddress_] = feeSize_;

        emit SetWhitelabelFee(whitelabelAddress_, feeSize_);
    }

    /**
     * @notice Set custom referral fee for address.
     * @param referrer_ Referrer address.
     * @param feeSize_ Whitelabel fee size.
     */
    function setCustomReferralFee(address referrer_, uint256 feeSize_) external onlyOwner {
        _checkFeeSize(feeSize_);
        customReferralFee[referrer_] = feeSize_;

        emit SetCustomReferralFee(referrer_, feeSize_);
    }

    /**
     * @dev Checks if fee size is in bounds.
     */
    function _checkFeeSize(uint256 feeSize_) private pure {
        require(feeSize_ <= MAX_FEE_SIZE, "FeeManager::_checkFeeSize: Bad fee size");
    }

    /**
     * @notice Calculates the fee for a given user and amount.
     * @param user_ User address.
     * @param amount_ Amount to calculate fee for.
     * @return fee_ Fee amount.
     */
    function calculateUserOpenFeeAmount(address user_, uint256 amount_) external view returns (uint256) {
        return _calculateUserFeeAmount(user_, amount_);
    }

    /**
     * @notice Calculates the fee amount for a given amount and the leverage.
     * @dev The fee is calculated in such a way, that it can be deducted from amount_ to get the margin for a position.
     * The margin times the leverage will be of such a volume, that the feeAmount_ is exactly the fee given by the user fee.
     * This function allows for the user to choose the margin, while still paying exactly the correct feeAmount.
     * @param user_ User address.
     * @param amount_ Amount to calculate the fee for.
     * @param leverage_ Leverage to calculate the fee for.
     * @return feeAmount_ Fee amount.
     */
    function calculateUserOpenFeeAmount(address user_, uint256 amount_, uint256 leverage_)
        external
        view
        returns (uint256 feeAmount_)
    {
        uint256 userFee = userManager.getUserFee(user_);
        uint256 margin =
            amount_ * LEVERAGE_MULTIPLIER * FULL_PERCENT / (LEVERAGE_MULTIPLIER * FULL_PERCENT + leverage_ * userFee);
        uint256 volume = margin * leverage_ / LEVERAGE_MULTIPLIER;
        feeAmount_ = volume * userFee / FULL_PERCENT;
    }

    /**
     * @notice Calculates the fee amount for the increaseToLeverage function.
     * @dev The fee is calculated in such a way, that it can be deducted from margin_ to get the margin for a position.
     * The new margin times the targetLeverage will be of such a volume, that the feeAmount_ is exactly the fee given by the added volume.
     * This function allows for the user to choose the leverage, while still paying exactly the correct feeAmount.
     * @param user_ User address.
     * @param margin_ Current margin.
     * @param volume_ Current volume.
     * @param targetLeverage_ Leverage to calculate the fee for.
     * @return feeAmount_ Fee amount.
     */
    function calculateUserExtendToLeverageFeeAmount(
        address user_,
        uint256 margin_,
        uint256 volume_,
        uint256 targetLeverage_
    ) external view returns (uint256 feeAmount_) {
        uint256 userFee = userManager.getUserFee(user_);
        uint256 addedVolume = (margin_ * targetLeverage_ / LEVERAGE_MULTIPLIER - volume_) * FULL_PERCENT
            * LEVERAGE_MULTIPLIER / (userFee * targetLeverage_ + FULL_PERCENT * LEVERAGE_MULTIPLIER);
        feeAmount_ = addedVolume * userFee / FULL_PERCENT;
    }

    /**
     * @dev Calculates the fee for a given user and close operation.
     */
    function calculateUserCloseFeeAmount(address user_, uint256 amount_) external view returns (uint256) {
        return _calculateUserFeeAmount(user_, amount_);
    }

    /**
     * @notice This function returns the absolute value of a fee given a user and an amount.
     * @dev Calculates the user fee for a certain amount. Mainly used to open, close and alter positions.
     * @param user_ address of the user.
     * @param amount_ amount of the trade.
     * @return amount the amount to calculates the fees from.
     */
    function _calculateUserFeeAmount(address user_, uint256 amount_) private view returns (uint256) {
        return userManager.getUserFee(user_) * amount_ / FULL_PERCENT;
    }

    /**
     * @notice Deposits open fees.
     * @param user_ User that deposits the fees.
     * @param asset_ Asset to deposit the fees in.
     * @param amount_ Amount to deposit.
     * @param whitelabelAddress_ Whitelabel address or address(0) if not whitelabeled.
     */
    function depositOpenFees(address user_, address asset_, uint256 amount_, address whitelabelAddress_)
        external
        onlyValidTradePair
    {
        _spreadFees(msg.sender, user_, IERC20(asset_), amount_, whitelabelAddress_);
    }

    /**
     * @notice Deposits close fees.
     * @param user_ User that deposits the fees.
     * @param asset_ Asset to deposit the fees in.
     * @param amount_ Amount to deposit.
     * @param whitelabelAddress_ Whitelabel address or address(0) if not whitelabeled.
     */
    function depositCloseFees(address user_, address asset_, uint256 amount_, address whitelabelAddress_)
        external
        onlyValidTradePair
    {
        _spreadFees(msg.sender, user_, IERC20(asset_), amount_, whitelabelAddress_);
    }

    /**
     * @dev Distributes fee to the different recievers.
     */
    function _spreadFees(address tradePair_, address user_, IERC20 asset_, uint256 amount_, address whitelabelAddress_)
        private
    {
        if (amount_ == 0) {
            return;
        }

        // take referral fee (10%), if user has a referrer
        address referrer = userManager.getUserReferrer(user_);

        if (referrer != address(0)) {
            uint256 userReferralFee = referralFee;

            if (customReferralFee[referrer] > referralFee) {
                userReferralFee = customReferralFee[referrer];
            }

            uint256 referralFeeAmount = amount_ * userReferralFee / FULL_PERCENT;

            asset_.safeTransferFrom(tradePair_, referrer, referralFeeAmount);

            unchecked {
                amount_ -= referralFeeAmount;
            }

            emit ReferrerFeesPaid(referrer, address(asset_), referralFeeAmount, user_);
        }

        uint256 amountLeft = amount_;

        unchecked {
            // pay to UWU stakers
            uint256 stakersFeeAmount = amount_ * STAKERS_FEE_SIZE / FULL_PERCENT;
            if (whitelabelAddress_ != address(0)) {
                uint256 feeSize = whitelabelFees[whitelabelAddress_];

                if (feeSize > 0) {
                    uint256 whitelabelFeeAmount = stakersFeeAmount * feeSize / FULL_PERCENT;

                    asset_.safeTransferFrom(msg.sender, whitelabelAddress_, whitelabelFeeAmount);
                    amountLeft -= whitelabelFeeAmount;
                    stakersFeeAmount -= whitelabelFeeAmount;

                    emit WhiteLabelFeesPaid(whitelabelAddress_, address(asset_), whitelabelFeeAmount, user_);
                }
            }

            // transfer to stakers address
            asset_.safeTransferFrom(msg.sender, stakersFeeAddress, stakersFeeAmount);
            amountLeft -= stakersFeeAmount;

            // transfer to dev address
            uint256 devFeeAmount = amount_ * DEV_FEE_SIZE / FULL_PERCENT;
            asset_.safeTransferFrom(msg.sender, devFeeAddress, devFeeAmount);
            amountLeft -= devFeeAmount;

            // transfer to insurance fund
            uint256 insuranceFundFeeAmount = amount_ * INSURANCE_FUND_FEE_SIZE / FULL_PERCENT;
            asset_.safeTransferFrom(msg.sender, insuranceFundFeeAddress, insuranceFundFeeAmount);
            amountLeft -= insuranceFundFeeAmount;

            // transfer amount left to LP Adapter
            _depositFeesToLiquidityPools(msg.sender, asset_, amountLeft);

            emit SpreadFees(
                address(asset_),
                stakersFeeAmount,
                devFeeAmount,
                insuranceFundFeeAmount,
                amountLeft, // liquidityPoolFeeAmount
                user_
            );
        }
    }

    /**
     * @notice Deposits borrow fees from TradePair.
     * @param asset_ Asset to deposit the fees in.
     * @param amount_ Amount to deposit.
     */
    function depositBorrowFees(address asset_, uint256 amount_) external onlyValidTradePair {
        if (amount_ > 0) {
            _depositFeesToLiquidityPools(msg.sender, IERC20(asset_), amount_);
        }
    }

    /**
     * @dev Deposits fees to the liquidity pools.
     */
    function _depositFeesToLiquidityPools(address tradePair_, IERC20 asset_, uint256 amount_) private {
        ILiquidityPoolAdapter liquidityPoolAdapter = _getLiquidityPoolAdapterFromTradePair(tradePair_);

        asset_.safeTransferFrom(tradePair_, address(liquidityPoolAdapter), amount_);
        liquidityPoolAdapter.depositFees(amount_);
    }

    /**
     * @dev Returns the liquidity pool adapter from a trade pair.
     */
    function _getLiquidityPoolAdapterFromTradePair(address tradePair_) private view returns (ILiquidityPoolAdapter) {
        return ITradePair(tradePair_).liquidityPoolAdapter();
    }

    /* ========== RESTRICTION FUNCTIONS ========== */

    /**
     * @dev Reverts if TradePair is not valid.
     */
    function _onlyValidTradePair() private view {
        require(controller.isTradePair(msg.sender), "FeeManager::_onlyValidTradePair: Caller is not a trade pair");
    }

    /**
     * @dev Reverts if address is zero address
     */
    function _nonZeroAddress(address address_) private pure {
        require(address_ != address(0), "FeeManager::_nonZeroAddress: Address cannot be 0");
    }

    /* ========== MODIFIERS ========== */

    modifier onlyValidTradePair() {
        _onlyValidTradePair();
        _;
    }

    modifier nonZeroAddress(address address_) {
        _nonZeroAddress(address_);
        _;
    }
}

