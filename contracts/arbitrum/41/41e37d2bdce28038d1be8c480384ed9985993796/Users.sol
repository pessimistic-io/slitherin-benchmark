// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {UsersStorage, UsersStorageLib, UserTier, Tier} from "./storage_Users.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {AccessControlled} from "./AccessControlled.sol";
import {BusinessStorageLib} from "./Business.sol";
import "./console.sol";

contract UsersFacet is AccessControlled {
    using SafeERC20 for IERC20;
    // ===============
    //     ERRORS
    // ===============
    error InsufficientLifetimeAmount(uint256 provided, uint256 expected);
    error InsufficientPayment(uint256 provided, uint256 min);
    error UnpricedTier();
    error CannotDowngrade();
    error TierAlreadyAdded();

    // ===============
    //     METHODS
    // ===============
    /**
     * Upgrade own tier
     * @param tierId - The tier ID to purchase
     * @param amount - The amount to purchase with (STABLECOIN) (will decide on length of tier validty)
     * @param isLifetime - Whether this is a lifetime purchase (if so, amount must be lifetime cost)
     */
    function upgradeTier(
        uint256 tierId,
        uint256 amount,
        bool isLifetime
    ) external {
        UsersStorage storage usersStorage = UsersStorageLib.retreive();

        IERC20(usersStorage.paymentToken).safeTransferFrom(
            msg.sender,
            BusinessStorageLib.retreive().treasury,
            amount
        );

        _upgradeTier(tierId, amount, isLifetime, msg.sender);
    }

    function _upgradeTier(
        uint256 tierId,
        uint256 amount,
        bool isLifetime,
        address receiver
    ) internal {
        UsersStorage storage usersStorage = UsersStorageLib.retreive();
        Tier memory tier = usersStorage.tiers[tierId];

        if (tier.monthlyCost == 0) revert UnpricedTier();

        if (isLifetime && tier.lifetimeCost > amount)
            revert InsufficientLifetimeAmount(amount, tier.lifetimeCost);

        UserTier memory currTier = usersStorage.users[receiver];
        UserTier storage storageTier = usersStorage.users[receiver];
        Tier memory currentTierDetails = usersStorage.tiers[currTier.tierId];

        if (currentTierDetails.powerLevel > tier.powerLevel)
            revert CannotDowngrade();

        // Gas savings
        if (currTier.tierId != tierId) storageTier.tierId = tierId;

        if (isLifetime) {
            storageTier.endsOn = type(uint256).max;
            return;
        }

        uint256 monthlyCost = tier.monthlyCost;

        if (amount < monthlyCost)
            revert InsufficientPayment(amount, monthlyCost);

        uint256 timeWorth = (amount / monthlyCost) * 30 days;

        if (currTier.endsOn > block.timestamp) storageTier.endsOn += timeWorth;
        else storageTier.endsOn = block.timestamp + timeWorth;
    }

    // ===============
    //     SETTERS
    // ===============
    function setPaymentToken(address paymentToken) external onlyOwner {
        UsersStorageLib.retreive().paymentToken = paymentToken;
    }

    function giftTier(
        address receiver,
        uint256 tierId,
        uint256 amount,
        bool isLifetime
    ) external onlyOwner {
        _upgradeTier(tierId, amount, isLifetime, receiver);
    }

    function addTier(
        uint256 tierPower,
        uint256 monthlyCost,
        uint256 lifetimeCost
    ) external onlyOwner {
        UsersStorage storage usersStorage = UsersStorageLib.retreive();
        usersStorage.tiersAmount++;
        usersStorage.tiers[usersStorage.tiersAmount] = Tier({
            isActive: true,
            powerLevel: tierPower,
            monthlyCost: monthlyCost,
            lifetimeCost: lifetimeCost
        });
    }

    function updateTierCost(
        uint256 tierId,
        uint256 newMonthlyCost,
        uint256 newlifetimeCost
    ) external onlyOwner {
        Tier storage tier = UsersStorageLib.retreive().tiers[tierId];
        tier.monthlyCost = newMonthlyCost;
        tier.lifetimeCost = newlifetimeCost;
    }

    function removeTier(uint256 tierId) external onlyOwner {
        UsersStorage storage usersStorage = UsersStorageLib.retreive();
        usersStorage.tiers[tierId].isActive = false;
    }

    // ===============
    //     GETTERS
    // ===============
    function getUserTier(
        address user
    ) external view returns (UserTier memory userTier) {
        userTier = UsersStorageLib.retreive().users[user];
    }

    function getTier(uint256 tierId) external view returns (Tier memory tier) {
        tier = UsersStorageLib.retreive().tiers[tierId];
    }

    function getPaymentToken() external view returns (address paymentToken) {
        paymentToken = UsersStorageLib.retreive().paymentToken;
    }

    function getAllTiers() external view returns (Tier[] memory tiers) {
        UsersStorage storage usersStorage = UsersStorageLib.retreive();

        uint256 maxAmt = usersStorage.tiersAmount;
        for (uint256 i; i < maxAmt; i++) {
            Tier memory currTier = usersStorage.tiers[i];

            if (currTier.isActive) {
                Tier[] memory newTiers = new Tier[](tiers.length + 1);
                for (uint256 j; j < tiers.length; j++) newTiers[j] = tiers[j];
                newTiers[newTiers.length - 1] = currTier;
                tiers = newTiers;
            }
        }
    }

    function isInTier(
        address user,
        uint256 tierId
    ) external view returns (bool isUserInTier) {
        isUserInTier = UsersStorageLib.isInTier(user, tierId);
    }
}

