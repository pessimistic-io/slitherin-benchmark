pragma solidity ^0.5.16;

import "./Math.sol";
import "./SafeMath.sol";
import "./ERC20.sol";
import "./ERC20Detailed.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./IStrategy.sol";
import "./IVault.sol";
import "./IController.sol";
import "./IUpgradeSource.sol";
import "./ControllableInit.sol";
import "./VaultStorage.sol";


contract VaultV1 is IVault, ERC20, ERC20Detailed, IUpgradeSource, ControllableInit, VaultStorage {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * Caller has exchanged assets for shares, and transferred those shares to owner.
     *
     * MUST be emitted when tokens are deposited into the Vault via the mint and deposit methods.
     */
    event Deposit(
        address indexed sender,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    /**
     * Caller has exchanged shares, owned by owner, for assets, and transferred those assets to receiver.
     *
     * MUST be emitted when shares are withdrawn from the Vault in ERC4626.redeem or ERC4626.withdraw methods.
     */
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Invest(uint256 amount);

    event VaultAnnounced(address newVault, uint256 availableAtTimestamp);
    event VaultChanged(address newVault);

    event StrategyAnnounced(address newStrategy, uint256 availableAtTimestamp);
    event StrategyChanged(address newStrategy);

    modifier whenStrategyDefined() {
        require(address(strategy()) != address(0), "Strategy must be defined");
        _;
    }

    modifier defense() {
        require(
            (msg.sender == tx.origin) || // If it is a normal user and not smart contract,
            // then the requirement will pass
            !IController(controller()).greyList(msg.sender), // If it is a smart contract, then
            "This smart contract has been grey listed"  // make sure that it is not on our greyList.
        );
        _;
    }

    constructor() public {
    }

    /**
     * The function is name differently to not cause inheritance clash in truffle and allows tests
     */
    function initializeVault(
        address _storage,
        address _underlying,
        uint256 _toInvestNumerator,
        uint256 _toInvestDenominator
    ) public initializer {
        require(_toInvestNumerator <= _toInvestDenominator, "cannot invest more than 100%");
        require(_toInvestDenominator != 0, "cannot divide by 0");

        ERC20Detailed.initialize(
            string(abi.encodePacked("FARM_", ERC20Detailed(_underlying).symbol())),
            string(abi.encodePacked("f", ERC20Detailed(_underlying).symbol())),
            ERC20Detailed(_underlying).decimals()
        );
        ControllableInit.initialize(_storage);

        uint256 underlyingUnit = 10 ** uint256(ERC20Detailed(address(_underlying)).decimals());
        VaultStorage.initialize(
            _underlying,
            _toInvestNumerator,
            _toInvestDenominator,
            underlyingUnit
        );
    }

    function strategy() public view returns (address) {
        return _strategy();
    }

    function underlying() public view returns (address) {
        return _underlying();
    }

    function underlyingUnit() public view returns (uint256) {
        return _underlyingUnit();
    }

    function vaultFractionToInvestNumerator() public view returns (uint256) {
        return _vaultFractionToInvestNumerator();
    }

    function vaultFractionToInvestDenominator() public view returns (uint256) {
        return _vaultFractionToInvestDenominator();
    }

    function nextImplementation() public view returns (address) {
        return _nextImplementation();
    }

    function nextImplementationTimestamp() public view returns (uint256) {
        return _nextImplementationTimestamp();
    }

    function nextImplementationDelay() public view returns (uint256) {
        return IController(controller()).nextImplementationDelay();
    }

    /**
     * Chooses the best strategy and re-invests. If the strategy did not change, it just calls doHardWork on the current
     * strategy. Call this through controller to claim hard rewards.
     */
    function doHardWork() whenStrategyDefined onlyControllerOrGovernance external {
        // ensure that new funds are invested too
        _invest();
        IStrategy(strategy()).doHardWork();
    }

    /**
     * @return The balance across all users in this contract.
     */
    function underlyingBalanceInVault() public view returns (uint256) {
        return IERC20(underlying()).balanceOf(address(this));
    }

    /**
     * @return  The current underlying (e.g., DAI's) balance together with the invested amount (if DAI is invested
     *          elsewhere by the strategy).
     */
    function underlyingBalanceWithInvestment() public view returns (uint256) {
        if (address(strategy()) == address(0)) {
            // initial state, when not set
            return underlyingBalanceInVault();
        }
        return underlyingBalanceInVault().add(IStrategy(strategy()).investedUnderlyingBalance());
    }

    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0
        ? underlyingUnit()
        : underlyingUnit().mul(underlyingBalanceWithInvestment()).div(totalSupply());
    }

    /**
     * @return The user's total balance in underlying
     */
    function underlyingBalanceWithInvestmentForHolder(address _holder) view external returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return underlyingBalanceWithInvestment().mul(balanceOf(_holder)).div(totalSupply());
    }

    function nextStrategy() public view returns (address) {
        return _nextStrategy();
    }

    function nextStrategyTimestamp() public view returns (uint256) {
        return _nextStrategyTimestamp();
    }

    function canUpdateStrategy(address _strategy) public view returns (bool) {
        bool isStrategyNotSetYet = strategy() == address(0);
        bool hasTimelockPassed = block.timestamp > nextStrategyTimestamp() && nextStrategyTimestamp() != 0;
        return isStrategyNotSetYet || (_strategy == nextStrategy() && hasTimelockPassed);
    }

    /**
     * Indicates that the strategy update will happen in the future
     */
    function announceStrategyUpdate(address _strategy) public onlyControllerOrGovernance {
        // records a new timestamp
        uint256 when = block.timestamp.add(IController(controller()).nextImplementationDelay());
        _setNextStrategyTimestamp(when);
        _setNextStrategy(_strategy);
        emit StrategyAnnounced(_strategy, when);
    }

    /**
     * Finalizes (or cancels) the strategy update by resetting the data
     */
    function finalizeStrategyUpdate() public onlyControllerOrGovernance {
        _setNextStrategyTimestamp(0);
        _setNextStrategy(address(0));
    }

    function setStrategy(address _strategy) public onlyControllerOrGovernance {
        require(
            canUpdateStrategy(_strategy),
            "The strategy exists or the time lock did not elapse yet"
        );
        require(
            _strategy != address(0),
            "New strategy cannot be empty"
        );
        require(
            IStrategy(_strategy).underlying() == address(underlying()),
            "Vault underlying must match Strategy underlying"
        );
        require(
            IStrategy(_strategy).vault() == address(this),
            "The strategy does not belong to this vault"
        );

        emit StrategyChanged(_strategy);
        if (address(_strategy) != address(strategy())) {
            if (address(strategy()) != address(0)) {
                // if the original strategy (no underscore) is defined, remove the token approval and withdraw all
                IERC20(underlying()).safeApprove(address(strategy()), 0);
                IStrategy(strategy()).withdrawAllToVault();
            }
            _setStrategy(_strategy);
            IERC20(underlying()).safeApprove(address(strategy()), 0);
            IERC20(underlying()).safeApprove(address(strategy()), uint256(-1));
        }
        finalizeStrategyUpdate();
    }

    function setVaultFractionToInvest(uint256 _numerator, uint256 _denominator) external onlyGovernance {
        require(_denominator > 0, "denominator must be greater than 0");
        require(_numerator <= _denominator, "denominator must be greater than or equal to the numerator");
        _setVaultFractionToInvestNumerator(_numerator);
        _setVaultFractionToInvestDenominator(_denominator);
    }

    function rebalance() external onlyControllerOrGovernance {
        withdrawAll();
        _invest();
    }

    function availableToInvestOut() public view returns (uint256) {
        uint256 wantInvestInTotal = underlyingBalanceWithInvestment()
            .mul(vaultFractionToInvestNumerator())
            .div(vaultFractionToInvestDenominator());
        uint256 alreadyInvested = IStrategy(strategy()).investedUnderlyingBalance();
        if (alreadyInvested >= wantInvestInTotal) {
            return 0;
        } else {
            uint256 remainingToInvest = wantInvestInTotal.sub(alreadyInvested);
            return remainingToInvest <= underlyingBalanceInVault() ? remainingToInvest : underlyingBalanceInVault();
        }
    }

    /**
     * Allows for depositing the underlying asset in exchange for shares. Approval is assumed.
     */
    function deposit(uint256 _assets) external nonReentrant defense {
        _deposit(_assets, msg.sender, msg.sender);
    }

    /**
     * Allows for depositing the underlying asset in exchange for shares assigned to the holder. This facilitates
     * depositing for someone else (using DepositHelper)
     */
    function depositFor(uint256 _assets, address _receiver) external nonReentrant defense {
        _deposit(_assets, msg.sender, _receiver);
    }

    function withdraw(uint256 _shares) external nonReentrant defense {
        _withdraw(_shares, msg.sender, msg.sender);
    }

    function withdrawAll() public onlyControllerOrGovernance whenStrategyDefined {
        IStrategy(strategy()).withdrawAllToVault();
    }

    /**
     * Schedules an upgrade for this vault's proxy.
     */
    function scheduleUpgrade(address _impl) public onlyGovernance {
        uint when = block.timestamp.add(nextImplementationDelay());
        _setNextImplementation(_impl);
        _setNextImplementationTimestamp(when);
        emit VaultAnnounced(_impl, when);
    }

    function shouldUpgrade() external view returns (bool, address) {
        return (
            nextImplementationTimestamp() != 0
            && block.timestamp > nextImplementationTimestamp()
            && nextImplementation() != address(0),
            nextImplementation()
        );
    }

    function finalizeUpgrade() external onlyGovernance {
        _setNextImplementation(address(0));
        _setNextImplementationTimestamp(0);
        emit VaultChanged(_implementation());
    }

    // ========================= Internal Functions =========================

    /**
     * @dev Transfers any available assets to the strategy
     */
    function _invest() internal whenStrategyDefined {
        uint256 availableAmount = availableToInvestOut();
        if (availableAmount > 0) {
            IERC20(underlying()).safeTransfer(address(strategy()), availableAmount);
            emit Invest(availableAmount);
        }
    }

    function _deposit(
        uint256 _assets,
        address _sender,
        address _receiver
    ) internal returns (uint256, uint256) {
        require(_assets > 0, "Cannot deposit 0");
        require(_receiver != address(0), "receiver must be defined");

        if (address(strategy()) != address(0)) {
            require(IStrategy(strategy()).depositArbCheck(), "Too much arb");
        }

        uint256 shares = totalSupply() == 0
            ? _assets
            : _assets.mul(totalSupply()).div(underlyingBalanceWithInvestment());

        _mint(_receiver, shares);

        _transferUnderlyingIn(_sender, _assets);

        // update the contribution amount for the beneficiary
        emit Deposit(_sender, _receiver, _assets, shares);

        return (_assets, shares);
    }

    function _withdraw(
        uint256 _shares,
        address _receiver,
        address _owner
    ) internal returns (uint256 assets) {
        require(totalSupply() > 0, "Vault has no shares");
        require(_shares > 0, "numberOfShares must be greater than 0");
        uint256 totalShareSupply = totalSupply();
        uint256 calculatedSharePrice = getPricePerFullShare();

        address sender = msg.sender;
        if (sender != _owner) {
            uint256 currentAllowance = allowance(_owner, sender);
            if (currentAllowance != uint(-1)) {
                require(currentAllowance >= _shares, "ERC20: transfer amount exceeds allowance");
                _approve(_owner, sender, currentAllowance - _shares);
            }
        }

        // !!! IMPORTANT: burning shares needs to happen after the last use of getPricePerFullShare()
        _burn(_owner, _shares);

        assets = _shares.mul(calculatedSharePrice).div(underlyingUnit());

        if (assets > underlyingBalanceInVault()) {
            uint256 missing = assets.sub(underlyingBalanceInVault());
            IStrategy(strategy()).withdrawToVault(missing);

            // recalculate to improve accuracy (in case of truncation or rounding issues upon withdrawing)
            assets = Math.min(
                _shares.mul(underlyingBalanceWithInvestment()).div(totalShareSupply),
                underlyingBalanceInVault()
            );
        }

        _transferUnderlyingOut(_receiver, assets);

        // update the withdrawal amount for the holder
        emit Withdraw(msg.sender, _receiver, _owner, assets, _shares);
    }

    function _transferUnderlyingIn(address _sender, uint _amount) internal {
        IERC20(underlying()).safeTransferFrom(_sender, address(this), _amount);
    }

    function _transferUnderlyingOut(address _receiver, uint _amount) internal {
        IERC20(underlying()).safeTransfer(_receiver, _amount);
    }
}

