// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./IComptroller.sol";
import "./IVaultLibrary.sol";
import "./ITreasury.sol";
import "./IfxToken.sol";
import "./IValidator.sol";
import "./IWETH.sol";
import "./IHandle.sol";
import "./IInterest.sol";
import "./IReferral.sol";
import "./IRewardPool.sol";
import "./HandlePausable.sol";

/**
 * @dev Provides mint and burn functions for vaults.
 */
contract Comptroller is
    IComptroller,
    IValidator,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    HandlePausable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /** @dev The Handle contract interface */
    IHandle private handle;
    /** @dev The Treasury contract interface */
    ITreasury private treasury;
    /** @dev The VaultLibrary contract interface */
    IVaultLibrary private vaultLibrary;
    /** @dev The canonical WETH address */
    address private WETH;

    /** @dev The minting threshold amount in ETH */
    uint256 public override minimumMintingAmount;

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
        WETH = handle.WETH();
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /** @dev Only allows ETH transfers from WETH withdrawals */
    receive() external payable {
        assert(msg.sender == WETH);
    }

    modifier validFxToken(address token) {
        require(handle.isFxTokenValid(token), "IF");
        _;
    }

    /**
     * @dev Setter for the minimum minting amount
     * @param amount The minimum minting amount in ETH
     */
    function setMinimumMintingAmount(uint256 amount)
        external
        override
        onlyOwner
    {
        minimumMintingAmount = amount;
    }

    /**
     * @dev Wraps received ETH and mints with WETH as collateral
     * @param tokenAmount The amount of fxTokens the user wants
     * @param token The token to mint
     * @param deadline The time on which the transaction is invalid.
     * @param referral The referral account
     */
    function mintWithEth(
        uint256 tokenAmount,
        address token,
        uint256 deadline,
        address referral
    )
        external
        payable
        override
        dueBy(deadline)
        validFxToken(token)
        nonReentrant
    {
        require(handle.isCollateralValid(WETH), "WE");
        require(tokenAmount > 0 && msg.value > 0, "IA");
        IWETH(WETH).deposit{value: msg.value}();
        _mintAndDeposit(tokenAmount, token, WETH, msg.value, referral);
    }

    /**
     * @dev Mints with a valid ERC20 as collateral.
            Must have pre-approved ERC20 allowance.
     * @param tokenAmount The amount of fxTokens the user wants
     * @param token The token to mint
     * @param deadline The time on which the transaction is invalid.
     * @param referral The referral account
     */
    function mint(
        uint256 tokenAmount,
        address token,
        address collateralToken,
        uint256 collateralAmount,
        uint256 deadline,
        address referral
    ) external override dueBy(deadline) validFxToken(token) nonReentrant {
        require(handle.isCollateralValid(collateralToken), "IC");
        require(tokenAmount > 0 && collateralAmount > 0, "IA");
        IERC20(collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
        _mintAndDeposit(
            tokenAmount,
            token,
            collateralToken,
            collateralAmount,
            referral
        );
    }

    /**
     * @dev Mints the requested amount accounting for mint fees and deposits
            collateral into the vault via the Treasury.
     * @param tokenAmount The token amount to mint, excluding the mint fee.
     * @param token The fxToken to mint
     * @param collateralToken The collateral token to deposit.
     * @param collateralAmount The amount of collateral to deposit.
     * @param referral The referral account.
     */
    function _mintAndDeposit(
        uint256 tokenAmount,
        address token,
        address collateralToken,
        uint256 collateralAmount,
        address referral
    ) private {
        IERC20(collateralToken).safeApprove(address(treasury), 0);
        IERC20(collateralToken).safeApprove(
            address(treasury),
            collateralAmount
        );

        // Calculate fee with current amount and increase token amount to include fee.
        uint256 feeTokens = tokenAmount.mul(handle.mintFeePerMille()).div(1000);
        uint256 feeCollateral =
            collateralAmount.mul(handle.depositFeePerMille()).div(1000);
        uint256 tokenQuote = handle.getTokenPrice(token);

        _ensureMinimumMintingAmount(
            msg.sender,
            token,
            tokenQuote,
            tokenAmount,
            true
        );

        require(
            vaultLibrary.canMint(
                msg.sender,
                token,
                collateralToken,
                collateralAmount.sub(feeCollateral),
                tokenAmount.add(feeTokens),
                tokenQuote,
                handle.getTokenPrice(collateralToken)
            ),
            "CR"
        );

        // Deposit in the treasury
        treasury.depositCollateral(
            msg.sender,
            collateralAmount,
            collateralToken,
            token,
            referral
        );

        _mint(tokenAmount, token, tokenQuote, feeTokens);
    }

    /**
     * @dev Mints fxTokens for the user and protocol as fees.
     * @param tokenAmount The token amount to mint for the user, excluding fee.
     * @param token The fxToken address to mint.
     * @param tokenQuote The unit price in ETH for the fxToken.
     * @param feeTokenAmount The amount of fxTokens to be minted as a fee.
     */
    function _mint(
        uint256 tokenAmount,
        address token,
        uint256 tokenQuote,
        uint256 feeTokenAmount
    ) private notPaused {
        // Mint tokens and fee
        uint256 balanceBefore = IfxToken(token).balanceOf(msg.sender);
        IfxToken(token).mint(msg.sender, tokenAmount);
        IfxToken(token).mint(handle.FeeRecipient(), feeTokenAmount);
        assert(
            IfxToken(token).balanceOf(msg.sender) ==
                balanceBefore.add(tokenAmount)
        );

        // Update debt position
        uint256 debtPosition = handle.getDebt(msg.sender, token);
        uint256 totalMintedAmount = tokenAmount.add(feeTokenAmount);
        handle.updateDebtPosition(msg.sender, totalMintedAmount, token, true);
        assert(
            debtPosition.add(totalMintedAmount) ==
                handle.getDebt(msg.sender, token)
        );

        // Stake into the reward pool.
        IRewardPool rewards = IRewardPool(handle.rewards());
        (bool found, uint256 rewardPoolId) =
            rewards.getPoolIdByAlias(
                rewards.getFxTokenPoolAlias(
                    token,
                    uint256(RewardPoolCategory.Mint)
                )
            );
        if (found) rewards.stake(msg.sender, totalMintedAmount, rewardPoolId);

        emit MintToken(tokenQuote, totalMintedAmount, token);
    }

    /**
     * @dev Allows an user to mint fxTokens with existing collateral.
     * @param tokenAmount The amount of fxTokens the user wants.
     * @param token The fxToken to mint.
     * @param deadline The time on which the transaction is invalid.
     * @param referral The referral account.
     */
    function mintWithoutCollateral(
        uint256 tokenAmount,
        address token,
        uint256 deadline,
        address referral
    ) public override dueBy(deadline) validFxToken(token) nonReentrant {
        require(tokenAmount > 0, "IA");

        // Check the vault ratio is correct (fxToken <-> collateral)
        uint256 quote = handle.getTokenPrice(token);

        _ensureMinimumMintingAmount(
            msg.sender,
            token,
            quote,
            tokenAmount,
            true
        );

        _trySetReferral(msg.sender, referral);

        // Update interest rates according to cache time.
        IInterest(handle.interest()).tryUpdateRates();

        // Calculate fee with current amount and increase token amount to include fee.
        uint256 feeTokens = tokenAmount.mul(handle.mintFeePerMille()).div(1000);

        require(
            vaultLibrary.getFreeCollateralAsEth(msg.sender, token) >=
                vaultLibrary.getMinimumCollateral(
                    tokenAmount.add(feeTokens),
                    vaultLibrary.getMinimumRatio(msg.sender, token),
                    quote
                ),
            "CR"
        );

        _mint(tokenAmount, token, quote, feeTokens);
    }

    /**
     * @dev Burns fxToken debt from sender's vault.
     * @param amount The amount of fxTokens to burn.
     * @param token The token to burn.
     * @param deadline The time on which the transaction is invalid.
     */
    function burn(
        uint256 amount,
        address token,
        uint256 deadline
    )
        external
        override
        dueBy(deadline)
        validFxToken(token)
        notPaused
        nonReentrant
    {
        require(amount > 0, "IA");
        // Token balance must be higher or equal than burn amount.
        require(IfxToken(token).balanceOf(msg.sender) >= amount, "IA");
        uint256 quote = handle.getTokenPrice(token);

        {
            // Treasury debt must be higher or equal to burn amount.
            uint256 maxAmount = handle.getDebt(msg.sender, token);
            if (amount > maxAmount) amount = maxAmount;
            if (amount != maxAmount)
                _ensureMinimumMintingAmount(
                    msg.sender,
                    token,
                    quote,
                    amount,
                    false
                );
        }

        // Update interest rates according to cache time.
        IInterest(handle.interest()).tryUpdateRates();

        // Store balance for assertion purposes.
        uint256 balanceBefore = IfxToken(token).balanceOf(msg.sender);

        // Charge burn fee as collateral Ether equivalent of fxToken amount.
        uint256 fee =
            amount
                .mul(handle.burnFeePerMille())
                .mul(quote)
            // Cancel out fee ratio unit after fee multiplication.
                .div(1000)
            // Cancel out token unit after price multiplication.
                .div(vaultLibrary.getTokenUnit(token));
        // Withdraw any available collateral type for fee.
        treasury.forceWithdrawAnyCollateral(
            msg.sender,
            handle.FeeRecipient(),
            fee,
            token,
            true
        );

        // Burn tokens
        IfxToken(token).burn(msg.sender, amount);
        assert(
            IfxToken(token).balanceOf(msg.sender) == balanceBefore.sub(amount)
        );

        // Update debt position
        uint256 debtPositionBefore = handle.getDebt(msg.sender, token);
        handle.updateDebtPosition(msg.sender, amount, token, false);
        assert(
            handle.getDebt(msg.sender, token) == debtPositionBefore.sub(amount)
        );

        // Unstake from the reward pool.
        IRewardPool rewards = IRewardPool(handle.rewards());
        (bool found, uint256 rewardPoolId) =
            rewards.getPoolIdByAlias(
                rewards.getFxTokenPoolAlias(
                    token,
                    uint256(RewardPoolCategory.Mint)
                )
            );
        if (found) rewards.unstake(msg.sender, amount, rewardPoolId);

        emit BurnToken(amount, token);
    }

    /**
     * @dev Reverts the transaction if the resulting vault debt does not
            meet the configured minimum mint amount set by the protocol.
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @param tokenPrice The fxToken price
     * @param deltaAmount The amount to be minted or burned.
     * @param isMinting Whether the transaction will mint or burn the fxToken.  
     */
    function _ensureMinimumMintingAmount(
        address account,
        address fxToken,
        uint256 tokenPrice,
        uint256 deltaAmount,
        bool isMinting
    ) private {
        if (minimumMintingAmount == 0) return;
        // Check that new principal will meet minimum mint amount after mint.
        uint256 principal = handle.getPrincipalDebt(account, fxToken);
        if (isMinting) {
            principal = principal.add(deltaAmount);
        } else if (principal <= deltaAmount) {
            revert("IA");
        } else {
            principal = principal.sub(deltaAmount);
        }
        // Convert minimum amount to fxToken equivalent.
        uint256 minimumFxAmount =
            minimumMintingAmount.mul(1 ether).div(tokenPrice);
        // Round fxAmount up to the nearest 100.
        uint256 roundBy = 100 ether;
        minimumFxAmount = ((minimumFxAmount + roundBy - 1) / roundBy) * roundBy;
        require(principal >= minimumFxAmount, "IA");
    }

    /**
     * @dev Calls the referral function to set a referral if this is the first
            time the user interacts with the protocol.
     * @param user The user address.
     * @param referral The referrer address.
     */
    function _trySetReferral(address user, address referral) private {
        IReferral(handle.referral()).setReferral(user, referral);
    }

    /** @dev Protected UUPS upgrade authorization fuction */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

