// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./Counters.sol";

import "./ERC20.sol";
import "./ERC4626.sol";
import "./SafeTransferLib.sol";

/**
 * @title   DSquared Investment Vault V0
 * @dev     Does not support rebasing or transfer fee tokens.
 * @author  @BowTiedPickle
 */
contract VaultV0 is ERC4626, Ownable {
    using Counters for Counters.Counter;
    using SafeTransferLib for ERC20;

    // ----- Events -----

    event EpochStarted(uint256 indexed epoch, uint256 fundingStart, uint256 epochStart, uint256 epochEnd);
    event FundsCustodied(uint256 indexed epoch, uint256 amount);
    event FundsReturned(uint256 indexed epoch, uint256 amount);
    event NewMaxDeposits(uint256 oldMax, uint256 newMax);
    event NewWhitelistStatus(address indexed user, bool status);

    // ----- State Variables -----

    uint256 public constant MAX_EPOCH_DURATION = 30 days;
    uint256 public constant MIN_FUNDING_DURATION = 2 days;

    struct Epoch {
        uint256 fundingStart;
        uint256 epochStart;
        uint256 epochEnd;
    }

    mapping(uint256 => Epoch) public epochs;
    Counters.Counter internal epochId;

    /// @notice Whether the epoch has been started
    bool public started;

    /// @notice Whether funds are currently out with the custodian
    bool public custodied;

    /// @notice Amount of funds sent to custodian
    uint256 public custodiedAmount;

    /// @notice Address which can take custody of funds to execute strategies during an epoch
    address public immutable trader;

    /// @notice Maximum allowable deposits to the vault
    uint256 public maxDeposits;

    /// @notice Current deposits
    uint256 public totalDeposits;

    /// @notice Mapping of users to whether they are whitelisted to deposit into the vault
    mapping(address => bool) public whitelisted;

    // ----- Modifiers -----

    modifier onlyTrader() {
        require(msg.sender == trader, "!trader");
        _;
    }

    modifier notCustodied() {
        require(!custodied, "custodied");
        _;
    }

    modifier duringFunding() {
        Epoch storage epoch = epochs[epochId.current()];
        require(block.timestamp >= epoch.fundingStart && block.timestamp < epoch.epochStart, "!funding");
        _;
    }

    modifier notDuringEpoch() {
        Epoch storage epoch = epochs[epochId.current()];
        require(block.timestamp < epoch.epochStart || block.timestamp >= epoch.epochEnd, "during");
        _;
    }

    modifier duringEpoch() {
        Epoch storage epoch = epochs[epochId.current()];
        require(block.timestamp >= epoch.epochStart && block.timestamp < epoch.epochEnd, "!during");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelisted[msg.sender], "!whitelisted");
        _;
    }

    // ----- Construction -----

    /**
     * @param   _asset          Underlying asset of the vault
     * @param   _name           Vault name
     * @param   _symbol         Vault symbol
     * @param   _trader         Trader address
     * @param   _maxDeposits    Initial maximum deposits allowed
     */
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _trader,
        uint256 _maxDeposits
    ) ERC4626(_asset, _name, _symbol) {
        require(_trader != address(0), "!zeroAddr");
        trader = _trader;
        maxDeposits = _maxDeposits;
    }

    // ----- Admin Functions -----

    /**
     * @notice  Start a new epoch and set its time parameters
     * @param   _fundingStart Start timestamp of the funding phase in unix epoch seconds
     * @param   _epochStart   Start timestamp of the epoch in unix epoch seconds
     * @param   _epochEnd     End timestamp of the epoch in unix epoch seconds
     */
    function startEpoch(
        uint256 _fundingStart,
        uint256 _epochStart,
        uint256 _epochEnd
    ) external onlyOwner notDuringEpoch {
        require(!started || !custodied, "!allowed");
        require(
            _epochEnd > _epochStart && _epochStart >= _fundingStart + MIN_FUNDING_DURATION && _fundingStart >= block.timestamp,
            "!timing"
        );
        require(_epochEnd <= _epochStart + MAX_EPOCH_DURATION, "!epochLen");

        epochId.increment();
        uint256 currentEpoch = getCurrentEpoch();
        Epoch storage epoch = epochs[currentEpoch];

        epoch.fundingStart = _fundingStart;
        epoch.epochStart = _epochStart;
        epoch.epochEnd = _epochEnd;

        started = true;

        emit EpochStarted(currentEpoch, _fundingStart, _epochStart, _epochEnd);
    }

    /**
     * @notice  Set new maximum deposit limit
     * @param   _newMax New maximum deposit limit
     */
    function setMaxDeposits(uint256 _newMax) external onlyOwner {
        emit NewMaxDeposits(maxDeposits, _newMax);
        maxDeposits = _newMax;
    }

    /**
     * @notice  Set the whitelist status of a single user
     * @param   _user       User address
     * @param   _status     True for whitelisted, false for blacklisted
     */
    function setWhitelistStatus(address _user, bool _status) external onlyOwner {
        _modifyWhitelist(_user, _status);
    }

    /**
     * @notice  Set the whitelist status of multiple users
     * @param   _users      User addresses
     * @param   _statuses   True for whitelisted, false for blacklisted
     */
    function setWhitelistStatuses(address[] calldata _users, bool[] calldata _statuses) external onlyOwner {
        uint256 len = _users.length;
        require(_statuses.length == len, "!len");

        for (uint256 i; i < len; ++i) {
            _modifyWhitelist(_users[i], _statuses[i]);
        }
    }

    function _modifyWhitelist(address _user, bool _status) internal {
        whitelisted[_user] = _status;
        emit NewWhitelistStatus(_user, _status);
    }

    // ----- Trader Functions -----

    /**
     * @notice  Take custody of the vault's funds for the purpose of executing trading strategies
     */
    function custodyFunds() external onlyTrader notCustodied duringEpoch {
        uint256 amount = totalAssets();
        require(amount > 0, "!amount");

        custodied = true;
        custodiedAmount = amount;
        asset.safeTransfer(trader, amount);

        emit FundsCustodied(epochId.current(), amount);
    }

    /**
     * @notice  Return custodied funds to the vault
     * @param   _amount     Amount to return
     * @dev     The trader is responsible for returning the whole sum taken into custody.
     *          Losses may be sustained during the trading, in which case the investors will suffer a loss.
     *          Returning the funds ends the epoch.
     */
    function returnFunds(uint256 _amount) external onlyTrader {
        require(custodied, "!custody");
        require(_amount > 0, "!amount");
        asset.safeTransferFrom(trader, address(this), _amount);

        uint256 currentEpoch = getCurrentEpoch();
        Epoch storage epoch = epochs[currentEpoch];
        epoch.epochEnd = block.timestamp;

        custodiedAmount = 0;
        custodied = false;
        started = false;
        totalDeposits = totalAssets();

        emit FundsReturned(currentEpoch, _amount);
    }

    // ----- View Functions -----

    /**
     * @notice  Get the current epoch ID
     * @return  Current epoch ID
     */
    function getCurrentEpoch() public view returns (uint256) {
        return epochId.current();
    }

    /**
     * @notice  Get the current epoch information
     * @return  Current epoch information
     */
    function getCurrentEpochInfo() external view returns (Epoch memory) {
        return epochs[epochId.current()];
    }

    /**
     * @notice  View whether the contract state is in funding phase
     * @return  True if in funding phase
     */
    function isFunding() external view returns (bool) {
        Epoch storage epoch = epochs[epochId.current()];
        return block.timestamp >= epoch.fundingStart && block.timestamp < epoch.epochStart;
    }

    /**
     * @notice  View whether the contract state is in epoch phase
     * @return  True if in epoch phase
     */
    function isInEpoch() external view returns (bool) {
        Epoch storage epoch = epochs[epochId.current()];
        return block.timestamp >= epoch.epochStart && block.timestamp < epoch.epochEnd;
    }

    /**
     * @notice  Returns true if notCustodied and duringFunding modifiers would pass
     * @dev     Only to be used with previewDeposit and previewMint
     */
    function notCustodiedAndDuringFunding() internal view returns (bool) {
        Epoch storage epoch = epochs[epochId.current()];
        return (!custodied && (block.timestamp >= epoch.fundingStart && block.timestamp < epoch.epochStart));
    }

    /**
     * @notice  Returns true if notCustodied and notDuringEpoch modifiers would pass
     * @dev     Only to be used with previewRedeem and previewWithdraw
     */
    function notCustodiedAndNotDuringEpoch() internal view returns (bool) {
        Epoch storage epoch = epochs[epochId.current()];
        return (!custodied && (block.timestamp < epoch.epochStart || block.timestamp >= epoch.epochEnd));
    }

    // ----- Overrides -----

    /// @dev    See EIP-4626
    function maxDeposit(address) public view override returns (uint256) {
        if (custodied) return 0;
        return totalDeposits > maxDeposits ? 0 : maxDeposits - totalDeposits;
    }

    /// @dev    See EIP-4626
    function maxMint(address) public view override returns (uint256) {
        return convertToShares(maxDeposit(msg.sender));
    }

    /// @dev    See EIP-4626
    function deposit(uint256 assets, address receiver) public override notCustodied duringFunding onlyWhitelisted returns (uint256) {
        require(assets <= maxDeposit(receiver), "!maxDeposit");
        return super.deposit(assets, receiver);
    }

    /// @dev    See EIP-4626
    /// @notice Will return 0 if not during funding window
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return (notCustodiedAndDuringFunding()) ? super.previewDeposit(assets) : 0;
    }

    /// @dev    See EIP-4626
    function mint(uint256 shares, address receiver) public override notCustodied duringFunding onlyWhitelisted returns (uint256) {
        require(shares <= maxMint(receiver), "!maxMint");
        return super.mint(shares, receiver);
    }

    /// @dev    See EIP-4626
    /// @notice Will return 0 if not during funding window
    function previewMint(uint256 shares) public view override returns (uint256) {
        return (notCustodiedAndDuringFunding()) ? super.previewMint(shares) : 0;
    }

    /// @dev    See EIP-4626
    function withdraw(
        uint256 assets,
        address receiver,
        address _owner
    ) public override notCustodied notDuringEpoch onlyWhitelisted returns (uint256) {
        return super.withdraw(assets, receiver, _owner);
    }

    /// @dev    See EIP-4626
    /// @notice Will return 0 if funds are custodied or during epoch
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return (notCustodiedAndNotDuringEpoch()) ? super.previewWithdraw(assets) : 0;
    }

    /// @dev    See EIP-4626
    function redeem(
        uint256 shares,
        address receiver,
        address _owner
    ) public override notCustodied notDuringEpoch onlyWhitelisted returns (uint256) {
        return super.redeem(shares, receiver, _owner);
    }

    /// @dev    See EIP-4626
    /// @notice Will return 0 if funds are custodied or during epoch
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return (notCustodiedAndNotDuringEpoch()) ? super.previewRedeem(shares) : 0;
    }

    /// @dev    See EIP-4626
    function totalAssets() public view override returns (uint256) {
        return custodied ? custodiedAmount : asset.balanceOf(address(this));
    }

    /// @dev    See EIP-4626
    function beforeWithdraw(uint256 assets, uint256 shares) internal override {
        if (totalDeposits > assets) {
            totalDeposits -= assets;
        } else {
            totalDeposits = 0;
        }
    }

    /// @dev    See EIP-4626
    function afterDeposit(uint256 assets, uint256 shares) internal override {
        totalDeposits += assets;
    }
}

