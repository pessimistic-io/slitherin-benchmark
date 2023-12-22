// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ILiquidator.sol";
import "./IVaultLibrary.sol";
import "./ITreasury.sol";
import "./IfxToken.sol";
import "./IValidator.sol";
import "./IHandle.sol";
import "./IHandleComponent.sol";
import "./IInterest.sol";
import "./IfxKeeperPool.sol";
import "./IReferral.sol";

/**
 * @dev Implements vault redemptions and liquidations.
 */
contract Liquidator is
    ILiquidator,
    IValidator,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    IHandleComponent,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /** @dev The Handle contract interface */
    IHandle private handle;
    /** @dev The Treasury contract interface */
    ITreasury private treasury;
    /** @dev The VaultLibrary contract interface */
    IVaultLibrary private vaultLibrary;

    /** @dev Percent of the minimum CR over 100% to liquidate the target vault
             to. e.g. a value of 10 liquidated the vault to 110% of the
             minimum CR. */
    uint256 public override crScalar;
    /** @dev Threshold of Keeper Pools' ETH staked amount at which only
             the KeeperPool is allowed to perform liquidations. */
    uint256 public override keeperPoolThreshold;
    /** @dev Ratio of liquidation fee to be applied on redemptions. */
    uint256 public override redemptionFeeRatio;
    /** @dev Protocol ratio for redemption fees. */
    uint256 public override protocolRedemptionFeeRatio;

    modifier validFxToken(address token) {
        require(handle.isFxTokenValid(token), "IF");
        _;
    }

    /** @dev Proxy initialisation function */
    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
     * @dev Setter for Handle contract reference
     * @param _handle The Handle contract address
     */
    function setHandleContract(address _handle) public override onlyOwner {
        handle = IHandle(_handle);
        treasury = ITreasury(handle.treasury());
        vaultLibrary = IVaultLibrary(handle.vaultLibrary());
    }

    /**
     * @dev Setter for the safety post-liquidation CR scalar.
     * @param value The value to set crScalar to.
     */
    function setCrScalar(uint256 value) external override onlyOwner {
        crScalar = value;
    }

    /**
     * @dev Setter for the keeper pool threshold.
     * @param amount The amount of ETH to set the keeper pool threshold to.
     */
    function setKeeperPoolThreshold(uint256 amount)
        external
        override
        onlyOwner
    {
        keeperPoolThreshold = amount;
    }

    /**
     * @dev Setter for the redemption fee ratio.
     * @param ratio The ratio to set the redemptionFeeRatio to.
     */
    function setRedemptionFeeRatio(uint256 ratio) external override onlyOwner {
        require(ratio <= 1 ether, "0<R<=1");
        redemptionFeeRatio = ratio;
    }

    /**
     * @dev Setter for the protocol redemption fee ratio.
     * @param ratio The ratio to set the protocolRedemptionFeeRatio to.
     */
    function setProtocolRedemptionFeeRatio(uint256 ratio)
        external
        override
        onlyOwner
    {
        require(ratio <= 1 ether, "0<R<=1");
        protocolRedemptionFeeRatio = ratio;
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /**
     * @dev Buy collateral from a vault at a 1:1 asset/collateral price ratio.
            Token must have been pre-approved for transfer with input amount.
     * @param amount The amount of fxTokens to redeem with
     * @param token The fxToken to buy collateral with
     * @param from The account to purchase from
     * @param deadline The deadline for the transaction
     * @param referral The referral account
     */
    function buyCollateral(
        uint256 amount,
        address token,
        address from,
        uint256 deadline,
        address referral
    )
        external
        override
        dueBy(deadline)
        validFxToken(token)
        nonReentrant
        returns (
            uint256[] memory collateralAmounts,
            address[] memory collateralTypes,
            uint256 etherAmount
        )
    {
        IReferral(handle.referral()).setReferral(msg.sender, referral);
        return _buyCollateral(amount, token, from);
    }

    /**
     * @dev Buys collateral from multiple vaults until request is fulfilled.
            Token must have been pre-approved for transfer with input amount
     * @param amount The amount of fxTokens to redeem with
     * @param token The fxToken to buy collateral with
     * @param from The array of accounts to purchase from
     * @param deadline The deadline for the transaction
     */
    function buyCollateralFromManyVaults(
        uint256 amount,
        address token,
        address[] memory from,
        uint256 deadline,
        address referral
    )
        external
        override
        dueBy(deadline)
        validFxToken(token)
        nonReentrant
        returns (
            uint256[] memory collateralAmounts,
            address[] memory collateralTypes,
            uint256 etherAmount
        )
    {
        IReferral(handle.referral()).setReferral(msg.sender, referral);
        collateralTypes = handle.getAllCollateralTypes();
        collateralAmounts = new uint256[](collateralTypes.length);
        etherAmount = 0;
        // Working array to bypass stack becoming too deep.
        // 0 = tokenPrice
        // 1 = etherAmountLeft
        // 2 = loop iteration ether amount received from buyCollateral
        // 3 = from.length
        uint256[] memory a = new uint256[](4);
        a[0] = handle.getTokenPrice(token);
        a[1] = amount.mul(a[0]).div(vaultLibrary.getTokenUnit(token));
        a[2] = 0;
        a[3] = from.length;
        // Loop iteration amounts received.
        uint256[] memory amounts;
        for (uint256 i = 0; i < a[3]; i++) {
            {
                address[] memory ct;
                uint256 eAmount;
                (amounts, ct, eAmount) = _buyCollateral(amount, token, from[i]);
                a[2] = eAmount;
            }
            // Add to main amounts array.
            for (uint256 j = 0; j < collateralTypes.length; j++) {
                collateralAmounts[j] = collateralAmounts[j].add(amounts[j]);
            }
            a[1] = a[2] > a[1] ? 0 : a[1].sub(a[2]);
            etherAmount = etherAmount.add(a[2]);
            if (a[1] == 0) break;
            {
                amount = a[1].mul(1 ether).div(a[0]);
            }
        }
    }

    /**
     * @dev Buys collateral from a vault (AKA redemption/liquidation).
     * @param amount The amount of fxTokens to use for the collateral purchase.
     * @param token The fxToken to purchase with.
     * @param from The vault account to purchase from.
     */
    function _buyCollateral(
        uint256 amount,
        address token,
        address from
    )
        private
        returns (
            uint256[] memory collateralAmounts,
            address[] memory collateralTypes,
            uint256 etherAmount
        )
    {
        // If isLiquidation is false then the collateral purchase is
        // considered a redemption instead of a liquidation.
        // This is defined by the vault's collateral ratio.
        bool isLiquidation;
        {
            // Sender must have enough balance.
            require(IfxToken(token).balanceOf(msg.sender) >= amount, "IA");
            uint256 allowedAmount;
            (
                allowedAmount,
                isLiquidation
            ) = getAllowedBuyCollateralFromTokenAmount(token, from);
            require(allowedAmount > 0, "IA");
            if (amount > allowedAmount) amount = allowedAmount;
            // Vault must have a debt >= amount.
            require(handle.getDebt(from, token) >= amount, "IA");
        }
        // Calculate the amount in ETH excluding fees.
        etherAmount = handle.getTokenPrice(token).mul(amount).div(1 ether);
        // If redeeming, include fee calculation & withdrawal in this function.
        // For liquidation, fees are withdrawn in the liquidate function.
        if (!isLiquidation) {
            // Calculate and send protocol redemption fees.
            // Ether amount of redemption fees for both user and protocol.
            uint256 redemptionFee =
                etherAmount
                    .mul(vaultLibrary.getLiquidationFee(from, token))
                    .mul(redemptionFeeRatio)
                    .div(1e36); // (1 ether)^2
            // The fee cannot be over 100%.
            require(redemptionFee <= etherAmount, "0<R<=1");
            if (redemptionFee > 0 && protocolRedemptionFeeRatio > 0) {
                // Withdraw protocol fees.
                treasury.forceWithdrawAnyCollateral(
                    from,
                    handle.FeeRecipient(),
                    redemptionFee.mul(protocolRedemptionFeeRatio).div(1 ether),
                    token,
                    true
                );
            }
            // Update ether amount with user's cut of redemption fees.
            etherAmount = etherAmount.add(
                redemptionFee
                    .mul(uint256(1 ether).sub(protocolRedemptionFeeRatio))
                    .div(1 ether)
            );
        }
        {
            // Vault must have enough collateral.
            bool metAmount = false;
            (collateralTypes, collateralAmounts, metAmount) = vaultLibrary
                .getCollateralForAmount(from, token, etherAmount);
            require(metAmount, "CA");
            // Burn token.
            IfxToken(token).burn(msg.sender, amount);
            // Reduce vault debt and withdraw collateral to user.
            handle.updateDebtPosition(from, amount, token, false);
        }
        // Withdraw collateral for liquidation/redemption.
        uint256 j = collateralTypes.length;
        for (uint256 i = 0; i < j; i++) {
            if (collateralAmounts[i] == 0) continue;
            treasury.forceWithdrawCollateral(
                from,
                collateralTypes[i],
                msg.sender,
                collateralAmounts[i],
                token
            );
        }
        if (isLiquidation) {
            emit Liquidate(
                from,
                token,
                amount,
                collateralAmounts,
                collateralTypes
            );
        } else {
            emit Redeem(
                from,
                token,
                amount,
                collateralAmounts,
                collateralTypes
            );
        }
    }

    /**
     * @dev Calculates the liquidation trigger collateral ratio.
            Ratio with 18 decimals.
     * @param account The vault account.
     * @param fxToken The vault fxToken.
     * @return ratio The trigger CR for liquidation.
     */
    function getLiquidationRatio(address account, address fxToken)
        public
        view
        override
        returns (uint256 ratio)
    {
        ratio = vaultLibrary.getMinimumRatio(account, fxToken).mul(80).div(100);
        uint256 min = uint256(1 ether).mul(110).div(100);
        if (ratio < min) ratio = min;
    }

    /**
     * @dev Attempts to liquidate the target vault.
     * @param account The vault account.
     * @param fxToken The vault fxToken.
     */
    function liquidate(address account, address fxToken)
        external
        override
        validFxToken(fxToken)
        nonReentrant
        returns (
            uint256 fxAmount,
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts
        )
    {
        uint256 tokenPrice = handle.getTokenPrice(fxToken);
        ensurePoolThreshold(fxToken, tokenPrice);
        uint256 debt = vaultLibrary.getDebtAsEth(account, fxToken);
        uint256 collateral =
            vaultLibrary.getTotalCollateralBalanceAsEth(account, fxToken);
        // Require that the vault CR is under or at the liquidation trigger.
        validateLiquidation(account, fxToken, debt, collateral);
        uint256 feeRatio = vaultLibrary.getLiquidationFee(account, fxToken);
        // Ensure threshold and msg.sender are valid.
        (fxAmount, feeRatio) = getLiquidationFxAmount(
            account,
            fxToken,
            debt,
            collateral,
            feeRatio,
            tokenPrice
        );
        // Liquidate vault.
        (collateralTypes, collateralAmounts) = executeLiquidation(
            account,
            fxToken,
            fxAmount,
            tokenPrice
        );
        // Withdraw liquidation fees.
        collateralAmounts = withdrawFees(
            account,
            fxToken,
            feeRatio,
            tokenPrice,
            fxAmount,
            collateralTypes
        );
    }

    /**
     * @dev Reverts the transaction if the target vault cannot be liquidated.
     * @param account The vault account.
     * @param fxToken The vault fxToken.
     * @param debt The vault debt.
     * @param collateral The vault collateral in the same currency as the debt.
     */
    function validateLiquidation(
        address account,
        address fxToken,
        uint256 debt,
        uint256 collateral
    ) private view {
        uint256 cr = collateral.mul(1 ether).div(debt);
        require(
            cr <= getLiquidationRatio(account, fxToken) && cr >= 1 ether,
            "CR"
        );
    }

    /**
     * @dev Calculates the required amount of fxTokens to successfully
            liquidate a vault to an acceptable CR. 
            Also caps the feeRatio to the maximum value possible if needed.
     * @param account The vault account.
     * @param fxToken The vault fxToken.
     * @param debt The vault debt.
     * @param collateral The vault collateral in the same currency as the debt.
     * @param inputFeeRatio The ratio of purchased asset value to purchasing value.
     * @param tokenPrice The fxToken unit price in ETH. 
     */
    function getLiquidationFxAmount(
        address account,
        address fxToken,
        uint256 debt,
        uint256 collateral,
        uint256 inputFeeRatio,
        uint256 tokenPrice
    ) private view returns (uint256 fxAmount, uint256 feeRatio) {
        // Assign output feeRatio in case this function changes it.
        feeRatio = inputFeeRatio;
        // Scale the minimum CR by the crScalar value.
        uint256 finalCr =
            vaultLibrary
                .getMinimumRatio(account, fxToken)
                .mul(crScalar.add(100))
                .div(100);
        // The max fee is the overcollateralisation % of the vault.
        uint256 maxFee = (collateral.mul(1 ether).div(debt)).sub(1 ether);
        if (feeRatio > maxFee) feeRatio = maxFee;
        // Get fxAmount to be used in liquidation.
        // Inputs are in Ether, therefore result is converted
        // back to the fxToken currency.
        fxAmount = tokensRequiredForCrIncrease(
            finalCr,
            debt,
            collateral,
            uint256(1 ether).add(feeRatio)
        )
            .mul(1 ether)
            .div(tokenPrice);
        require(
            IERC20(fxToken).balanceOf(msg.sender) >= fxAmount,
            "Liquidator: insufficient balance"
        );
    }

    /**
     * @dev Executes a liquidation and asserts that the value purchased
            is correct.
     * @param account The vault account.
     * @param fxToken The vault fxToken.
     * @param fxAmount The amount of fxTokens to liquidate with.
     * @param tokenPrice The fxToken unit price in ETH.
     */
    function executeLiquidation(
        address account,
        address fxToken,
        uint256 fxAmount,
        uint256 tokenPrice
    )
        private
        returns (
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts
        )
    {
        uint256 etherAmountPurchased;
        (
            collateralAmounts,
            collateralTypes,
            etherAmountPurchased
        ) = _buyCollateral(fxAmount, fxToken, account);
        // Assert that the amount purchased is correct.
        // i.e. allowed fxAmount must match with the input fxAmount.
        assert(etherAmountPurchased == fxAmount.mul(tokenPrice).div(1 ether));
    }

    /**
     * @dev Withdraws liquidation fees to the sender.
     * @param fxToken The vault fxToken.
     * @param feeRatio The ratio of the purchased asset value to the
                        purchasing asset value.
     * @param tokenPrice The unit price of the fxToken in ETH.
     * @param fxAmount The amount of fxTokens to withdraw as ETH for the fees.
     * @param collateralTypes The array of supported protocol collateral.
     */
    function withdrawFees(
        address account,
        address fxToken,
        uint256 feeRatio,
        uint256 tokenPrice,
        uint256 fxAmount,
        address[] memory collateralTypes
    ) private returns (uint256[] memory collateralAmounts) {
        address[] memory withdrawnCollateralTypes;
        // Convert fxAmount to the ETH profit.
        fxAmount = fxAmount.mul(feeRatio).div(1 ether).mul(tokenPrice).div(
            1 ether
        );
        // Both _buyCollateral and Treasury.forceWithdrawAnyCollateral
        // use the full list of ordered collateral types,
        // therefore the result from the function below can simply be
        // assigned to the return collateralAmounts
        // instead of looping collateralTypes and withdrawnCollateralTypes
        // to ensure the types match for the collateralAmounts array.
        (withdrawnCollateralTypes, collateralAmounts) = treasury
            .forceWithdrawAnyCollateral(
            account,
            msg.sender,
            fxAmount,
            fxToken,
            false
        );
    }

    /**
     * @dev returns the allowed amount of tokens that can be used to buy collateral from a vault
     * @param token The vault fxToken
     * @param from The vault account
     */
    function getAllowedBuyCollateralFromTokenAmount(address token, address from)
        public
        view
        override
        returns (uint256 allowedAmount, bool isLiquidation)
    {
        uint256 minimumCr = vaultLibrary.getMinimumRatio(from, token);
        uint256 debt = vaultLibrary.getDebtAsEth(from, token);
        uint256 collateral =
            vaultLibrary.getTotalCollateralBalanceAsEth(from, token);
        // Vault CR must be below the max. for buying collateral.
        uint256 cr = collateral.mul(1 ether).div(debt);
        require(cr < minimumCr, "CR");
        // Liquidation ROI ratio (from fxToken value to purchased collateral value)
        uint256 returnRatio = 1 ether;
        isLiquidation = cr <= getLiquidationRatio(from, token);
        // Apply liquidation modifiers to allowable amount if liquidating.
        if (isLiquidation) {
            // Turn minimum CR into target CR for liquidations
            // by accounting for safety CR scalar.
            minimumCr = minimumCr.mul(crScalar.add(100)).div(100);
            // Add vault liquidation fee to ROI ratio.
            // The max fee allowed is the overcollateralisation % of the vault.
            uint256 fee = vaultLibrary.getLiquidationFee(from, token);
            returnRatio = fee <= cr.sub(1 ether)
                ? returnRatio.add(fee) // Charge fee under the max.
                : cr; // Charge max. fee (equal to CR).
        }
        allowedAmount = tokensRequiredForCrIncrease(
            minimumCr,
            debt,
            collateral,
            returnRatio
        );
        // Allowed amount calculated in Ether, convert to forex value.
        uint256 tokenPrice = handle.getTokenPrice(token);
        allowedAmount = allowedAmount.mul(1 ether).div(tokenPrice);
    }

    /**
     * @dev Returns the amount of tokens required to use towards CR increase.
            Formula: [tokens] = ([debt]*[ratio]-[collateral])/([ratio]-1)
     * @param crTarget The per-thousand ratio for vault CR after purchase.
     * @param debt The vault debt in ETH
     * @param collateral The vault collateral in ETH
     */
    function tokensRequiredForCrIncrease(
        uint256 crTarget,
        uint256 debt,
        uint256 collateral,
        uint256 returnRatio
    ) public pure override returns (uint256 amount) {
        require(crTarget > 1 ether, "Invalid target CR");
        require(debt < collateral, "Invalid vault CR");
        require(returnRatio < crTarget, "RR >= CR");
        uint256 nominator = debt.mul(crTarget).sub(collateral.mul(1 ether));
        uint256 denominator = crTarget.sub(returnRatio);
        return nominator.div(denominator);
    }

    /**
     * @dev Ensures that the staked amount in the target fxKeeperPool is
               greater than the threshold if the sender is not the keeper pool.
     * @param fxToken The pool fxToken
     * @param tokenPrice The fxToken unit price in ETH.
     */
    function ensurePoolThreshold(address fxToken, uint256 tokenPrice) private {
        address keeperPool = handle.fxKeeperPool();
        if (msg.sender == keeperPool) return;
        // Staked value in ETH.
        uint256 staked =
            IfxKeeperPool(keeperPool)
                .getPoolTotalDeposit(fxToken)
                .mul(tokenPrice)
                .div(1 ether);
        require(staked <= keeperPoolThreshold, "NW");
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

