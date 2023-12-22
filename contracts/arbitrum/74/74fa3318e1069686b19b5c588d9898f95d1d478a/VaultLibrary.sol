// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeMath.sol";
import "./IVaultLibrary.sol";
import "./IComptroller.sol";
import "./ITreasury.sol";
import "./IHandle.sol";
import "./IHandleComponent.sol";
import "./IValidator.sol";
import "./IERC20.sol";
import "./IInterest.sol";

/**
 * @dev Provides read-only functions to calculate vault data such as the
        collateral ratio, the equivalent ETH value of collateral/debt at
        the current exchange rates, weighted fees, etc.
 */
contract VaultLibrary is
    IVaultLibrary,
    IValidator,
    Initializable,
    IHandleComponent,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    using SafeMath for uint256;

    /** @dev The Handle contract interface */
    IHandle private handle;
    /** @dev The Treasury contract interface */
    ITreasury private treasury;
    /** @dev The Comptroller contract interface */
    IComptroller private comptroller;
    /** @dev The Interest contract interface */
    IInterest private interest;

    /** @dev Proxy initialisation function */
    function initialize() public initializer {
        __Ownable_init();
    }

    /**
     * @dev Setter for Handle contract reference
     * @param _handle The Handle contract address
     */
    function setHandleContract(address _handle) public override onlyOwner {
        handle = IHandle(_handle);
        comptroller = IComptroller(handle.comptroller());
        treasury = ITreasury(handle.treasury());
        interest = IInterest(handle.interest());
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /**
     * @dev Returns whether the vault's current CR meets the minimum ratio.
     * @param account The vault account
     * @param fxToken The vault fxToken
     */
    function doesMeetRatio(address account, address fxToken)
        external
        view
        override
        returns (bool)
    {
        uint256 targetRatio = getMinimumRatio(account, fxToken);
        uint256 currentRatio = getCurrentRatio(account, fxToken);
        return currentRatio != 0 && currentRatio >= targetRatio;
    }

    /**
     * @dev Calculates the minimum collateral required for a given
            amount and ratio.
     * @param tokenAmount The amount of the token desired
     * @param ratio The minting collateral ratio with 18 decimals of precision
     * @param unitPrice The price of the token in ETH
     * @return minimum The minimum collateral required for the ratio
     */
    function getMinimumCollateral(
        uint256 tokenAmount,
        uint256 ratio,
        uint256 unitPrice
    ) public pure override returns (uint256 minimum) {
        require(ratio >= 1 ether, "CR");
        minimum = unitPrice.mul(tokenAmount).mul(ratio).div(1 ether).div(
            1 ether
        );
    }

    /**
     * @dev Calculates the vault's current ratio
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return ratio The current vault ratio percent; zero if no debt
     */
    function getCurrentRatio(address account, address fxToken)
        public
        view
        override
        returns (uint256 ratio)
    {
        uint256 debtAsEth = getDebtAsEth(account, fxToken);
        if (debtAsEth == 0) return 0;
        uint256 collateral = getTotalCollateralBalanceAsEth(account, fxToken);
        ratio = collateral.mul(1 ether).div(debtAsEth);
    }

    /**
     * @dev Returns the vault debt as ETH using the current exchange rate.
     * @param account The vault account
     * @param fxToken The vault fxToken
     */
    function getDebtAsEth(address account, address fxToken)
        public
        view
        override
        returns (uint256 debt)
    {
        return
            handle
                .getDebt(account, fxToken)
                .mul(handle.getTokenPrice(fxToken))
                .div(1 ether);
    }

    /**
     * @dev Returns the total vault amount of collateral converted to ETH
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return balance The total vault collateral balance as ETH
     */
    function getTotalCollateralBalanceAsEth(address account, address fxToken)
        public
        view
        override
        returns (uint256 balance)
    {
        address[] memory collateralTokens = handle.getAllCollateralTypes();
        balance = 0;
        uint256 j = collateralTokens.length;
        for (uint256 i = 0; i < j; i++) {
            uint256 collateralAsEth =
                handle
                    .getCollateralBalance(account, collateralTokens[i], fxToken)
                    .mul(handle.getTokenPrice(collateralTokens[i]))
                    .div(getTokenUnit(collateralTokens[i]));
            balance = balance.add(collateralAsEth);
        }
    }

    /**
     * @dev Calculates the amount of free collateral in ETH that a vault has.
            It will convert collateral other than ETH into ETH first.
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return free The amount of free collateral
     */
    function getFreeCollateralAsEth(address account, address fxToken)
        public
        view
        override
        returns (uint256)
    {
        return
            getFreeCollateralAsEthFromMinimumRatio(
                account,
                fxToken,
                getMinimumRatio(account, fxToken)
            );
    }

    /**
     * @dev Same as getFreeCollateralAsEth, but accepts any minimum ratio.
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return free The amount of free collateral
     */
    function getFreeCollateralAsEthFromMinimumRatio(
        address account,
        address fxToken,
        uint256 minimumRatio
    ) public view override returns (uint256) {
        uint256 currentCollateral =
            getTotalCollateralBalanceAsEth(account, fxToken);
        if (currentCollateral == 0) return 0;
        uint256 collateralRequired =
            getDebtAsEth(account, fxToken).mul(minimumRatio).div(1 ether);
        if (currentCollateral <= collateralRequired) return 0;
        return currentCollateral.sub(collateralRequired);
    }

    /**
     * @dev Returns an array of collateral tokens and amounts that meet the input amount in ETH
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return collateralTypes An array of collateral addresses
     * @return collateralAmounts An array of collateral amounts
     * @return metAmount Whether the requested amount exists in the vault
     */
    function getCollateralForAmount(
        address account,
        address fxToken,
        uint256 amountEth
    )
        external
        view
        override
        returns (
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts,
            bool metAmount
        )
    {
        collateralTypes = getCollateralTypesSortedByLiquidationRank();
        uint256 j = collateralTypes.length;
        collateralAmounts = new uint256[](j);
        uint256 currentEthAmount = 0;
        // Loop through all sorted vault collateral types,
        // convert to ETH until it matches amount value.
        for (uint256 i = 0; i < j; i++) {
            uint256 collateral =
                handle.getCollateralBalance(
                    account,
                    collateralTypes[i],
                    fxToken
                );
            if (collateral == 0) continue;
            uint256 collateralUnitPrice =
                handle.getTokenPrice(collateralTypes[i]);
            uint256 collateralAsEth =
                collateralUnitPrice.mul(collateral).div(
                    getTokenUnit(collateralTypes[i])
                );
            if (currentEthAmount.add(collateralAsEth) < amountEth) {
                // Add entire collateral amount.
                collateralAmounts[i] = collateral;
                currentEthAmount = currentEthAmount.add(collateralAsEth);
                continue;
            }
            // Add missing amount to fill amount required.
            uint256 delta = amountEth.sub(currentEthAmount);
            // Convert the amount from 18 decimals to the collateral's decimals.
            collateralAmounts[i] = getDecimalsAmount(
                delta.mul(1 ether).div(collateralUnitPrice),
                18,
                IERC20(collateralTypes[i]).decimals()
            );
            currentEthAmount = currentEthAmount.add(delta);
            break;
        }
        metAmount = currentEthAmount == amountEth;
    }

    /**
     * @dev Converts a value from one decimal count to another. Note that if
            reducing the amount of decimals some data and precision may be lost.
     * @param amount The current value to be transformed
     * @param fromDecimals The current amount of decimals in the value
     * @param toDecimals The final desired amount of decimals for the value 
     */
    function getDecimalsAmount(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) public pure override returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        int256 delta = int256(int8(fromDecimals) - int8(toDecimals));
        uint256 udelta;
        if (delta > 0) {
            // fromDecimals > toDecimals. Scale amount down.
            udelta = uint256(delta);
            amount = amount.div(10**udelta);
        } else {
            // fromDecimals < toDecimals. Scale amount up.
            udelta = uint256(-delta);
            amount = amount.mul(10**udelta);
        }
        return amount;
    }

    /**
     * @dev Calculates the vault interest using the R value for the current block
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return The amount of interest outstanding in ETH.
     */
    function calculateInterest(address account, address fxToken)
        public
        view
        override
        returns (uint256)
    {
        uint256 dR = getInterestDeltaR(account, fxToken);
        return handle.getPrincipalDebt(account, fxToken).mul(dR).div(1 ether);
    }

    /**
     * @dev Calculates vault's weighted interest rate
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return rate The interest rate with 1 decimal (perMille)
     */
    function getInterestRate(address account, address fxToken)
        public
        view
        override
        returns (uint256 rate)
    {
        rate = 0;
        address[] memory collateralTokens = handle.getAllCollateralTypes();
        uint256 j = collateralTokens.length;
        uint256[] memory shares = getCollateralShares(account, fxToken);
        for (uint256 i = 0; i < j; i++) {
            rate = rate.add(
                handle
                    .getCollateralDetails(collateralTokens[i])
                    .interestRate
                    .mul(shares[i])
                    .div(1 ether)
            );
        }
    }

    /**
     * @dev Calculates vault's weighted delta cumulative interest rate
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return dR The delta cumulative interest rate with 18 decimals
     */
    function getInterestDeltaR(address account, address fxToken)
        public
        view
        override
        returns (uint256 dR)
    {
        (uint256[] memory R, address[] memory collateralTokens) =
            interest.getCurrentR();
        dR = 0;
        // Compute weighted interest rate based on collateral tokens.
        uint256 j = collateralTokens.length;
        uint256 R0;
        uint256[] memory shares = getCollateralShares(account, fxToken);
        for (uint256 i = 0; i < j; i++) {
            R0 = handle.getCollateralR0(account, fxToken, collateralTokens[i]);
            dR = dR.add(R[i].sub(R0).mul(shares[i]).div(1 ether));
        }
    }

    /**
     * @dev Calculates the weighted minting vault ratio. Ratio with 18 decimals.
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return ratio The wighted minting ratio; zero if vault has no collateral
     */
    function getMinimumRatio(address account, address fxToken)
        public
        view
        override
        returns (uint256 ratio)
    {
        address[] memory collateralTypes = handle.getAllCollateralTypes();
        uint256[] memory shares = getCollateralShares(account, fxToken);
        uint256 j = collateralTypes.length;
        for (uint256 i = 0; i < j; i++) {
            ratio = ratio.add(
                handle
                    .getCollateralDetails(collateralTypes[i])
                    .mintCR
                    .mul(100)
                    .mul(shares[i])
            );
        }
        // Normalise the value. Return a value with 18 decimals.
        ratio = ratio.div(10_000);
    }

    /**
     * @dev Returns the vault's weighted liquidation fee based on collateral.
            Returns a ratio with 18 decimals.
     * @param account The vault account
     * @param fxToken The vault fxToken
     */
    function getLiquidationFee(address account, address fxToken)
        public
        view
        override
        returns (uint256 fee)
    {
        fee = 0;
        address[] memory collateralTypes = handle.getAllCollateralTypes();
        uint256[] memory shares = getCollateralShares(account, fxToken);
        uint256 j = collateralTypes.length;
        for (uint256 i = 0; i < j; i++) {
            fee = fee.add(
                handle
                    .getCollateralDetails(collateralTypes[i])
                    .liquidationFee
                    .mul(shares[i])
                // Since the liquidation fee has 2 decimals, the value
                // is divided by 10000 here after being multiplied by
                // the collateral share which has 18 decimals.
                    .div(10000)
            );
        }
    }

    /**
     * @dev Returns a share value per collateral type (1 ether = 100%)
     * @param account The vault account
     * @param fxToken The vault fxToken
     */
    function getCollateralShares(address account, address fxToken)
        public
        view
        override
        returns (uint256[] memory shares)
    {
        address[] memory collateralTypes = handle.getAllCollateralTypes();
        uint256 j = collateralTypes.length;
        shares = new uint256[](j);
        uint256 totalBalanceEth =
            getTotalCollateralBalanceAsEth(account, fxToken);
        if (totalBalanceEth == 0) return shares;
        uint256 balance = 0;
        uint256 balanceEth = 0;
        for (uint256 i = 0; i < j; i++) {
            balance = handle.getCollateralBalance(
                account,
                collateralTypes[i],
                fxToken
            );
            balanceEth = handle
                .getTokenPrice(collateralTypes[i])
                .mul(balance)
                .div(getTokenUnit(collateralTypes[i]));
            shares[i] = balanceEth.mul(1 ether).div(totalBalanceEth);
        }
    }

    /**
     * @dev Returns a sorted array of Comptroller collateral type addresses by
            their liquidation rank, which is derived by the collateral's
            minting ratio.
     */
    function getCollateralTypesSortedByLiquidationRank()
        public
        view
        override
        returns (address[] memory sortedCollateralTypes)
    {
        address[] memory unsortedCollateralTypes =
            handle.getAllCollateralTypes();
        // Get collateral liquidation ranks.
        uint256 m = unsortedCollateralTypes.length;
        uint256[] memory unsortedRanks = new uint256[](m);
        for (uint256 i = 0; i < m; i++) {
            // The rank is simply the minting ratio.
            unsortedRanks[i] = handle
                .getCollateralDetails(unsortedCollateralTypes[i])
                .mintCR;
        }
        // Sort ranks; copy array.
        uint256[] memory sortedRanks = new uint256[](m);
        for (uint256 i = 0; i < m; i++) {
            sortedRanks[i] = unsortedRanks[i];
        }
        // Quicksort (ascending order).
        quickSort(sortedRanks, 0, int256(sortedRanks.length - 1));
        // Map unsorted index to sorted index.
        uint256[] memory toUnsortedIndex = new uint256[](m);
        // List of unsorted indices already used, if two or more collaterals
        // have the same mint CR -- if this is not used, an overlap will occur.
        // This stores the index + 1 since the default is zero.
        uint256[] memory jUsed = new uint256[](m);
        // i is the sorted index.
        for (uint256 i = 0; i < m; i++) {
            // j is the unsorted index.
            for (uint256 j = 0; j < m; j++) {
                if (unsortedRanks[j] != sortedRanks[i]) continue;
                bool isDuplicateJ;
                // k is used for finding duplicate indices.
                for (uint256 k = 0; k < m; k++) {
                    if (j + 1 == jUsed[k]) isDuplicateJ = true;
                }
                if (isDuplicateJ) continue;
                toUnsortedIndex[i] = j;
                jUsed[i] = j + 1;
                break;
            }
        }
        sortedCollateralTypes = new address[](m);
        for (uint256 i = 0; i < m; i++) {
            // i is sorted, j is unsorted.
            uint256 n = toUnsortedIndex[i];
            // The ascending order array must be reversed now so that it's descending.
            // Descending order index.
            uint256 iDescending = m - i - 1;
            sortedCollateralTypes[iDescending] = unsortedCollateralTypes[n];
        }
    }

    /**
     * @dev Returns the new minimum vault ratio due to a collateral deposit
            or withdraw. Used for checking the CR is valid before performing
            an operation.
     * @param account The account that owns the vault
     * @param fxToken The vault fxToken
     * @param collateralToken The collateral address
     * @param collateralAmount The collateral amount
     * @param collateralQuote The collateral unit price in ETH
     * @param isDeposit Whether depositing or withdrawing the input collateral
     */
    function getNewMinimumRatio(
        address account,
        address fxToken,
        address collateralToken,
        uint256 collateralAmount,
        uint256 collateralQuote,
        bool isDeposit
    )
        public
        view
        override
        returns (uint256 ratio, uint256 newCollateralAsEther)
    {
        uint256 currentMinRatio = getMinimumRatio(account, fxToken);
        uint256 vaultCollateral =
            getTotalCollateralBalanceAsEth(account, fxToken);
        // Calculate new vault collateral from deposit amount.
        newCollateralAsEther = isDeposit
            ? vaultCollateral.add(
                collateralQuote.mul(collateralAmount).div(
                    getTokenUnit(collateralToken)
                )
            )
            : vaultCollateral.sub(
                collateralQuote.mul(collateralAmount).div(
                    getTokenUnit(collateralToken)
                )
            );
        uint256 depositCollateralMintCR =
            handle.getCollateralDetails(collateralToken).mintCR;
        if (currentMinRatio == 0) {
            ratio = depositCollateralMintCR.mul(1 ether).div(100);
            return (ratio, newCollateralAsEther);
        }
        /* Ratio for the current share of minimum collateral ratio due
        to the deposit amount (i.e. if vault holds $50 and the new
        deposit is $50, this value is 50% expressed as 0.5 ether).
           For a withdrawal, the value is going to be >100% since
        collateral is removed. */
        uint256 oldCollateralMintRatio =
            vaultCollateral.mul(1 ether).div(newCollateralAsEther);
        // Start calculating new minimum ratio using the CR ratio above.
        ratio = currentMinRatio.mul(oldCollateralMintRatio).div(1 ether);
        // Finish calculating the ratio depending on whether it's a deposit
        // or withdrawal to prevent an underflow on withdrawal.
        assert(
            (oldCollateralMintRatio <= 1 ether && isDeposit) ||
                (oldCollateralMintRatio >= 1 ether && !isDeposit)
        );
        ratio = isDeposit
            ? ratio.add(
                depositCollateralMintCR
                    .mul(uint256(1 ether).sub(oldCollateralMintRatio))
                    .div(1 ether)
            )
            : ratio.sub(
                depositCollateralMintCR
                    .mul(oldCollateralMintRatio.sub(1 ether))
                    .div(1 ether)
            );
    }

    /**
     * @dev Returns whether the resulting state is valid for a vault about to
            mint fxTokens.
     * @param account The vault account.
     * @param fxToken The vault fxToken.
     * @param collateralToken The collateral token to deposit when minting.
     * @param collateralAmount The amount of collateral to deposit.
     * @param tokenAmount The amount of tokens to mint.
     * @param fxQuote The fxToken unit price in ETH.
     * @param collateralQuote The collateral token unit price in ETH.
     */
    function canMint(
        address account,
        address fxToken,
        address collateralToken,
        uint256 collateralAmount,
        uint256 tokenAmount,
        uint256 fxQuote,
        uint256 collateralQuote
    ) external view override returns (bool) {
        (uint256 minimumRatio, uint256 collateral) =
            getNewMinimumRatio(
                account,
                fxToken,
                collateralToken,
                collateralAmount,
                collateralQuote,
                true
            );

        // Check the vault ratio is correct
        return (collateral >=
            // Calculate token value as ETH.
            tokenAmount
                .mul(fxQuote)
                .div(1 ether)
            // Add existing debt as ETH.
                .add(getDebtAsEth(account, fxToken))
            // Multiply by the minimum ratio -- collateral must be greater than
            // or equal to this value so that the collateral ratio is valid.
                .mul(minimumRatio)
                .div(1 ether));
    }

    /**
     * @dev Quick sort algorithm implementation (ascending order).
     * @param array The array to sort
     * @param left The leftmost index of the array to sort from
     * @param right The rightmost index of the array to sort to
     */
    function quickSort(
        uint256[] memory array,
        int256 left,
        int256 right
    ) public pure override {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = array[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (array[uint256(i)] < pivot) i++;
            while (pivot < array[uint256(j)]) j--;
            if (i <= j) {
                (array[uint256(i)], array[uint256(j)]) = (
                    array[uint256(j)],
                    array[uint256(i)]
                );
                i++;
                j--;
            }
        }
        if (left < j) quickSort(array, left, j);
        if (i < right) quickSort(array, i, right);
    }

    /**
     * @dev Returns an unit value for any ERC20 that implements decimals.
     * @param token The token address
     */
    function getTokenUnit(address token)
        public
        view
        override
        returns (uint256)
    {
        uint256 decimals = IERC20(token).decimals();
        return 10**decimals;
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

