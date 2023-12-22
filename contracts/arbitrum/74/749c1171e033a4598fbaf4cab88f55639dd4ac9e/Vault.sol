// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./AccessControlUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./IVault.sol";

contract Vault is
    AccessControlUpgradeable,
    ERC20Upgradeable,
    UUPSUpgradeable,
    IVault
{
    using SafeERC20 for IERC20;

    event FeePctSet(uint256 depositFeePct, uint256 withdrawFeePct);

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 constant DENOMINATOR = 1e6;
    uint256 constant INVEST_PCT = 9e5;

    IERC20 public override underlying;
    IStrategy public override strategy;
    address public override treasury;
    uint256 public minimumMovement;
    uint256 public depositFeePct;
    uint256 public withdrawFeePct;

    function initialize(
        IERC20 _underlying,
        address _treasury,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __AccessControl_init();
        __ERC20_init(_name, _symbol);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        underlying = _underlying;
        treasury = _treasury;
    }

    function deposit(uint256 amount, address beneficiary) external override {
        uint256 _amount = amount;
        require(_amount != 0, "zero");

        address _beneficiary = beneficiary == address(0)
            ? msg.sender
            : beneficiary;

        uint256 _totalBalance = totalBalance();
        uint256 _totalSupply = totalSupply();

        underlying.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 fee = _deductFee(_amount, true);
        _amount -= fee;

        uint256 share;
        if (_totalBalance == 0 || _totalSupply == 0) {
            share = _amount;
        } else {
            share = (_totalSupply * _amount) / _totalBalance;
        }

        _mint(_beneficiary, share);

        emit Deposited(msg.sender, _beneficiary, _amount, share, fee);
    }

    function withdraw(uint256 share, address beneficiary) external override {
        uint256 _share = share;
        require(_share != 0, "zero");

        address _beneficiary = beneficiary == address(0)
            ? msg.sender
            : beneficiary;

        uint256 _totalBalance = totalBalance();
        uint256 _totalSupply = totalSupply();

        uint256 amount = (_share * _totalBalance) / _totalSupply;

        uint256 _balanceInVault = _vaultBalance();

        if (amount > _balanceInVault) {
            uint256 withdrawFromStrategy = amount - _balanceInVault;

            uint256 actualWithdrawn = strategy.withdraw(withdrawFromStrategy);
            amount = _balanceInVault + actualWithdrawn;
        }

        uint256 fee = _deductFee(amount, false);
        amount -= fee;

        _burn(msg.sender, _share);
        underlying.safeTransfer(_beneficiary, amount);

        emit Withdrawn(msg.sender, _beneficiary, amount, _share, fee);
    }

    function rebalance(bool onlyInvest)
        external
        override
        onlyRole(OPERATOR_ROLE)
    {
        uint256 remainBal = _vaultBalance();
        uint256 investedBal = strategy.totalAssets();
        uint256 _total = remainBal + investedBal;

        uint256 _expectedInvest = (_total * INVEST_PCT) / DENOMINATOR;

        if (_expectedInvest < investedBal) {
            require(!onlyInvest, "only invest");

            uint256 amount = investedBal - _expectedInvest;
            require(amount >= minimumMovement, "Too small");
            uint256 actualWithdrawn = strategy.withdraw(amount);

            emit Rebalanced(address(strategy), int256(actualWithdrawn) * -1);
        } else {
            uint256 amount = _expectedInvest - investedBal;

            require(amount >= minimumMovement, "Too small");
            underlying.safeTransfer(address(strategy), amount);
            strategy.invest();

            emit Rebalanced(address(strategy), int256(amount));
        }
    }

    function setStrategy(IStrategy _strategy)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            address(strategy) == address(0) || strategy.totalAssets() == 0,
            "not empty"
        );
        require(
            address(_strategy.vault()) == address(this),
            "invalid strategy"
        );

        strategy = _strategy;

        emit StrategySet(address(_strategy));
    }

    function setTreasury(address _treasury)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_treasury != address(0), "zero addr");

        treasury = _treasury;

        emit TreasurySet(_treasury);
    }

    function setFeePct(uint256 _depositFeePct, uint256 _withdrawFeePct)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            _depositFeePct < DENOMINATOR / 2 &&
                _withdrawFeePct < DENOMINATOR / 2,
            "too big"
        );

        depositFeePct = _depositFeePct;
        withdrawFeePct = _withdrawFeePct;

        emit FeePctSet(_depositFeePct, _withdrawFeePct);
    }

    function totalBalance() public view override returns (uint256) {
        return _vaultBalance() + strategy.totalAssets();
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(address(underlying)).decimals();
    }

    function _vaultBalance() internal view returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function _deductFee(uint256 amount, bool isDeposit)
        internal
        returns (uint256 fee)
    {
        uint256 feePct = isDeposit ? depositFeePct : withdrawFeePct;

        if (feePct != 0) {
            fee = (amount * feePct) / DENOMINATOR;
            underlying.safeTransfer(treasury, fee);
        }
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}
}

