// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeMath.sol";
import "./IHandle.sol";
import "./ITreasury.sol";
import "./IPCT.sol";
import "./IPCTProtocolInterface.sol";
import "./SafeERC20.sol";
import "./HandlePausable.sol";

/**
 * @dev Implements a scalable pool for keeping track of user collateral shares
        and an interface to interact with bridges to external investment
        protocols.
 */
contract PCT is
    IPCT,
    Initializable,
    UUPSUpgradeable,
    HandlePausable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string internal constant notAnInterface = "PCT: not an interface";
    string internal constant accessDenied = "PCT: access denied";

    /** @dev The Handle contract interface */
    IHandle private handle;
    /** @dev The Treasury contract interface */
    ITreasury private treasury;

    /** @dev mapping(collateral => PCT pool data) */
    mapping(address => Pool) private pools;
    /** @dev Ratio of accrued interest sent to protocol, where 1 ETH = 100% */
    uint256 public override protocolFee;

    modifier validInterface(address collateralToken, address pia) {
        require(pools[collateralToken].protocolInterfaces[pia], notAnInterface);
        _;
    }

    /** @dev Proxy initialisation function */
    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    receive() external payable {}

    /**
     * @dev Setter for Handle contract reference
     * @param _handle The Handle contract address
     */
    function setHandleContract(address _handle) public override onlyOwner {
        handle = IHandle(_handle);
        treasury = ITreasury(handle.treasury());
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /**
     * @dev Stakes tokens
     * @param account The account to stake with
     * @param amount The amount to stake
     * @param fxToken The deposit fxToken
     * @param collateralToken The pool token address
     */
    function stake(
        address account,
        uint256 amount,
        address fxToken,
        address collateralToken
    ) external override notPaused nonReentrant returns (uint256 errorCode) {
        require(
            msg.sender == account || msg.sender == address(treasury),
            accessDenied
        );
        if (amount == 0) return 1;
        uint256 vaultCollateral =
            handle.getCollateralBalance(account, collateralToken, fxToken);
        // User must hold enough collateral.
        if (vaultCollateral < amount) return 2;
        // Transfer must not exceed per-user upper bound.
        uint256 maxDueToUpperBound =
            vaultCollateral.mul(handle.pctCollateralUpperBound()).div(1 ether);
        // Assert that current stake does not exceed max for vault.
        uint256 stake = balanceOfStake(account, fxToken, collateralToken);
        if (stake >= maxDueToUpperBound) return 3;
        // Calculate max stake remaining and cap amount if needed.
        uint256 maxStakeRemaining = maxDueToUpperBound.sub(stake);
        if (amount > maxStakeRemaining) amount = maxStakeRemaining;
        // Proceed with staking.
        Pool storage pool = pools[collateralToken];
        Deposit storage deposit = pool.deposits[account][fxToken];
        checkUpdateConfirmedDeposit(pool, deposit);
        // Withdraw existing collateral rewards, if any.
        _claimInterest(account, fxToken, collateralToken);
        // Update total deposits.
        pool.totalDeposits = pool.totalDeposits.add(amount);
        // Update deposit properties.
        deposit.amount_flagged = deposit.amount_flagged.add(amount);
        deposit.S = pool.S;
        deposit.N = pool.N.add(1);
        emit Stake(account, fxToken, collateralToken, amount);
        return 0;
    }

    /**
     * @dev Will do one of two things:
            1) Notifies PCT that staked collateral might no longer be
               available in Treasury if already invested.
            2) If the staked amount hasn't been invested yet,
               simply unstake it.
     * @param account The account to unstake with
     * @param amount The amount to unstake
     * @param fxToken The deposit fxToken
     * @param collateralToken The pool token address
     */
    function unstake(
        address account,
        uint256 amount,
        address fxToken,
        address collateralToken
    ) external override notPaused nonReentrant returns (uint256 errorCode) {
        require(
            msg.sender == account || msg.sender == address(treasury),
            accessDenied
        );
        uint256 stakedAmount =
            balanceOfStake(account, fxToken, collateralToken);
        if (amount > stakedAmount) amount = stakedAmount;
        if (amount == 0) return 1;
        Pool storage pool = pools[collateralToken];
        Deposit storage deposit = pool.deposits[account][fxToken];
        checkUpdateConfirmedDeposit(pool, deposit);
        // Withdraw existing collateral rewards, if any.
        _claimInterest(account, fxToken, collateralToken);
        // Accrue new interest from this point.
        deposit.S = pool.S;
        if (amount <= deposit.amount_flagged) {
            // Remove only flagged amount, which hasn't been invested yet.
            deposit.amount_flagged = deposit.amount_flagged.sub(amount);
            // Total deposits should only subtract flagged deposit, as
            // the confirmed deposit is subtracted during investment withdrawal.
            pool.totalDeposits = pool.totalDeposits.sub(amount);
        } else {
            uint256 unstakeConfirmed = amount.sub(deposit.amount_flagged);
            pool.totalDeposits = pool.totalDeposits.sub(deposit.amount_flagged);
            deposit.amount_flagged = 0;
            deposit.amount_confirmed = deposit.amount_confirmed.sub(
                unstakeConfirmed
            );
        }
        emit Unstake(account, fxToken, collateralToken, amount);
        return 0;
    }

    /**
     * @dev Claims interest from pool
     * @param fxToken The deposit fxToken
     * @param collateralToken The pool token address
     */
    function claimInterest(address fxToken, address collateralToken)
        external
        override
        notPaused
        nonReentrant
    {
        Pool storage pool = pools[collateralToken];
        Deposit storage deposit = pool.deposits[msg.sender][fxToken];
        checkUpdateConfirmedDeposit(pool, deposit);
        uint256 claimed = _claimInterest(msg.sender, fxToken, collateralToken);
        require(claimed > 0, "PCT: no claimable interest");
        // Update deposit S value so new interest is accrued from this point.
        deposit.S = pool.S;
    }

    /**
     * @dev Claims interest from pool
     * @param account The account to claim interest with
     * @param fxToken The deposit fxToken
     * @param collateralToken The pool token address
     */
    function _claimInterest(
        address account,
        address fxToken,
        address collateralToken
    ) private returns (uint256 claimed) {
        Pool storage pool = pools[collateralToken];
        Deposit storage deposit = pool.deposits[account][fxToken];
        // Withdraw all collateral rewards.
        claimed = _balanceOfClaimableInterest(pool, deposit);
        if (claimed == 0) return 0;
        // Reduce from total accrued.
        pool.totalAccrued = pool.totalAccrued.sub(claimed);
        // Increase collateral balance.
        handle.updateCollateralBalance(
            account,
            claimed,
            fxToken,
            collateralToken,
            true
        );
        emit ClaimInterest(account, collateralToken, claimed);
    }

    /**
     * @dev Sets a protocol interface as valid
     * @param collateralToken The pool token
     * @param pia The protocol interface address
     */
    function setProtocolInterface(address collateralToken, address pia)
        external
        override
        onlyOwner
    {
        IPCTProtocolInterface pi = IPCTProtocolInterface(pia);
        require(
            pi.investedToken() == collateralToken,
            "PCT: interface token mismatch"
        );
        Pool storage pool = pools[collateralToken];
        require(!pool.protocolInterfaces[pia], "PCT: interface already set");
        pool.protocolInterfaces[pia] = true;
        emit SetProtocolInterface(pia, collateralToken);
    }

    /**
     * @dev Removes a protocol interface
     * @param collateralToken The pool token
     * @param pia The protocol interface address
     */
    function unsetProtocolInterface(address collateralToken, address pia)
        external
        override
        onlyOwner
    {
        Pool storage pool = pools[collateralToken];
        require(pool.protocolInterfaces[pia], notAnInterface);
        pools[collateralToken].protocolInterfaces[pia] = false;
        emit UnsetProtocolInterface(pia, collateralToken);
    }

    /**
     * @dev Claims accrued interest from external protocol.
     * @param collateralToken The pool token
     * @param pia The protocol interface address
     */
    function claimProtocolInterest(address collateralToken, address pia)
        external
        override
        onlyOwner
        nonReentrant
        validInterface(collateralToken, pia)
    {
        uint256 balanceA = IERC20(collateralToken).balanceOf(address(treasury));
        IPCTProtocolInterface pi = IPCTProtocolInterface(pia);
        uint256 amount = pi.withdrawRewards();
        uint256 balanceB = IERC20(collateralToken).balanceOf(address(treasury));
        require(balanceB == balanceA.add(amount), "PCT: claim transfer failed");
        distributeInterest(collateralToken, amount);
        ensureUpperBoundLimit(pi, collateralToken);
        emit ProtocolClaimInterest(pia, collateralToken, amount);
    }

    /**
     * @dev Deposits funds into a protocol as an investment
     * @param collateralToken The collateral to deposit
     * @param pia The protocol interface address
     * @param ratio The ratio (0 to 1, 18 decimals) of available collateral
             to deposit into the protocol. 
     */
    function depositProtocolFunds(
        address collateralToken,
        address pia,
        uint256 ratio
    )
        external
        override
        onlyOwner
        nonReentrant
        validInterface(collateralToken, pia)
    {
        require(ratio > 0 && ratio <= 1 ether, "PCT: invalid ratio (0<R<=1)");
        Pool storage pool = pools[collateralToken];
        require(pool.totalDeposits > 0, "PCT: no funds available");
        uint256 amount = pool.totalDeposits.mul(ratio).div(1 ether);
        // Request withdraw via protocol interface, which will call returnFunds.
        IPCTProtocolInterface(pia).deposit(amount);
        // Increase investments; decrease deposits.
        pool.totalInvestments = pool.totalInvestments.add(amount);
        pool.protocolInvestments[pia] = pool.protocolInvestments[pia].add(
            amount
        );
        pool.totalDeposits = pool.totalDeposits.sub(amount);
        // Total amount staked during investment. Used to calculate shares.
        pool.totalDepositsAtInvestment = pool.totalDeposits.add(
            pool.totalInvestments
        );
        // Increase N to confirm recent deposits.
        pool.N = pool.N.add(1);
        emit ProtocolDepositFunds(pia, collateralToken, amount);
    }

    /**
     * @dev Withdraws invested funds from a protocol
     * @param collateralToken The collateral to withdraw
     * @param pia The protocol interface address
     * @param amount The amount of collateral to withdraw
     */
    function withdrawProtocolFunds(
        address collateralToken,
        address pia,
        uint256 amount
    ) external override onlyOwner nonReentrant {
        Pool storage pool = pools[collateralToken];
        uint256 currentInvestments = pool.protocolInvestments[pia];
        require(currentInvestments > 0, "PCT: not invested");
        IPCTProtocolInterface pi = IPCTProtocolInterface(pia);
        // Withdraw any unstaked collateral first.
        ensureUpperBoundLimit(pi, collateralToken);
        // Cap amount to totalInvestments.
        uint256 totalInvestments = pool.totalInvestments;
        if (amount > totalInvestments) amount = totalInvestments;
        // Request withdraw via protocol interface, which will call returnFunds.
        pi.withdraw(amount);
        // Decrease investments; increase deposits.
        pool.totalInvestments = totalInvestments.sub(amount);
        pool.protocolInvestments[pia] = currentInvestments.sub(amount);
        pool.totalDeposits = pool.totalDeposits.add(amount);
    }

    /**
     * @dev Requests funds from Treasury for a PCT protocol interface
     * @param collateralToken The pool token invested
     * @param requestedToken The token to request (protocol token or collateral token)
     * @param amount The amount of token to request
     */
    function requestTreasuryFunds(
        address collateralToken,
        address requestedToken,
        uint256 amount
    ) external override notPaused validInterface(collateralToken, msg.sender) {
        treasury.requestFundsPCT(requestedToken, amount);
        IERC20(requestedToken).safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Returns funds to Treasury from a PCT protocol interface
     * @param collateralToken The pool token invested
     * @param returnedToken The token to return (protocol token or collateral)
     * @param amount The amount of token to send
     */
    function returnTreasuryFunds(
        address collateralToken,
        address returnedToken,
        uint256 amount
    ) external override notPaused validInterface(collateralToken, msg.sender) {
        IERC20(returnedToken).safeTransferFrom(
            msg.sender,
            address(treasury),
            amount
        );
        emit ProtocolReturnFunds(msg.sender, returnedToken, amount);
    }

    function setProtocolFee(uint256 ratio) external override onlyOwner {
        require(ratio <= 1 ether, "PCT: invalid ratio (0<=R<=1)");
        protocolFee = ratio;
    }

    /**
     * @dev Distributes interest for stakers
     * @param collateralToken The pool token
     * @param amount The amount to distribute
     */
    function distributeInterest(address collateralToken, uint256 amount)
        private
    {
        // Calculate and transfer fee.
        uint256 fee = amount.mul(protocolFee).div(1 ether);
        treasury.requestFundsPCT(collateralToken, fee);
        IERC20(collateralToken).safeTransfer(handle.FeeRecipient(), fee);
        amount = amount.sub(fee);
        // Distribute pool rewards.
        Pool storage pool = pools[collateralToken];
        uint256 deltaS =
            amount.mul(1 ether).div(pool.totalDepositsAtInvestment);
        pool.S = pool.S.add(deltaS);
        pool.totalAccrued = pool.totalAccrued.add(amount);
    }

    /**
     * @dev Checks the Treasury's collateral balance and total invested funds
            against maximum upper bound and withdraws from external protocol
            into Treasury if needed.
     * @param pi The PCT protocol interface
     * @param collateralToken The pool token address
     */
    function ensureUpperBoundLimit(
        IPCTProtocolInterface pi,
        address collateralToken
    ) private {
        Pool storage pool = pools[collateralToken];
        address pia = address(pi);
        uint256 totalInvested = pool.totalInvestments;
        uint256 totalFunds =
            IERC20(collateralToken).balanceOf(address(treasury)).add(
                totalInvested
            );
        uint256 upperBound = handle.pctCollateralUpperBound();
        uint256 maxInvestmentAmount = totalFunds.mul(upperBound).div(1 ether);
        if (totalInvested <= maxInvestmentAmount) return;
        // Upper bound limit has been exceeded; withdraw from external protocol.
        uint256 diff = totalInvested.sub(maxInvestmentAmount);
        assert(pool.protocolInvestments[pia] >= diff);
        pi.withdraw(diff);
        pool.totalInvestments = pool.totalInvestments.sub(diff);
        pool.protocolInvestments[pia] = pool.protocolInvestments[pia].sub(diff);
    }

    /**
     * @dev retrieves the total staked amount for account vault
     * @param account The address to fetch balance from
     * @param fxToken The deposit fxToken
     * @param collateralToken The pool token address
     */
    function balanceOfStake(
        address account,
        address fxToken,
        address collateralToken
    ) public view override returns (uint256 amount) {
        Deposit storage deposit =
            pools[collateralToken].deposits[account][fxToken];
        return deposit.amount_confirmed.add(deposit.amount_flagged);
    }

    /**
     * @dev Retrieves account's current claimable interest amount
     * @param account The address to fetch claimable interest from
     * @param fxToken The deposit fxToken
     * @param collateralToken The pool token address
     */
    function balanceOfClaimableInterest(
        address account,
        address fxToken,
        address collateralToken
    ) public view override returns (uint256 amount) {
        Pool storage pool = pools[collateralToken];
        Deposit storage deposit = pool.deposits[account][fxToken];
        return _balanceOfClaimableInterest(pool, deposit);
    }

    /**
     * @dev Getter for user's balance of claimable interest
     * @param pool The pool reference
     * @param deposit The deposit reference
     */
    function _balanceOfClaimableInterest(
        Pool storage pool,
        Deposit storage deposit
    ) private view returns (uint256 amount) {
        // Return zero if pool was not initialised.
        if (pool.S == 0) return 0;
        // It should be impossible for deposit.S > pool.S.
        uint256 deltaS = pool.S.sub(deposit.S);
        uint256 confirmedDeposit = getConfirmedDeposit(pool, deposit);
        amount = confirmedDeposit.mul(deltaS).div(1 ether);
        // Subtract 1 wei from total amount in case the final value
        // had a "decimal" >= 0.5 wei and was therefore rounded up.
        if (amount > 0) amount = amount - 1;
    }

    /**
     * @dev Checks whether the deposit has been confirmed
     * @param pool The pool reference
     * @param deposit The deposit reference
     */
    function getConfirmedDeposit(Pool storage pool, Deposit storage deposit)
        private
        view
        returns (uint256)
    {
        // If deposit N > pool N then flagged deposit has not been confirmed.
        return
            deposit.N <= pool.N
                ? deposit.amount_flagged.add(deposit.amount_confirmed)
                : deposit.amount_confirmed;
    }

    /**
     * @dev Checks whether the user deposit has been confirmed.
     * @param pool The pool reference
     * @param deposit The deposit reference
     */
    function checkUpdateConfirmedDeposit(
        Pool storage pool,
        Deposit storage deposit
    ) private {
        // If deposit N > pool N then deposit has not been confirmed.
        if (deposit.N > pool.N) return;
        // Add to confirmed and reset flagged.
        deposit.amount_confirmed = deposit.amount_confirmed.add(
            deposit.amount_flagged
        );
        deposit.amount_flagged = 0;
    }

    /**
     * @dev Getter for total pool deposit/stake
     * @param collateralToken The pool token
     */
    function getTotalDeposits(address collateralToken)
        external
        view
        override
        returns (uint256 amount)
    {
        return pools[collateralToken].totalDeposits;
    }

    /**
     * @dev Getter for total investments across all protocol interfaces
     * @param collateralToken The pool token
     */
    function getTotalInvestments(address collateralToken)
        external
        view
        override
        returns (uint256 amount)
    {
        return pools[collateralToken].totalInvestments;
    }

    /**
     * @dev Getter for total invested amounts per protocol interface
     * @param collateralToken The pool token
     * @param pia The protocol interface address
     */
    function getProtocolInvestments(address collateralToken, address pia)
        external
        view
        override
        returns (uint256 amount)
    {
        return pools[collateralToken].protocolInvestments[pia];
    }

    /**
     * @dev Getter for total pool accrued interest
     * @param collateralToken The pool token
     */
    function getTotalAccruedInterest(address collateralToken)
        external
        view
        override
        returns (uint256 amount)
    {
        return pools[collateralToken].totalAccrued;
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

