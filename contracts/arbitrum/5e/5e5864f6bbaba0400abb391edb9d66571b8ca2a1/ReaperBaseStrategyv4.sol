// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./IStrategy.sol";
import "./ISwapper.sol";
import "./ReaperSwapper.sol";
import "./IVault.sol";
import "./ReaperMathUtils.sol";
import "./ReaperAccessControl.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

abstract contract ReaperBaseStrategyv4 is
    ReaperAccessControl,
    IStrategy,
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable
{
    using ReaperMathUtils for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant PERCENT_DIVISOR = 10_000;
    uint256 public constant UPGRADE_TIMELOCK = 48 hours; // minimum 48 hours for RF
    uint256 public constant FUTURE_NEXT_PROPOSAL_TIME = 365 days * 100;

    // The token the strategy wants to operate
    address public want;

    bool public emergencyExit;
    uint256 public lastHarvestTimestamp;

    uint256 public upgradeProposalTime;

    /**
     * Reaper Roles in increasing order of privilege.
     * {KEEPER} - Stricly permissioned trustless access for off-chain programs or third party keepers.
     * {STRATEGIST} - Role conferred to authors of the strategy, allows for tweaking non-critical params.
     * {GUARDIAN} - Multisig requiring 2 signatures for emergency measures such as pausing and panicking.
     * {ADMIN}- Multisig requiring 3 signatures for unpausing.
     *
     * The DEFAULT_ADMIN_ROLE (in-built access control role) will be granted to a multisig requiring 4
     * signatures. This role would have upgrading capability, as well as the ability to grant any other
     * roles.
     *
     * Also note that roles are cascading. So any higher privileged role should be able to perform all the functions
     * of any lower privileged role.
     */
    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");
    bytes32 public constant GUARDIAN = keccak256("GUARDIAN");
    bytes32 public constant ADMIN = keccak256("ADMIN");

    enum ExchangeType {
        UniV2,
        Bal,
        VeloSolid,
        UniV3
    }

    struct SwapStep {
        ExchangeType exType;
        address start;
        address end;
        MinAmountOutData minAmountOutData;
        address exchangeAddress; // router (vault for Bal)
    }

    SwapStep[] public swapSteps;

    /**
     * @dev Reaper contracts:
     * {vault} - Address of the vault that controls the strategy's funds.
     * {swapper} - Address of the master swapper external contract.
     */
    address public vault;
    ISwapper public swapper;

    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function __ReaperBaseStrategy_init(
        address _vault,
        address _swapper,
        address _want,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers
    ) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __AccessControlEnumerable_init();

        vault = _vault;
        swapper = ISwapper(_swapper);
        want = _want;
        IERC20Upgradeable(want).safeApprove(vault, type(uint256).max);

        uint256 numStrategists = _strategists.length;
        for (uint256 i = 0; i < numStrategists; i = i.uncheckedInc()) {
            _grantRole(STRATEGIST, _strategists[i]);
        }

        require(_multisigRoles.length == 3, "Invalid number of multisig roles");
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, _multisigRoles[0]);
        _grantRole(ADMIN, _multisigRoles[1]);
        _grantRole(GUARDIAN, _multisigRoles[2]);

        for (uint256 i = 0; i < _keepers.length; i = i.uncheckedInc()) {
            _grantRole(KEEPER, _keepers[i]);
        }

        clearUpgradeCooldown();
    }

    /**
     * @dev Withdraws funds and sends them back to the vault. Can only
     *      be called by the vault. _amount must be valid and security fee
     *      is deducted up-front.
     */
    function withdraw(uint256 _amount) external override returns (uint256 loss) {
        require(msg.sender == vault, "Only vault can withdraw");

        uint256 amountFreed = 0;
        (amountFreed, loss) = _liquidatePosition(_amount);
        IERC20Upgradeable(want).safeTransfer(vault, amountFreed);
    }

    /**
     * @dev harvest() function that takes care of logging. Subcontracts should
     *      override _harvestCore() and implement their specific logic in it.
     *
     * This method returns any realized profits and/or realized losses
     * incurred, and should return the total amounts of profits/losses/debt
     * payments (in `want` tokens) for the Vault's accounting.
     *
     * `debt` will be 0 if the Strategy is not past the configured
     * allocated capital, otherwise its value will be how far past the allocation
     * the Strategy is. The Strategy's allocation is configured in the Vault.
     *
     * NOTE: `repayment` should be less than or equal to `debt`.
     *       It is okay for it to be less than `debt`, as that
     *       should only used as a guide for how much is left to pay back.
     *       Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     */
    function harvest() public override returns (int256 roi) {
        _atLeastRole(KEEPER);
        int256 availableCapital = IVault(vault).availableCapital();
        uint256 debt = 0;
        if (availableCapital < 0) {
            debt = uint256(-availableCapital);
        }

        uint256 repayment = 0;
        if (emergencyExit) {
            uint256 amountFreed = _liquidateAllPositions();
            if (amountFreed < debt) {
                roi = -int256(debt - amountFreed);
            } else if (amountFreed > debt) {
                roi = int256(amountFreed - debt);
            }

            repayment = debt;
            if (roi < 0) {
                repayment -= uint256(-roi);
            }
        } else {
            _harvestCore();

            uint256 allocated = IVault(vault).strategies(address(this)).allocated;
            uint256 totalAssets = balanceOf();
            uint256 toFree = MathUpgradeable.min(debt, totalAssets);

            if (totalAssets > allocated) {
                uint256 profit = totalAssets - allocated;
                toFree += profit;
                roi = int256(profit);
            } else if (totalAssets < allocated) {
                roi = -int256(allocated - totalAssets);
            }

            (uint256 amountFreed, uint256 loss) = _liquidatePosition(toFree);
            repayment = MathUpgradeable.min(debt, amountFreed);
            roi -= int256(loss);
        }

        debt = IVault(vault).report(roi, repayment);
        _adjustPosition(debt);

        lastHarvestTimestamp = block.timestamp;
    }

    function _harvestCore() internal virtual {
        _beforeHarvestSwapSteps();
        uint256 numSteps = swapSteps.length;
        for (uint256 i = 0; i < numSteps; i = i.uncheckedInc()) {
            SwapStep storage step = swapSteps[i];
            IERC20Upgradeable startToken = IERC20Upgradeable(step.start);
            uint256 amount = startToken.balanceOf(address(this));
            if (amount == 0) {
                continue;
            }

            startToken.safeApprove(address(swapper), 0);
            startToken.safeIncreaseAllowance(address(swapper), amount);
            if (step.exType == ExchangeType.UniV2) {
                swapper.swapUniV2(step.start, step.end, amount, step.minAmountOutData, step.exchangeAddress);
            } else if (step.exType == ExchangeType.Bal) {
                swapper.swapBal(step.start, step.end, amount, step.minAmountOutData, step.exchangeAddress);
            } else if (step.exType == ExchangeType.VeloSolid) {
                swapper.swapVelo(step.start, step.end, amount, step.minAmountOutData, step.exchangeAddress);
            } else if (step.exType == ExchangeType.UniV3) {
                swapper.swapUniV3(step.start, step.end, amount, step.minAmountOutData, step.exchangeAddress);
            }
        }
        _afterHarvestSwapSteps();
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It only takes into account funds in hand.
     */
    function balanceOfWant() public view virtual returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Function to calculate the total {want} in external contracts only.
     */
    function balanceOfPool() public view virtual returns (uint256);

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in external contracts.
     */
    function balanceOf() public view virtual override returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    /**
     * @notice
     *  Activates emergency exit. Once activated, the Strategy will exit its
     *  position upon the next harvest, depositing all funds into the Vault as
     *  quickly as is reasonable given on-chain conditions.
     *
     *  This may only be called by GUARDIAN or higher privileged roles.
     * @dev
     *  See `vault.setEmergencyShutdown()` and `harvest()` for further details.
     */
    function setEmergencyExit() external {
        _atLeastRole(GUARDIAN);
        emergencyExit = true;
        IVault(vault).revokeStrategy(address(this));
    }

    /**
     * Only {ADMIN} or higher roles may set the array
     * of swap steps executed as part of harvest.
     */
    function setHarvestSwapSteps(SwapStep[] calldata _newSteps) external {
        _atLeastRole(ADMIN);
        delete swapSteps;

        for (uint256 i = 0; i < _newSteps.length; i = i.uncheckedInc()) {
            SwapStep memory step = _newSteps[i];
            _verifySwapStep(step);
            swapSteps.push(step);
        }
    }

    function setHarvestSwapStepAtIndex(SwapStep calldata _newStep, uint256 index) external {
        _atLeastRole(ADMIN);
        require(index < swapSteps.length, "Invalid index");
        delete swapSteps[index].minAmountOutData;
        delete swapSteps[index];
        _verifySwapStep(_newStep);
        swapSteps[index] = _newStep;
    }

    function _verifySwapStep(SwapStep memory _step) internal {
        // Paths must be at least two elements long so we query the elements at index 1.
        // This is because in solidity's auto-generated view functions for mappings,
        // if the innermost item of the mapping is an array, the view function instead adds
        // a uint parameter at the end of the view function.
        if (_step.exType == ExchangeType.UniV2) {
            address pathElement = swapper.uniV2SwapPaths(_step.start, _step.end, _step.exchangeAddress, 1);
            require(pathElement != address(0), "Path for step not registered in swapper");
        } else if (_step.exType == ExchangeType.Bal) {
            bytes32 poolID = swapper.balSwapPoolIDs(_step.start, _step.end, _step.exchangeAddress);
            require(poolID != bytes32(0), "Pool ID for step not registered in swapper");
        } else if (_step.exType == ExchangeType.VeloSolid) {
            address pathElement = swapper.veloSwapPaths(_step.start, _step.end, _step.exchangeAddress, 1);
            require(pathElement != address(0), "Path for step not registered in swapper");
        } else if (_step.exType == ExchangeType.UniV3) {
            address pathElement = swapper.uniV3SwapPaths(_step.start, _step.end, _step.exchangeAddress, 1);
            require(pathElement != address(0), "Path for step not registered in swapper");
            address quoter = swapper.uniV3Quoters(_step.exchangeAddress);
            require(quoter != address(0), "Quoter for provided router not registered in swapper");
        }

        if (_step.minAmountOutData.kind == MinAmountOutKind.ChainlinkBased) {
            require(_step.minAmountOutData.absoluteOrBPSValue <= PERCENT_DIVISOR, "Invalid BPS value for minAmountOut");
            (address startTokenCLAggregator,) = swapper.aggregatorData(_step.start);
            require(startTokenCLAggregator != address(0), "Start token CL aggregator not registered");
            (address endTokenCLAggregator,) = swapper.aggregatorData(_step.end);
            require(endTokenCLAggregator != address(0), "End token CL aggregator not registered");
        }
    }

    /**
     * @dev This function must be called prior to upgrading the implementation.
     *      It's required to wait UPGRADE_TIMELOCK seconds before executing the upgrade.
     *      Strategists and roles with higher privilege can initiate this cooldown.
     */
    function initiateUpgradeCooldown() external {
        _atLeastRole(STRATEGIST);
        upgradeProposalTime = block.timestamp;
    }

    /**
     * @dev This function is called:
     *      - in initialize()
     *      - as part of a successful upgrade
     *      - manually to clear the upgrade cooldown.
     * Guardian and roles with higher privilege can clear this cooldown.
     */
    function clearUpgradeCooldown() public {
        _atLeastRole(GUARDIAN);
        upgradeProposalTime = block.timestamp + FUTURE_NEXT_PROPOSAL_TIME;
    }

    /**
     * @dev This function must be overriden simply for access control purposes.
     *      Only DEFAULT_ADMIN_ROLE can upgrade the implementation once the timelock
     *      has passed.
     */
    function _authorizeUpgrade(address) internal override {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        require(
            upgradeProposalTime + UPGRADE_TIMELOCK < block.timestamp, "Upgrade cooldown not initiated or still ongoing"
        );
        clearUpgradeCooldown();
    }

    /**
     * @dev Returns an array of all the relevant roles arranged in descending order of privilege.
     *      Subclasses should override this to specify their unique roles arranged in the correct
     *      order, for example, [SUPER-ADMIN, ADMIN, GUARDIAN, STRATEGIST].
     */
    function _cascadingAccessRoles() internal pure override returns (bytes32[] memory) {
        bytes32[] memory cascadingAccessRoles = new bytes32[](5);
        cascadingAccessRoles[0] = DEFAULT_ADMIN_ROLE;
        cascadingAccessRoles[1] = ADMIN;
        cascadingAccessRoles[2] = GUARDIAN;
        cascadingAccessRoles[3] = STRATEGIST;
        cascadingAccessRoles[4] = KEEPER;
        return cascadingAccessRoles;
    }

    /**
     * @dev Returns {true} if {_account} has been granted {_role}. Subclasses should override
     *      this to specify their unique role-checking criteria.
     */
    function _hasRole(bytes32 _role, address _account) internal view override returns (bool) {
        return hasRole(_role, _account);
    }

    /**
     * Perform any adjustments to the core position(s) of this Strategy given
     * what change the Vault made in the "investable capital" available to the
     * Strategy. Note that all "free capital" in the Strategy after the report
     * was made is available for reinvestment. Also note that this number
     * could be 0, and you should handle that scenario accordingly.
     */
    function _adjustPosition(uint256 _debt) internal virtual {
        if (emergencyExit) {
            return;
        }

        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _debt) {
            uint256 toReinvest = wantBalance - _debt;
            _deposit(toReinvest);
        }
    }

    /**
     * Liquidate up to `_amountNeeded` of `want` of this strategy's positions,
     * irregardless of slippage. Any excess will be re-invested with `_adjustPosition()`.
     * This function should return the amount of `want` tokens made available by the
     * liquidation. If there is a difference between them, `loss` indicates whether the
     * difference is due to a realized loss, or if there is some other sitution at play
     * (e.g. locked funds) where the amount made available is less than what is needed.
     *
     * NOTE: The invariant `liquidatedAmount + loss <= _amountNeeded` should always be maintained
     */
    function _liquidatePosition(uint256 _amountNeeded)
        internal
        virtual
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 wantBal = balanceOfWant();
        if (wantBal < _amountNeeded) {
            _withdraw(_amountNeeded - wantBal);
            liquidatedAmount = balanceOfWant();
        } else {
            liquidatedAmount = _amountNeeded;
        }

        if (_amountNeeded > liquidatedAmount) {
            loss = _amountNeeded - liquidatedAmount;
        }
    }

    /**
     * Liquidate everything and returns the amount that got freed.
     * This function is used during emergency exit instead of `_harvestCore()` to
     * liquidate all of the Strategy's positions back to the Vault.
     */
    function _liquidateAllPositions() internal virtual returns (uint256 amountFreed);

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever the vault has allocated more free want to this strategy that can be
     * deposited in external contracts to generate yield.
     */
    function _deposit(uint256 toReinvest) internal virtual;

    /**
     * @dev Withdraws funds from external contracts and brings them back to the strategy.
     */
    function _withdraw(uint256 _amount) internal virtual;

    /**
     * @dev Override this hook for taking actions before the harvest swap steps are executed.
     *      For example, claiming rewards.
     *
     *      If you're not using the harvest steps at all, but you still need to take certain actions
     *      as part of the harvest, you have two options:
     *      1. Override _harvestCore() and execute your actions inside of it
     *      2. Override one of _beforeHarvestSwapSteps() or _afterHarvestSwapSteps() and ensure
     *         no steps are registered in this strategy.
     *
     */
    function _beforeHarvestSwapSteps() internal virtual {}

    /**
     * @dev Override this hook for taking actions after the harvest swap steps are executed.
     *      For example, adding liquidity, or anything else that cannot be accomplished with a dex swap.
     */
    function _afterHarvestSwapSteps() internal virtual {}
}

