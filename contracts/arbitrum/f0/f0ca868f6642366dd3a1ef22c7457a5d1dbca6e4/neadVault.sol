// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControlEnumerable.sol";
import "./IERC20.sol";

import "./IStrategy.sol";
import "./ERC20.sol";

/// @title Ennead single strategy vault
/// @notice Not intended to be deployed from a factory
/// @dev Limitation: Most interactions would reset withdraw fee for a users entire balance

contract neadVaultSingle is ERC20, AccessControlEnumerable {
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    address public constant asset = 0x40301951Af3f80b8C1744ca77E55111dd3c1dba1;
    address public strategy;

    uint public withdrawFeeDuration;
    uint public withdrawFee;
    uint constant basis = 1000;

    mapping(address => uint) lockTime;

    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);
    event StrategyMigrated(address indexed newStrategy);

    constructor(
        address _admin,
        address _setter,
        address _timelock,
        address _strategy
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SETTER_ROLE, _setter);
        _grantRole(TIMELOCK_ROLE, _timelock);
        _setRoleAdmin(TIMELOCK_ROLE, TIMELOCK_ROLE);

        strategy = _strategy;
        IStrategy(_strategy).initialize(address(this));

        string memory __symbol = ERC20(asset).symbol();
        string memory _name = string(
            abi.encodePacked("Ennead ", __symbol, " Compounder")
        );
        string memory _symbol = string(abi.encodePacked("neadAC-", __symbol));
        name = _name;
        symbol = _symbol;
        withdrawFee = 999; // 0.1% fee
        withdrawFeeDuration = 86400; // initial 24 hours
    }

    function deposit(uint amount) public {
        require(amount > 0, "Can't deposit 0!");

        uint _totalSupply = totalSupply;
        uint shares = _totalSupply == 0
            ? amount
            : (amount * _totalSupply) / totalAssets();

        _mint(msg.sender, shares);
        IERC20(asset).transferFrom(msg.sender, strategy, amount);
        IStrategy(strategy).registerStake(amount);

        lockTime[msg.sender] = block.timestamp + withdrawFeeDuration;
        emit Deposit(msg.sender, amount);
    }

    function depositAll() external {
        uint bal = IERC20(asset).balanceOf(msg.sender);
        deposit(bal);
    }

    /// @notice withdraw takes vault shares instead of assets
    function withdraw(uint shares) public {
        require(shares > 0, "Can't withdraw 0!");

        uint amount = (shares * totalAssets()) / totalSupply;
        if (block.timestamp < lockTime[msg.sender]) {
            if (shares != totalSupply) {
                amount = (amount * withdrawFee) / basis;
            } // if shares == totalSupply withdraw all assets
        } // no need to reset to 0 after

        _burn(msg.sender, shares);

        IStrategy(strategy).unregisterStake(amount);
        IERC20(asset).transferFrom(strategy, msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function withdrawAll() external {
        uint bal = balanceOf[msg.sender];
        withdraw(bal);
    }

    function quotePricePerShare() external view returns (uint amount) {
        uint one = 1e18;
        amount = totalSupply == 0 ? one : (one * totalAssets()) / totalSupply;
    }

    /// @notice quotes how much `assets` can be redeemed for `shares`
    function quoteAssets(uint shares) external view returns (uint assets) {
        assets = (shares * totalAssets()) / totalSupply;
    }

    function totalAssets() public view returns (uint assets) {
        assets = IStrategy(strategy).getTotalStaked();
    }

    /// @notice sets duration withdraw fee will remain active after an interaction
    function setDuration(uint duration) external onlyRole(SETTER_ROLE) {
        withdrawFeeDuration = duration;
    }

    /// @notice sets the withdraw fee
    function setWithdrawFee(uint fee) external onlyRole(SETTER_ROLE) {
        require(fee >= 900, "Too high!");
        withdrawFee = fee;
    }

    // not expecting to change the strategy in the lifetime of the vault but keeping in case.

    /// @notice retires current strategy and migrates to a new one
    function migrateStrategy(
        address _strategy
    ) external onlyRole(TIMELOCK_ROLE) {
        uint assets = IStrategy(strategy).getTotalStaked();
        // do one last reinvest, try catch in case.
        try IStrategy(strategy).reinvest(address(this)) {} catch {}
        IStrategy(strategy).unregisterStake(assets);
        IERC20(asset).transferFrom(strategy, address(this), assets);
        strategy = _strategy;

        uint bal = IERC20(asset).balanceOf(address(this));
        IERC20(asset).transfer(strategy, bal);
        IStrategy(_strategy).registerStake(bal);
    }

    /// @notice each transfer will reactivate withdraw fee
    function beforeTokenTransfer(address, address to) internal override {
        lockTime[to] = block.timestamp + withdrawFeeDuration;
    }
}

