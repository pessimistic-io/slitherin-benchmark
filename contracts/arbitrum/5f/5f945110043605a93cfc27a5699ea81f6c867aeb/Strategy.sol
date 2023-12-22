// SPDX-License-Identifier: GNU GPLv3
pragma solidity >=0.8.10;

// Libraries
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {ERC20} from "./ERC20.sol";
import {ERC4626} from "./ERC4626.sol";
import {ACL} from "./ACL.sol";

// Interfaces
import {IStrategy} from "./IStrategy.sol";

abstract contract Strategy is IStrategy, ACL, ERC4626 {
    using FixedPointMathLib for uint256;

    uint256 public ADMIN_FEE_BIPS = 0;
    uint256 public WITHDRAW_FEE_BIPS = 0;
    uint256 public REINVEST_FEE_BIPS = 0;
    uint256 constant BIPS_DIVISOR = 10000;

    address public feeRecipient;

    uint256 internal _totalAssets = 0;

    event RecoveredEth(uint256 amount);
    event RecoveredToken(address token, uint256 amount);

    event UpdateAdminFee(uint256 oldBips, uint256 newBips);
    event UpdateWithdrawFee(uint256 oldBips, uint256 newBips);
    event UpdateReinvestFee(uint256 oldBips, uint256 newBips);
    event UpdateFeeRecipient(address oldRecipient, address newRecipient);
    event Reinvest(uint256 newDeposits, uint256 newSupply);

    error NotEnoughRewards();
    error ZeroAddress();

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol) {}

    /// Set admin fee bips. Charged on every reinvest.
    /// @param newBips The new admin fee in bips
    function setAdminFeeBips(uint256 newBips) external onlyAdmin {
        uint256 oldBips = ADMIN_FEE_BIPS;
        ADMIN_FEE_BIPS = newBips;
        emit UpdateAdminFee(oldBips, newBips);
    }

    /// Set withdraw fee bips. Charged on every withdrawal.
    /// @param newBips The new withdraw fee in bips
    function setWithdrawFeeBips(uint256 newBips) external onlyAdmin {
        uint256 oldBips = WITHDRAW_FEE_BIPS;
        WITHDRAW_FEE_BIPS = newBips;
        emit UpdateWithdrawFee(oldBips, newBips);
    }

    /// Set reinvest fee bips. Charged on every reinvest and given to the person
    /// calling the function, used to incentivise vault compounding action.
    /// @param newBips The new reinvest fee in bips.
    function setReinvestFeeBips(uint256 newBips) external onlyAdmin {
        uint256 oldBips = REINVEST_FEE_BIPS;
        REINVEST_FEE_BIPS = newBips;
        emit UpdateReinvestFee(oldBips, newBips);
    }

    /// Set fee recipient address.
    /// @param newRecipient The new recipient address.
    function setFeeRecipient(address newRecipient) external onlyAdmin {
        if (newRecipient == address(0)) revert ZeroAddress();

        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit UpdateFeeRecipient(oldRecipient, newRecipient);
    }

    function totalAssets() public view override returns (uint256) {
        return _totalAssets;
    }

    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        uint256 assets = convertToAssets(shares);
        uint256 fees = _calcFees(assets, WITHDRAW_FEE_BIPS);
        return assets - fees;
    }

    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        // round up because assets -> shares conversion
        uint256 beforeFeesAmount = _calcBeforeFeesAmountRoundDown(
            assets,
            WITHDRAW_FEE_BIPS
        );
        return convertToShares(beforeFeesAmount);
    }

    function afterDeposit(
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        _totalAssets += assets;
        _afterDeposit(receiver, assets, shares);
    }

    function beforeWithdraw(
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        // round down because assets after fees -> assets before fees
        uint256 assetsBeforeFees = _calcBeforeFeesAmountRoundDown(
            assets,
            WITHDRAW_FEE_BIPS
        );

        _totalAssets -= assetsBeforeFees;

        _beforeWithdraw(receiver, assets, shares, assetsBeforeFees);
    }

    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        _beforeTokenTransfer(to, amount);
        bool success = super.transfer(to, amount);
        _afterTokenTransfer(to, amount);
        return success;
    }

    function _beforeTokenTransfer(address to, uint256 amount)
        internal
        virtual
    {}

    function _afterTokenTransfer(address to, uint256 amount) internal virtual {}

    function _afterDeposit(
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual;

    function _beforeWithdraw(
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 assetsBeforeFees
    ) internal virtual;

    function _withdrawAssets(address receiver, uint256 underlyingAssets)
        internal
        virtual
    {}

    function withdrawAssets(address receiver, uint256 assets)
        internal
        override
    {
        uint256 amtBeforeFees = _calcBeforeFeesAmountRoundDown(
            assets,
            WITHDRAW_FEE_BIPS
        );
        uint256 withdrawalFee = amtBeforeFees - assets;

        // transfer the underlying to user after deducting the withdrawal fee
        SafeTransferLib.safeTransfer(asset, receiver, assets);

        if (withdrawalFee > 0) {
            // transfer the withdrawal fee to admin
            SafeTransferLib.safeTransfer(asset, feeRecipient, withdrawalFee);
        }

        _withdrawAssets(receiver, assets);
    }

    function _calcFees(uint256 chargeableAmount, uint256 feeBips)
        internal
        pure
        returns (uint256)
    {
        return chargeableAmount.mulDivDown(feeBips, BIPS_DIVISOR);
    }

    function _calcBeforeFeesAmountRoundUp(
        uint256 afterFeesAmount,
        uint256 feeBips
    ) internal pure returns (uint256) {
        // fee = amt * bips / divisor
        // amountBeforeFees = receive + fees
        // amountBeforeFees = receive + receive * bips / divisor
        // amountBeforeFees = receive( 1 + bips / divisor)
        // amountBeforeFees = receive ( divisor + bips / bips)

        return afterFeesAmount.mulDivUp(BIPS_DIVISOR + feeBips, BIPS_DIVISOR);
    }

    function _calcBeforeFeesAmountRoundDown(
        uint256 afterFeesAmount,
        uint256 feeBips
    ) internal pure returns (uint256) {
        // fee = amt * bips / divisor
        // amountBeforeFees = receive + fees
        // amountBeforeFees = receive + receive * bips / divisor
        // amountBeforeFees = receive( 1 + bips / divisor)
        // amountBeforeFees = receive ( divisor + bips / bips)

        return afterFeesAmount.mulDivDown(BIPS_DIVISOR + feeBips, BIPS_DIVISOR);
    }

    function _distributeFees(
        ERC20 feeToken,
        address recipient,
        uint256 totalChargeableAmount,
        uint256 feeBips
    ) internal returns (uint256) {
        uint256 fee = _calcFees(totalChargeableAmount, feeBips);
        if (fee > 0) SafeTransferLib.safeTransfer(feeToken, recipient, fee);
        return fee;
    }

    function _distributeReinvestFees(
        ERC20 feeToken,
        uint256 totalChargeableAmount
    ) internal returns (uint256) {
        uint256 adminFees = _distributeFees(
            feeToken,
            feeRecipient,
            totalChargeableAmount,
            ADMIN_FEE_BIPS
        );
        uint256 reinvestFees = _distributeFees(
            feeToken,
            msg.sender,
            totalChargeableAmount,
            REINVEST_FEE_BIPS
        );
        return adminFees + reinvestFees;
    }

    function _distributeWithdrawFees(
        ERC20 feeToken,
        uint256 totalChargeableAmount
    ) internal returns (uint256) {
        return
            _distributeFees(
                feeToken,
                feeRecipient,
                totalChargeableAmount,
                WITHDRAW_FEE_BIPS
            );
    }

    function _withdrawWithFees(
        ERC20 token,
        address receiver,
        uint256 withdrawAmount
    ) internal virtual {
        uint256 withdrawFee = _distributeWithdrawFees(token, withdrawAmount);
        SafeTransferLib.safeTransfer(
            token,
            receiver,
            withdrawAmount - withdrawFee
        );
    }
}

