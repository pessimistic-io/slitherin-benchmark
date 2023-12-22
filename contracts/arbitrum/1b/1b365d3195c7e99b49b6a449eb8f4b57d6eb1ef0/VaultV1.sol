// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC4626 } from "./IERC4626.sol";
import { Pausable } from "./Pausable.sol";
import { AccessControl } from "./AccessControl.sol";
import { IStrategyConfig } from "./IStrategyConfig.sol";

struct StrategyParams {
    address operator;
    uint256 debtRatio;
    uint256 totalDebt;
    bool activation;
    int256 netDeposits;
}

contract VaultV1 is IERC4626, Pausable, ReentrancyGuard, AccessControl {
    event AddStrategy(
        address indexed strategy,
        address indexed operator,
        uint256 debtRatio,
        uint256 totalDebtRatio
    );

    event RevokeStrategy(address indexed caller, address indexed strategy, uint256 totalDebtRatio);

    bytes32 public constant CLIENT_ROLE = bytes32(uint256(1));

    IERC20 private immutable _underlyingToken;

    uint256 private _totalShares;

    mapping(address => uint256) private _shares;

    address[] public withdrawalQueue;

    uint256 public withdrawalQueueLength;

    mapping(address => StrategyParams) public strategies;

    uint256 public totalDebtRatio;

    uint256 public totalDebt;

    string private _name;

    int256 public netDeposits;

    constructor(
        string memory vaultName,
        IERC20 underlyingToken,
        address adminAddress
    ) Pausable() ReentrancyGuard() {
        _underlyingToken = underlyingToken;
        _name = vaultName;
        _setupRole(DEFAULT_ADMIN_ROLE, adminAddress);
    }

    modifier onlyWhitelisted() {
        require(
            hasRole(CLIENT_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "VaultV1: Not whitelisted"
        );
        _;
    }

    modifier onlyOperator(address strategy) {
        require(
            strategies[strategy].operator == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "VaultV1: Not strategy operator"
        );
        _;
    }

    function exchangeRate() public view returns (uint256) {
        if (_totalShares == 0) return 1e18;
        else return (_vaultBalance() * 1e18) / _totalShares;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalShares;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _shares[account];
    }

    function assetsOf(address account) external view returns (uint256) {
        return (_shares[account] * exchangeRate()) / 1e18;
    }

    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }

    function allowance(address, address) external pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        return false;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _name;
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function asset() external view override returns (address) {
        return address(_underlyingToken);
    }

    function totalAssets() external view override returns (uint256) {
        return _vaultBalance();
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        if (_totalShares == 0) return assets;
        else return (assets * _totalShares) / _vaultBalance();
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (_totalShares == 0) return shares;
        else return (shares * _vaultBalance()) / _totalShares;
    }

    /// @dev no max deposit limit currently.
    function maxDeposit(address) public pure override returns (uint256) {
        return 2 ** 256 - 1;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    /// @dev second param not necessary, but implemented for IERC4626.
    /// @dev nonReentrant because the only use of the function is as a descreet deposit.
    function deposit(
        uint256 assets,
        address
    ) public onlyWhitelisted nonReentrant returns (uint256 shares) {
        shares = convertToShares(assets);
        _deposit(shares, assets, msg.sender);
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        return deposit(assets, address(0));
    }

    /// @dev no max mint limit currently.
    function maxMint(address) external pure returns (uint256) {
        return 2 ** 256 - 1;
    }

    /// @dev doubles another method, but implemented for IERC4626.
    function previewMint(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    /// @dev second param not necessary, but implemented for IERC4626.
    /// @dev nonReentrant because the only use of the function is as a descreet deposit.
    function mint(
        uint256 shares,
        address
    ) public onlyWhitelisted nonReentrant returns (uint256 assets) {
        assets = convertToAssets(shares);
        _deposit(shares, assets, msg.sender);
    }

    function mint(uint256 shares) external returns (uint256 assets) {
        return mint(shares, address(0));
    }

    function _deposit(uint256 shares, uint256 assets, address receiver) internal {
        _totalShares += shares;
        _shares[receiver] += shares;

        uint256 underlyingBalance = _underlyingToken.balanceOf(address(this));
        _underlyingToken.transferFrom(msg.sender, address(this), assets);
        underlyingBalance = _underlyingToken.balanceOf(address(this)) - underlyingBalance;

        require(underlyingBalance == assets, "VaultV1: Incoherent transfer amount");

        netDeposits += int256(underlyingBalance);

        emit Deposit(receiver, msg.sender, assets, shares);
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(_shares[owner]);
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    /// @dev nonReentrant because the only use of the function is as a descreet deposit.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 shares) {
        if (assets == 0) shares = _shares[owner];
        else shares = convertToShares(assets);
        _redeem(shares, receiver, owner);
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return _shares[owner];
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    /// @dev nonReentrant because the only use of the function is as a descreet deposit.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256) {
        if (shares == 0) shares = _shares[owner];
        return _redeem(shares, receiver, owner);
    }

    function _redeem(
        uint256 shares,
        address receiver,
        address owner
    ) internal returns (uint256 assets) {
        require(shares <= _shares[owner], "VaultV1: Not enough shares");
        require(shares > 0, "VaultV1: Not withdrawing anything");

        assets = convertToAssets(shares);

        uint256 vaultBalance = _underlyingToken.balanceOf(address(this));

        if (assets > vaultBalance) {
            for (uint256 i = 0; i < withdrawalQueue.length; i++) {
                uint256 amountNeeded = assets - vaultBalance;

                if (amountNeeded == 0) break;

                _repay(withdrawalQueue[i], amountNeeded);

                vaultBalance = _underlyingToken.balanceOf(address(this));
            }
        }

        _underlyingToken.transfer(receiver, assets);

        // implicily trust that transfer amount is coherent

        _totalShares -= shares;
        _shares[owner] -= shares;

        netDeposits -= int256(assets);

        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);
    }

    /// @notice allows to add AND edit existing strategies.
    function addStrategy(
        address strategy,
        address operator,
        uint256 debtRatio
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        totalDebtRatio -= strategies[strategy].debtRatio;
        strategies[strategy] = StrategyParams({
            operator: operator,
            debtRatio: debtRatio,
            totalDebt: strategies[strategy].totalDebt,
            activation: true,
            netDeposits: 0
        });
        totalDebtRatio += debtRatio;

        emit AddStrategy(strategy, operator, debtRatio, totalDebtRatio);
    }

    function revokeStrategy(address strategy) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        _revokeStrategy(strategy);
    }

    function _revokeStrategy(address strategy) internal {
        require(strategies[strategy].activation, "VaultV1: Strategy not activated");

        _repay(strategy, 0);

        StrategyParams memory selectedStrategy = strategies[strategy];
        totalDebtRatio -= selectedStrategy.debtRatio;
        delete selectedStrategy.debtRatio;
        delete selectedStrategy.activation;
        strategies[strategy] = selectedStrategy;

        emit RevokeStrategy(msg.sender, strategy, totalDebtRatio);
    }

    function setWithdrawalQueue(address[] calldata queue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        /// check activation
        for (uint256 i = 0; i < queue.length; i++) {
            require(strategies[address(queue[i])].activation, "VaultV1: Strategy not activated");
        }

        /// prevent disconnecting strategies with remaining funds
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            bool found = false;
            address withdrawalStrategy = withdrawalQueue[i];
            for (uint256 j = 0; j < queue.length; j++) {
                if (withdrawalStrategy == queue[j]) {
                    found = true;
                    break;
                }
            }
            if (found == false) {
                _revokeStrategy(withdrawalStrategy);
            }
        }

        withdrawalQueue = queue;
        withdrawalQueueLength = queue.length;
    }

    function creditAvailable(address strategy) public view returns (uint256) {
        if (totalDebtRatio == 0) return 0;
        StrategyParams memory strat = strategies[strategy];
        uint256 creditPlus = ((_vaultBalance() * strat.debtRatio) / totalDebtRatio);
        uint256 creditMinus = strat.totalDebt;
        if (creditPlus > creditMinus) return creditPlus - creditMinus;
        else return 0;
    }

    function totalCreditAvailable() external view returns (uint256) {
        if (totalDebtRatio == 0) return 0;
        (uint256 creditPlus, uint256 creditMinus) = (_vaultBalance(), totalDebt);
        if (creditPlus > creditMinus) return creditPlus - creditMinus;
        else return 0;
    }

    function borrow(
        address strategy,
        uint256 underlyingBorrowAmount
    ) external whenNotPaused onlyOperator(strategy) {
        uint256 borrowAvailable = creditAvailable(strategy);

        underlyingBorrowAmount = underlyingBorrowAmount > borrowAvailable ||
            underlyingBorrowAmount == 0
            ? borrowAvailable
            : underlyingBorrowAmount;

        uint256 underlyingBalance = _underlyingToken.balanceOf(address(this));

        underlyingBorrowAmount = underlyingBorrowAmount > underlyingBalance
            ? underlyingBalance
            : underlyingBorrowAmount;

        strategies[strategy].netDeposits += int256(underlyingBorrowAmount);
        strategies[strategy].totalDebt += underlyingBorrowAmount;
        totalDebt += underlyingBorrowAmount;

        _underlyingToken.transfer(strategy, underlyingBorrowAmount);
    }

    /// @param underlyingRepayAmount if set to zero and debt exceeding credit, changes to difference between debt and credit available.
    function repay(
        address strategy,
        uint256 underlyingRepayAmount
    ) external onlyOperator(strategy) {
        StrategyParams memory strat = strategies[strategy];
        require(strat.activation, "VaultV1: Strategy not activated");

        underlyingRepayAmount = underlyingRepayAmount == 0 &&
            strat.totalDebt > creditAvailable(strategy)
            ? strat.totalDebt - creditAvailable(strategy)
            : underlyingRepayAmount;

        _repay(strategy, underlyingRepayAmount);
    }

    function _repay(address strategy, uint256 repayAmount) internal {
        IStrategyConfig withdrawalStrat = IStrategyConfig(strategy);

        uint256 strategyBalance = withdrawalStrat.strategyBalance();

        repayAmount = repayAmount > strategyBalance || repayAmount == 0
            ? strategyBalance
            : repayAmount;

        uint256 withdrawalAmount = _underlyingToken.balanceOf(address(this));

        StrategyParams memory strat = strategies[strategy];

        withdrawalStrat.withdraw(repayAmount);
        withdrawalAmount = _underlyingToken.balanceOf(address(this)) - withdrawalAmount;

        strat.netDeposits -= int256(withdrawalAmount);

        withdrawalAmount = withdrawalAmount > strat.totalDebt ? strat.totalDebt : withdrawalAmount;
        strat.totalDebt -= withdrawalAmount;
        totalDebt -= withdrawalAmount;

        strategies[strategy] = strat;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            _repay(withdrawalQueue[i], 0);
            totalDebtRatio -= strategies[withdrawalQueue[i]].debtRatio;
            strategies[withdrawalQueue[i]].debtRatio = 0;
        }
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _vaultBalance() internal view returns (uint256 totalSize) {
        totalSize = _underlyingToken.balanceOf(address(this));
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            totalSize += IStrategyConfig(withdrawalQueue[i]).strategyBalance();
        }
    }
}

