// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./SafeMathUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./RewardsRecipient.sol";

import "./IFutureYieldToken.sol";

import "./IPT.sol";
import "./IFutureWallet.sol";
import "./IRateOracle.sol";

import "./IController.sol";
import "./IRegistry.sol";
import "./ITokensFactory.sol";
import "./RoleCheckable.sol";
import "./RegistryStorage.sol";
import "./IFutureVault.sol";
import "./IERC1820RegistryUpgradeable.sol";

/**
 * @title Main future abstraction contract
 * @notice Handles the future mechanisms
 * @dev Basis of all mecanisms for futures (registrations, period switch)
 */
contract FutureVault is
    Initializable,
    RoleCheckable,
    RegistryStorage,
    ReentrancyGuardUpgradeable,
    RewardsRecipient,
    IFutureVault
{
    using SafeMathUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20;

    /* State variables */
    mapping(address => uint256) internal lastPeriodClaimed;

    mapping(address => uint256) internal claimableFYTByUser;
    mapping(uint256 => uint256) internal yieldOfPeriod;
    uint256 internal totalUnderlyingDeposited;

    bool private terminated;

    IFutureYieldToken[] internal fyts;
    /* Delegation */
    struct Delegation {
        address receiver;
        uint256 delegatedAmount;
    }

    mapping(address => mapping(address => uint256))
        internal delegationsByDelegator;
    mapping(address => uint256) internal totalDelegationsReceived;
    mapping(address => uint256) internal totalDelegationsMade;

    /* External contracts */
    IFutureWallet internal futureWallet;
    IERC20 internal ibt;
    IPT internal pt;
    IController internal controller;
    IRateOracle internal rateOracle;

    /* Settings */
    uint256 public override PERIOD_DURATION;
    string public override PLATFORM_NAME;

    /* Constants */
    uint256 internal IBT_UNIT;
    uint256 internal IBT_UNITS_MULTIPLIED_VALUE;
    uint256 constant UNIT = 10**18;

    /* Events */
    event RateOracleSet(IRateOracle _rateOracle);

    /* Modifiers */
    modifier nextPeriodAvailable() {
        uint256 controllerDelay = controller.STARTING_DELAY();
        require(
            controller.getNextPeriodStart(PERIOD_DURATION) <
                block.timestamp.add(controllerDelay),
            "FutureVault: ERR_PERIOD_RANGE"
        );
        _;
    }

    modifier periodsActive() {
        require(!terminated, "FutureVault: PERIOD_TERMINATED");
        _;
    }

    modifier withdrawalsEnabled() {
        require(
            !controller.isWithdrawalsPaused(address(this)),
            "FutureVault: WITHDRAWALS_DISABLED"
        );
        _;
    }

    modifier depositsEnabled() {
        require(
            !controller.isDepositsPaused(address(this)) &&
                getCurrentPeriodIndex() != 0,
            "FutureVault: DEPOSITS_DISABLED"
        );
        _;
    }

    /* Initializer */
    /**
     * @notice Intializer
     * @param _controller the address of the controller
     * @param _ibt the address of the corresponding IBT
     * @param _periodDuration the length of the period (in seconds)
     * @param _platformName the name of the platform and tools
     * @param _admin the address of the ACR admin
     */
    function initialize(
        IController _controller,
        IERC20 _ibt,
        uint256 _periodDuration,
        string memory _platformName,
        address _admin
    ) public virtual initializer {
        controller = _controller;
        ibt = _ibt;
        IBT_UNIT = 10**ibt.decimals();
        IBT_UNITS_MULTIPLIED_VALUE = UNIT * IBT_UNIT;
        PERIOD_DURATION = _periodDuration;
        PLATFORM_NAME = _platformName;
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(CONTROLLER_ROLE, address(_controller));

        fyts.push();

        registry = IRegistry(controller.getRegistryAddress());

        pt = IPT(
            ITokensFactory(
                IRegistry(controller.getRegistryAddress())
                    .getTokensFactoryAddress()
            ).deployPT(
                    ibt.symbol(),
                    ibt.decimals(),
                    PLATFORM_NAME,
                    PERIOD_DURATION
                )
        );

        emit PTSet(pt);
    }

    /* Period functions */

    /**
     * @notice Start a new period
     * @dev needs corresponding permissions for sender
     */
    function startNewPeriod()
        public
        virtual
        override
        nextPeriodAvailable
        periodsActive
        nonReentrant
        onlyController
    {
        _switchPeriod();
    }

    function _switchPeriod() internal periodsActive {
        uint256 nextPeriodID = getNextPeriodIndex();
        uint256 yield = getUnrealisedYieldPerPT().mul(
            totalUnderlyingDeposited
        ) / IBT_UNIT;

        uint256 reinvestedYield;
        if (yield > 0) {
            uint256 currentPeriodIndex = getCurrentPeriodIndex();
            yieldOfPeriod[currentPeriodIndex] = convertIBTToUnderlying(
                yield.mul(IBT_UNIT).div(totalUnderlyingDeposited)
            );
            uint256 collectedYield = yield
                .mul(fyts[currentPeriodIndex].totalSupply())
                .div(totalUnderlyingDeposited);
            reinvestedYield = yield.sub(collectedYield);
            futureWallet.registerExpiredFuture(collectedYield); // Yield deposit in the futureWallet contract
            if (collectedYield > 0)
                ibt.safeTransfer(address(futureWallet), collectedYield);
        } else {
            futureWallet.registerExpiredFuture(0);
        }

        /* Period Switch*/
        totalUnderlyingDeposited = totalUnderlyingDeposited.add(
            convertIBTToUnderlying(reinvestedYield)
        ); // Add newly reinvested yield as underlying
        if (!controller.isFutureSetToBeTerminated(address(this))) {
            _deployNewFutureYieldToken(nextPeriodID);
            emit NewPeriodStarted(nextPeriodID);
        } else {
            terminated = true;
        }
    }

    /* User state */

    /**
     * @notice Update the state of the user and mint claimable pt
     * @param _user user adress
     */
    function updateUserState(address _user) public override {
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        uint256 lastPeriodClaimedOfUser = lastPeriodClaimed[_user];
        if (
            lastPeriodClaimedOfUser < currentPeriodIndex &&
            lastPeriodClaimedOfUser != 0
        ) {
            uint256 claimablePT = _preparePTClaim(_user, currentPeriodIndex);
            if (claimablePT > 0) {
                pt.mint(_user, claimablePT);
            }
        }
        if (lastPeriodClaimedOfUser != currentPeriodIndex)
            lastPeriodClaimed[_user] = currentPeriodIndex;
    }

    function _preparePTClaim(address _user, uint256 _currentPeriodIndex)
        internal
        virtual
        returns (uint256 claimablePT)
    {
        if (lastPeriodClaimed[_user] < _currentPeriodIndex) {
            uint256 totalDelegated = getTotalDelegated(_user);
            claimablePT = getClaimablePT(_user, totalDelegated);
            claimableFYTByUser[_user] = pt
                .balanceOf(_user)
                .add(totalDelegationsReceived[_user])
                .sub(totalDelegated);
            lastPeriodClaimed[_user] = _currentPeriodIndex;
        }
    }

    /**
     * @notice Deposit funds into ongoing period
     * @param _user user address
     * @param _amount amount of IBT transferred into the protocol
     * @dev part of the amount deposited will be used to buy back the yield already generated proportionally to the amount deposited
     */
    function deposit(address _user, uint256 _amount)
        external
        virtual
        override
        nonReentrant
        periodsActive
        depositsEnabled
        onlyController
    {
        require(
            (_amount > 0) && (_amount <= ibt.balanceOf(_user)),
            "FutureVault: ERR_AMOUNT"
        );
        _deposit(_user, _amount);
        emit FundsDeposited(_user, _amount);
    }

    /**
     * @notice Deposit funds into ongoing period
     * @param _user user address for whom funds are deposited
     * @param _sender user address from whom funds are deposited
     * @param _amount amount of IBT transferred into the protocol
     * @dev part of the amount deposited will be used to buy back the yield already generated proportionally to the amount deposited
     */
    function depositForUser(
        address _user,
        address _sender,
        uint256 _amount
    )
        external
        virtual
        override
        nonReentrant
        periodsActive
        depositsEnabled
        onlyController
    {
        require(
            (_amount > 0) && (_amount <= ibt.balanceOf(_sender)),
            "FutureVault: ERR_AMOUNT"
        );
        _deposit(_user, _amount);
        emit FundsDeposited(_user, _amount);
    }

    function _deposit(address _user, uint256 _amount) internal {
        uint256 underlyingDeposited = getPTPerAmountDeposited(_amount);
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        uint256 ptToMint = _preparePTClaim(_user, currentPeriodIndex).add(
            underlyingDeposited
        );

        /* Update State and mint pt*/
        totalUnderlyingDeposited = totalUnderlyingDeposited.add(
            underlyingDeposited
        );
        claimableFYTByUser[_user] = claimableFYTByUser[_user].add(ptToMint);

        pt.mint(_user, ptToMint);
    }

    /**
     * @notice Sender unlocks the locked funds corresponding to their pt holding
     * @param _user user adress
     * @param _amount amount of funds to unlock
     * @dev will require a transfer of FYT of the ongoing period corresponding to the funds unlocked
     */
    function withdraw(address _user, uint256 _amount)
        external
        virtual
        override
        nonReentrant
        periodsActive
        withdrawalsEnabled
        onlyController
    {
        require(
            (_amount > 0) &&
                (_amount.add(getTotalDelegated(_user)) <= pt.balanceOf(_user)),
            "FutureVault: ERR_AMOUNT"
        );
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        IFutureYieldToken futureYieldToken = fyts[currentPeriodIndex];
        require(
            _amount <= futureYieldToken.balanceOf(_user),
            "FutureVault: ERR_FYT_AMOUNT"
        );
        _withdraw(_user, _amount);

        uint256 FYTsToBurn;
        uint256 FYTSMinted = futureYieldToken.recordedBalanceOf(_user);
        if (_amount > FYTSMinted) {
            FYTsToBurn = FYTSMinted;
            uint256 ClaimableFYTsToBurn = _amount - FYTsToBurn;
            claimableFYTByUser[_user] = claimableFYTByUser[_user].sub(
                ClaimableFYTsToBurn,
                "FutureVault: ERR_AMOUNT"
            );
        } else {
            FYTsToBurn = _amount;
        }

        if (FYTsToBurn > 0) futureYieldToken.burnFrom(_user, FYTsToBurn);

        emit FundsWithdrawn(_user, _amount);
    }

    /**
     * @notice Internal function for withdrawing funds corresponding to the pt holding of an address
     * @param _user user adress
     * @param _amount amount of funds to unlock
     * @dev handle the logic of withdraw but does not burn fyts
     */
    function _withdraw(address _user, uint256 _amount) internal virtual {
        updateUserState(_user);
        uint256 fundsToBeUnlocked = _amount.mul(getUnlockableFunds(_user)).div(
            pt.recordedBalanceOf(_user)
        );
        uint256 yieldToBeUnlocked = _amount.mul(getUnrealisedYieldPerPT()) /
            IBT_UNIT;

        ibt.safeTransfer(_user, fundsToBeUnlocked.add(yieldToBeUnlocked));

        totalUnderlyingDeposited = totalUnderlyingDeposited.sub(_amount);
        pt.burnFrom(_user, _amount);
    }

    /* Delegation */

    /**
     * @notice Create a delegation from one address to another
     * @param _delegator the address delegating its future FYTs
     * @param _receiver the address receiving the future FYTs
     * @param _amount the of future FYTs to delegate
     */
    function createFYTDelegationTo(
        address _delegator,
        address _receiver,
        uint256 _amount
    ) public override nonReentrant periodsActive onlyController {
        require(
            _receiver != address(0),
            "ERR: Cannot delegate to zero address"
        );
        require(
            _receiver != address(this),
            "ERR: Cannot delegate to future vault address"
        );
        updateUserState(_delegator);
        updateUserState(_receiver);
        uint256 totalDelegated = getTotalDelegated(_delegator);
        require(
            _amount > 0 &&
                _amount <= pt.balanceOf(_delegator).sub(totalDelegated),
            "FutureVault: ERR_AMOUNT"
        );
        delegationsByDelegator[_delegator][_receiver] = delegationsByDelegator[
            _delegator
        ][_receiver].add(_amount);
        totalDelegationsMade[_delegator] = totalDelegationsMade[_delegator].add(
            _amount
        );
        totalDelegationsReceived[_receiver] = totalDelegationsReceived[
            _receiver
        ].add(_amount);
        emit DelegationCreated(_delegator, _receiver, _amount);
    }

    /**
     * @notice Remove a delegation from one address to another
     * @param _delegator the address delegating its future FYTs
     * @param _receiver the address receiving the future FYTs
     * @param _amount the of future FYTs to remove from the delegation
     */
    function withdrawFYTDelegationFrom(
        address _delegator,
        address _receiver,
        uint256 _amount
    ) public override onlyController {
        updateUserState(_delegator);
        updateUserState(_receiver);
        require(_amount > 0, "FutureVault: ERR_AMOUNT");

        delegationsByDelegator[_delegator][_receiver] = delegationsByDelegator[
            _delegator
        ][_receiver].sub(_amount, "FutureVault: ERR_AMOUNT");
        totalDelegationsMade[_delegator] = totalDelegationsMade[_delegator].sub(
            _amount
        );
        totalDelegationsReceived[_receiver] = totalDelegationsReceived[
            _receiver
        ].sub(_amount);
        emit DelegationRemoved(_delegator, _receiver, _amount);
    }

    /**
     * @notice Getter the total number of FYTs on address is delegating
     * @param _delegator the delegating address
     * @return totalDelegated the number of FYTs delegated
     */
    function getTotalDelegated(address _delegator)
        public
        view
        override
        returns (uint256)
    {
        return totalDelegationsMade[_delegator];
    }

    /* Claim functions */

    /**
     * @notice Send the user their owed FYT (and pt if there are some claimable)
     * @param _user address of the user to send the FYT to
     */
    function claimFYT(address _user, uint256 _amount)
        external
        virtual
        override
        periodsActive
        nonReentrant
    {
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        require(
            msg.sender == address(fyts[currentPeriodIndex]),
            "FutureVault: ERR_CALLER"
        );
        updateUserState(_user);
        _claimFYT(_user, _amount, currentPeriodIndex);
    }

    function _claimFYT(
        address _user,
        uint256 _amount,
        uint256 _currentPeriodIndex
    ) internal virtual {
        claimableFYTByUser[_user] = claimableFYTByUser[_user].sub(
            _amount,
            "FutureVault: ERR_CLAIMED_FYT_AMOUNT"
        );
        fyts[_currentPeriodIndex].mint(_user, _amount);
    }

    /* Termination of the pool */

    /**
     * @notice Exit a terminated pool
     * @param _user the user to exit from the pool
     * @dev only pt are required as there  aren't any new FYTs
     */
    function exitTerminatedFuture(address _user)
        external
        override
        nonReentrant
        onlyController
    {
        require(terminated, "FutureVault: ERR_NOT_TERMINATED");
        uint256 amount = pt.balanceOf(_user);
        require(amount > 0, "FutureVault: ERR_PT_BALANCE");
        _withdraw(_user, amount);
        emit FundsWithdrawn(_user, amount);
    }

    /* Utilitary functions */
    function _deployNewFutureYieldToken(uint256 newPeriodIndex) internal {
        IFutureYieldToken newToken = IFutureYieldToken(
            ITokensFactory(registry.getTokensFactoryAddress())
                .deployNextFutureYieldToken(newPeriodIndex)
        );
        fyts.push(newToken);
    }

    /* Admin function */
    /**
     * @notice Set futureWallet address
     * @param _futureWallet the address of the new futureWallet
     * @dev needs corresponding permissions for sender
     */
    function setFutureWallet(IFutureWallet _futureWallet)
        external
        override
        onlyAdmin
    {
        futureWallet = _futureWallet;
        emit FutureWalletSet(address(_futureWallet));
    }

    /**
     * @notice Set rateOracle address
     * @param _rateOracle the address of the new rateOracle
     * @dev needs corresponding permissions for sender
     */
    function setRateOracleAddress(IRateOracle _rateOracle) external onlyAdmin {
        rateOracle = _rateOracle;
        emit RateOracleSet(_rateOracle);
    }

    /* Getters */
    function convertIBTToUnderlying(uint256 _amount)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _amount.mul(getIBTRate()) / IBT_UNIT;
    }

    function convertIBTToUnderlyingWithRate(uint256 _amount, uint256 _rate)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _amount.mul(_rate) / IBT_UNIT;
    }

    function convertUnderlyingtoIBT(uint256 _amount)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _amount.mul(IBT_UNIT).div(getIBTRate());
    }

    function convertUnderlyingtoIBTWithRate(uint256 _amount, uint256 _rate)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _amount.mul(IBT_UNIT).div(_rate);
    }

    /**
     * @notice Getter for the rate of the IBT
     * @return the uint256 rate, IBT x rate must be equal to the quantity of underlying tokens
     */
    function getIBTRate() public view virtual returns (uint256) {
        if (address(rateOracle) == address(0)) return IBT_UNIT;
        return rateOracle.getIBTRate();
    }

    /**
     * @notice Getter for the amount of pt that the user can claim
     * @param _user user to check the check the claimable pt of
     * @return the amount of pt claimable by the user
     */
    function getClaimablePT(address _user, uint256 _totalDelegated)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        uint256 lastPeriodClaimedUser = lastPeriodClaimed[_user];
        uint256 totalDelegationsReceivedUser = totalDelegationsReceived[_user];

        if (lastPeriodClaimedUser == 0) {
            return 0;
        } else if (lastPeriodClaimedUser < currentPeriodIndex) {
            uint256 recordedBalance = pt.recordedBalanceOf(_user);
            recordedBalance = recordedBalance
                .add(totalDelegationsReceivedUser)
                .sub(_totalDelegated); // add delegated FYTs
            uint256 userStackingGrowthFactor = yieldOfPeriod[
                lastPeriodClaimedUser
            ];
            if (userStackingGrowthFactor > 0) {
                recordedBalance = recordedBalance.add(
                    claimableFYTByUser[_user].mul(userStackingGrowthFactor) /
                        IBT_UNIT
                ); // add reinvested FYTs
            }
            for (
                uint256 i = lastPeriodClaimedUser + 1;
                i < currentPeriodIndex;
                i++
            ) {
                recordedBalance = recordedBalance.add(
                    yieldOfPeriod[i].mul(recordedBalance) / IBT_UNIT
                );
            }
            return
                recordedBalance
                    .add(_totalDelegated)
                    .sub(pt.recordedBalanceOf(_user))
                    .sub(totalDelegationsReceivedUser);
        } else {
            return 0;
        }
    }

    /**
     * @notice Getter for user IBT amount that is unlockable
     * @param _user user to unlock the IBT from
     * @return the amount of IBT the user can unlock
     */
    function getUnlockableFunds(address _user)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertUnderlyingtoIBT(pt.balanceOf(_user));
    }

    /**
     * @notice Getter for the amount of FYT that the user can claim for a certain period
     * @param _user the user to check the claimable FYT of
     * @param _periodIndex period ID to check the claimable FYT of
     * @return the amount of FYT claimable by the user for this period ID
     */
    function getClaimableFYTForPeriod(address _user, uint256 _periodIndex)
        external
        view
        virtual
        override
        returns (uint256)
    {
        uint256 currentPeriodIndex = getCurrentPeriodIndex();

        if (_periodIndex != currentPeriodIndex || _user == address(this)) {
            return 0;
        } else if (
            _periodIndex == currentPeriodIndex &&
            lastPeriodClaimed[_user] == currentPeriodIndex
        ) {
            return claimableFYTByUser[_user];
        } else {
            return
                pt.balanceOf(_user).add(totalDelegationsReceived[_user]).sub(
                    getTotalDelegated(_user)
                );
        }
    }

    /**
     * @notice Getter for the yield currently generated by one pt for the current period
     * @return the amount of yield (in IBT) generated during the current period
     */
    function getUnrealisedYieldPerPT() public view override returns (uint256) {
        uint256 totalUnderlyingAtStart = totalUnderlyingDeposited;
        if (totalUnderlyingAtStart == 0) return 0;
        uint256 rate = getIBTRate();
        uint256 totalUnderlyingNow = convertIBTToUnderlyingWithRate(
            ibt.balanceOf(address(this)),
            rate
        );
        uint256 yieldForAllPT = convertUnderlyingtoIBTWithRate(
            totalUnderlyingNow.sub(totalUnderlyingAtStart),
            rate
        );
        return yieldForAllPT.mul(IBT_UNIT).div(totalUnderlyingAtStart);
    }

    /**
     * @notice Getter for the number of pt that can be minted for an amoumt deposited now
     * @param _amount the amount to of IBT to deposit
     * @return the number of pt that can be minted for that amount
     */
    function getPTPerAmountDeposited(uint256 _amount)
        public
        view
        override
        returns (uint256)
    {
        uint256 rate = getIBTRate();
        uint256 underlyingAmountOfDeposit = convertIBTToUnderlyingWithRate(
            _amount,
            rate
        );
        uint256 underlyingYieldPerPT = convertIBTToUnderlyingWithRate(
            getUnrealisedYieldPerPT(),
            rate
        );
        return
            underlyingAmountOfDeposit.mul(IBT_UNIT).div(
                IBT_UNIT.add(underlyingYieldPerPT)
            );
    }

    /**
     * @notice Getter for the total yield generated during one period
     * @param _periodID the period id
     * @return the total yield in underlying value
     */
    function getYieldOfPeriod(uint256 _periodID)
        external
        view
        override
        returns (uint256)
    {
        require(
            getCurrentPeriodIndex() > _periodID,
            "FutureVault: Invalid period ID"
        );
        return yieldOfPeriod[_periodID];
    }

    /**
     * @notice Getter for next period index
     * @return next period index
     * @dev index starts at 1
     */
    function getNextPeriodIndex()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return fyts.length;
    }

    /**
     * @notice Getter for current period index
     * @return current period index
     * @dev index starts at 1
     */
    function getCurrentPeriodIndex()
        public
        view
        virtual
        override
        returns (uint256)
    {
        if (isTerminated()) {
            return fyts.length;
        }
        return fyts.length - 1;
    }

    /**
     * @notice Getter for total underlying deposited in the vault
     * @return the total amount of funds deposited in the vault (in underlying)
     */
    function getTotalUnderlyingDeposited()
        external
        view
        override
        returns (uint256)
    {
        return totalUnderlyingDeposited;
    }

    /**
     * @notice Getter for controller address
     * @return the controller address
     */
    function getControllerAddress() external view override returns (address) {
        return address(controller);
    }

    /**
     * @notice Getter for futureWallet address
     * @return futureWallet address
     */
    function getFutureWalletAddress() external view override returns (address) {
        return address(futureWallet);
    }

    /**
     * @notice Getter for RateOracle address
     * @return rateOracle address
     */
    function getRateOracleAddress() external view virtual returns (address) {
        return address(rateOracle);
    }

    /**
     * @notice Getter for the IBT address
     * @return IBT address
     */
    function getIBTAddress()
        public
        view
        virtual
        override(IFutureVault, RewardsRecipient)
        returns (address)
    {
        return address(ibt);
    }

    /**
     * @notice Getter for future pt address
     * @return pt address
     */
    function getPTAddress() external view override returns (address) {
        return address(pt);
    }

    /**
     * @notice Getter for FYT address of a particular period
     * @param _periodIndex period index
     * @return FYT address
     */
    function getFYTofPeriod(uint256 _periodIndex)
        external
        view
        override
        returns (address)
    {
        return address(fyts[_periodIndex]);
    }

    /**
     * @notice Getter for the terminated state of the future
     * @return true if this vault is terminated
     */
    function isTerminated() public view override returns (bool) {
        return terminated;
    }

    /**
     * @notice Pause liquidity transfers
     */
    function pauseLiquidityTransfers() external override onlyAdmin {
        pt.pause();
        emit LiquidityTransfersPaused();
    }

    /**
     * @notice Resume liquidity transfers
     */
    function resumeLiquidityTransfers() external override onlyAdmin {
        pt.unpause();
        emit LiquidityTransfersResumed();
    }
}

