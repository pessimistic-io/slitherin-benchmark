// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ITreasury.sol";
import "./IWETH.sol";
import "./IVaultLibrary.sol";
import "./IHandle.sol";
import "./IHandleComponent.sol";
import "./IPCT.sol";
import "./IInterest.sol";
import "./IReferral.sol";
import "./IRewardPool.sol";
import "./Roles.sol";

/**
 * @dev Provides deposit and withdrawal functions for vaults.
        Holds all protocol funds.
 */
contract Treasury is
    ITreasury,
    Initializable,
    UUPSUpgradeable,
    IHandleComponent,
    Roles,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /** @dev The Handle contract interface */
    IHandle private handle;
    /** @dev The VaultLibrary contract interface */
    IVaultLibrary private vaultLibrary;
    /** @dev The canonical WETH address */
    address private WETH;

    /** @dev Variable to keep track of total deposits, converted to ETH at
             the time of the deposit. Used to limit the max. deposits in the
             contract for safety reasons during the initial deployment to
             mainnet. */
    uint256 public totalCollateralDeposited;
    /** @dev Maximum deposit allowed (in ETH). A value of 0 means no maximum */
    uint256 public maximumTotalDepositAllowed;

    address private self;

    /** @dev Proxy initialisation function */
    function initialize() public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        self = address(this);
    }

    /**
     * @dev Setter for maximumTotalDepositAllowed
     * @param value The maximum deposit allowed in ETH.
     */
    function setMaximumTotalDepositAllowed(uint256 value)
        external
        override
        onlyAdmin
    {
        maximumTotalDepositAllowed = value;
    }

    /**
     * @dev Setter for Handle contract reference
     * @param _handle The Handle contract address
     */
    function setHandleContract(address _handle) public override onlyAdmin {
        handle = IHandle(_handle);
        WETH = handle.WETH();
        // Grant roles as needed.
        uint256 operatorCount = 3;
        address[] memory operators = new address[](operatorCount);
        operators[0] = handle.comptroller();
        operators[1] = handle.fxKeeperPool();
        operators[2] = handle.liquidator();
        for (uint256 i = 0; i < operatorCount; i++) {
            if (!hasRole(OPERATOR_ROLE, operators[i]))
                grantRole(OPERATOR_ROLE, operators[i]);
        }
        // Update interface references.
        vaultLibrary = IVaultLibrary(handle.vaultLibrary());
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /** Allow any incoming ETH transfers. */
    receive() external payable {}

    /**
     * @dev Deposits collateral into a vault.
     * @param to The vault account to deposit into.
     * @param amount The amount to deposit.
     * @param collateralToken The type of collateral to deposit.
     * @param fxToken The vault fxToken.
     * @param referral The referral account.
     */
    function depositCollateral(
        address to,
        uint256 amount,
        address collateralToken,
        address fxToken,
        address referral
    ) external override nonReentrant {
        _trySetReferral(to, referral);
        _depositCollateral(msg.sender, to, amount, collateralToken, fxToken);
    }

    /**
     * @dev Deposits ETH collateral into a vault as WETH.
     * @param to The vault account to deposit into.
     * @param fxToken The vault fxToken.
     * @param referral The referral account.
     */
    function depositCollateralETH(
        address to,
        address fxToken,
        address referral
    ) external payable override nonReentrant {
        require(handle.isCollateralValid(WETH), "IC");
        _trySetReferral(to, referral);
        // Wrap incoming ether into WETH
        IWETH(WETH).deposit{value: msg.value}();
        // Deposit WETH for the user.
        _depositCollateral(self, to, msg.value, WETH, fxToken);
    }

    /**
     * @dev Deposits collateral into a vault.
     * @param from The address to deposit from.
     * @param to The vault account to deposit into.
     * @param depositAmount The amount of collateral to deposit.
     * @param fxToken The vault fxToken.
     */
    function _depositCollateral(
        address from,
        address to,
        uint256 depositAmount,
        address collateralToken,
        address fxToken
    ) private {
        require(handle.isCollateralValid(collateralToken), "IC");

        // Ensure Treasury has self-allowance on ERC20 to wrap for the user.
        // This is needed on Arbitrum for ETH->WETH deposits.
        if (
            from == self &&
            IERC20(collateralToken).allowance(self, self) < depositAmount
        ) {
            IERC20(collateralToken).safeApprove(self, 0);
            IERC20(collateralToken).safeApprove(self, 2**256 - 1);
        }

        // Ensure that this deposit won't result in the total ETH cap being
        uint256 newTotalEthDeposits =
            totalCollateralDeposited.add(
                depositAmount.mul(handle.getTokenPrice(collateralToken)).div(
                    vaultLibrary.getTokenUnit(collateralToken)
                )
            );
        require(
            maximumTotalDepositAllowed == 0 ||
                newTotalEthDeposits <= maximumTotalDepositAllowed,
            "IA"
        );
        totalCollateralDeposited = newTotalEthDeposits;

        // Update interest rates according to cache time.
        IInterest(handle.interest()).tryUpdateRates();

        // Calculate fee and actual deposit amount.
        uint256 fee = depositAmount.mul(handle.depositFeePerMille()).div(1000);
        depositAmount = depositAmount.sub(fee);

        // Transfer collateral into the treasury
        IERC20(collateralToken).safeTransferFrom(from, self, depositAmount);

        handle.updateCollateralBalance(
            to,
            depositAmount,
            fxToken,
            collateralToken,
            true
        );

        // Transfer fee.
        IERC20(collateralToken).safeTransferFrom(
            from,
            handle.FeeRecipient(),
            fee
        );

        // Stake into PCT and RewardPool.
        handleStaking(to, fxToken, collateralToken, depositAmount, true);
    }

    /**
     * @dev Withdraws collateral from the sender's account
     * @param collateralToken The collateral token to withdraw
     * @param to The address to remit to
     * @param amount The amount of collateral to withdraw
     * @param fxToken The vault fxToken
     */
    function withdrawCollateral(
        address collateralToken,
        address to,
        uint256 amount,
        address fxToken
    ) external override nonReentrant {
        // Update interest rates according to cache time.
        IInterest(handle.interest()).tryUpdateRates();
        _withdrawCollateralFrom(
            msg.sender,
            collateralToken,
            to,
            amount,
            fxToken
        );
    }

    /**
     * @dev Withdraws collateral from a vault
     * @param from The vault account to withdraw from
     * @param collateralToken The collateral token to withdraw
     * @param to The address to remit to
     * @param amount The amount of collateral to withdraw
     * @param fxToken The vault fxToken
     */
    function withdrawCollateralFrom(
        address from,
        address collateralToken,
        address to,
        uint256 amount,
        address fxToken
    ) external override onlyAddressOrOperatorExcludeAdmin(from) nonReentrant {
        // Update interest rates according to cache time.
        IInterest(handle.interest()).tryUpdateRates();
        _withdrawCollateralFrom(from, collateralToken, to, amount, fxToken);
    }

    /**
     * @dev Withdraws WETH collateral as ETH
     * @param to The address to remit to
     * @param amount The amount of collateral to withdraw
     * @param fxToken The vault fxToken
     */
    function withdrawCollateralETH(
        address to,
        uint256 amount,
        address fxToken
    ) external override nonReentrant {
        // Update interest rates according to cache time.
        IInterest(handle.interest()).tryUpdateRates();
        _withdrawCollateralFrom(msg.sender, address(0), to, amount, fxToken);
    }

    /**
     * @dev Withdraws collateral from a vault if the resulting CR meets the
            minimum CR required. Can be used for all collateral types
     * @param from The vault account to withdraw from
     * @param collateralToken The vault collateral token to withdraw
     * @param to The address to remit to
     * @param amount The amount of collateral to withdraw
     * @param fxToken The vault fxToken
     */
    function _withdrawCollateralFrom(
        address from,
        address collateralToken,
        address to,
        uint256 amount,
        address fxToken
    ) private {
        address parsedCollateralToken =
            collateralToken == address(0) ? WETH : collateralToken;
        uint256 collateralRate = handle.getTokenPrice(parsedCollateralToken);
        // The available ERC20 amount.
        uint256 available =
            vaultLibrary
                .getFreeCollateralAsEth(from, fxToken)
                .mul(vaultLibrary.getTokenUnit(parsedCollateralToken))
                .div(collateralRate);
        uint256 collateralBalance =
            handle.getCollateralBalance(from, parsedCollateralToken, fxToken);

        if (available > collateralBalance) available = collateralBalance;

        require(available > 0, "CA");

        if (amount > available) amount = available;

        _forceWithdrawCollateral(from, collateralToken, to, amount, fxToken);
    }

    /**
     * @dev Withdraws any collateral type available in a vault.
            Uses the sorted liquidation collateral order from VaultLibrary.
     * @param from The owner of the vault to withdraw from
     * @param to The address to remit to
     * @param amount The amount of collateral to withdraw
     * @param fxToken The vault to withdraw from
     */
    function forceWithdrawAnyCollateral(
        address from,
        address to,
        uint256 amount,
        address fxToken,
        bool requireFullAmount
    )
        external
        override
        onlyOperator
        nonReentrant
        returns (
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts
        )
    {
        bool metAmount;
        (collateralTypes, collateralAmounts, metAmount) = vaultLibrary
            .getCollateralForAmount(from, fxToken, amount);
        if (requireFullAmount && !metAmount) revert("IA");

        uint256 j = collateralTypes.length;
        for (uint256 i = 0; i < j; i++) {
            if (collateralAmounts[i] == 0) continue;
            _forceWithdrawCollateral(
                from,
                collateralTypes[i],
                to,
                collateralAmounts[i],
                fxToken
            );
        }
    }

    /**
     * @dev Forces collateral withdraw, bypassing vault CR checks.
            Can be used for all collateral types.
     * @param from The owner of the vault to withdraw from
     * @param collateralToken The token to withdraw
     * @param to The address to remit to
     * @param amount The amount of collateral to withdraw
     * @param fxToken The vault to withdraw from
     */
    function forceWithdrawCollateral(
        address from,
        address collateralToken,
        address to,
        uint256 amount,
        address fxToken
    ) external override onlyOperator nonReentrant {
        // Require that user has enough collateral.
        require(
            handle.getCollateralBalance(from, collateralToken, fxToken) >=
                amount,
            "CA"
        );
        _forceWithdrawCollateral(from, collateralToken, to, amount, fxToken);
    }

    /**
     * @dev Forces a collateral withdrawal, bypassing minimum CR checks.
     * @param from The vault account to withdraw from
     * @param collateralToken The vault collateral token to withdraw
     * @param to The account to send the funds to
     * @param amount The amount to be withdrawn
     * @param fxToken The vault fxToken
     */
    function _forceWithdrawCollateral(
        address from,
        address collateralToken,
        address to,
        uint256 amount,
        address fxToken
    ) private {
        bool isEth = collateralToken == address(0);
        if (isEth) collateralToken = WETH;

        // Calculate and transfer fee.
        // Set withdraw fee to zero if recipient is FeeRecipient.
        // Send fees as WETH even if ETH in favour of function size.
        address feeRecipient = handle.FeeRecipient();
        uint256 fee =
            to != feeRecipient
                ? amount.mul(handle.withdrawFeePerMille()).div(1000)
                : 0;

        if (fee > 0) IERC20(collateralToken).safeTransfer(feeRecipient, fee);

        handle.updateCollateralBalance(
            from,
            amount,
            fxToken,
            collateralToken,
            false
        );

        // Unstake from PCT and RewardPool.
        handleStaking(from, fxToken, collateralToken, amount, false);

        uint256 withdrawAmount = amount - fee;
        // Remit collateral to the user
        if (!isEth) {
            uint256 balanceBefore = IERC20(collateralToken).balanceOf(to);
            IERC20(collateralToken).safeTransfer(to, withdrawAmount);
            uint256 balanceAfter = IERC20(collateralToken).balanceOf(to);
            assert(balanceBefore + withdrawAmount == balanceAfter);
        } else {
            IWETH(WETH).withdraw(withdrawAmount);
            bool success;
            (success, ) = to.call{value: withdrawAmount}("");
            require(success, "FP");
        }
    }

    /**
     * @dev Stakes or unstakes user collateral into/from the PCT and rewards.
            Keeps track of collateral shares per-user as investments
            are made for the PCT, and FOREX rewards for the RewardPool.
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @param collateralToken The vault collateral token
     * @param amount The amount to stake/unstake
     * @param isStaking Whether staking or otherwise unstaking collateral
     */
    function handleStaking(
        address account,
        address fxToken,
        address collateralToken,
        uint256 amount,
        bool isStaking
    ) private {
        uint256 upperBound = handle.pctCollateralUpperBound();
        IRewardPool rewards = IRewardPool(handle.rewards());
        (bool foundRewardPool, uint256 rewardPoolId) =
            rewards.getPoolIdByAlias(
                rewards.getFxTokenPoolAlias(
                    fxToken,
                    uint256(RewardPoolCategory.Deposit)
                )
            );
        if (upperBound == 0 && !foundRewardPool) return;
        uint256 pctAmount = (amount * upperBound) / (1 ether);
        IPCT pct = IPCT(handle.pct());
        if (isStaking) {
            if (upperBound > 0)
                pct.stake(account, pctAmount, fxToken, collateralToken);
            if (foundRewardPool) rewards.stake(account, amount, rewardPoolId);
        } else {
            if (upperBound > 0)
                pct.unstake(account, pctAmount, fxToken, collateralToken);
            if (foundRewardPool) rewards.unstake(account, amount, rewardPoolId);
        }
    }

    /**
     * @dev Allows the configured PCT contract to request any funds held by
            the Treasury to be invested in external finance protocols.
     * @param token The token requested.
     * @param amount The amount to be transferred.
     */
    function requestFundsPCT(address token, uint256 amount) external override {
        address pct = handle.pct();
        require(msg.sender == pct, "NO");
        IERC20(token).safeTransfer(pct, amount);
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

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyAdmin {}
}

