// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import {UD60x18, ud, convert} from "./UD60x18.sol";

/// @title OptionixV15
/// @dev  This contract is for handling trading operations and processingliquidity in Optionix web app.
///       It also implements UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable patterns.
///       It monitors win rates and Liquidity Provider Balances.
/// @author https://github.com/makskorotkoff
contract OptionixV15 is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @dev Timestamp for next update.
    uint public nextUpdateTimestamp;
    /// @dev Total liquidity provided.
    uint public liquidityPool;
    /// @dev Commissions gained by the owner.
    uint ownerComissions;
    /// @dev Total commissions.
    int public comissionsPool;
    int public prevComissionsPool;

    /// @dev Initial win rate for an new symbol.
    UD60x18 public INITIAL_WIN_RATE;

    /// @dev Comission rate of owner.
    UD60x18 public OWNER_COMISSION;

    /// @dev Comission rate of liquidity providers.
    UD60x18 public LIQUIDITY_PROVIDERS_COMISSION;

    /// @dev Struct to store timestamp and fee per unit liquidity.
    struct Timestamp {
        uint timestamp;
        UD60x18 feePerLiquidityUnit;
    }

    /// @dev An array to store timestamps.
    Timestamp[] public timestamps;

    /// @dev Struct to store LiquidityProvider's balance and timestamp of liquidity deposit.
    struct LiquidityProviderBalance {
        uint timestamp;
        uint balance;
    }

    /// @dev Mapping to store data about liquidity providers.
    mapping(address => LiquidityProviderBalance) liquidityProviderBalances;

    /// @dev Mapping to store balance of regular users.
    mapping(address => uint) userBalance;

    /// @dev Mapping to store win rates per trading pair.
    mapping(string => UD60x18) public winRates;

    /// @dev Parameter related to maximum bet calculation.
    uint public MAXBET_COEF;

    /// @dev The minimum bet value.
    uint public minBet;

    /// @dev Factor for Exponential Moving Average (EMA) calculation.
    UD60x18 public EMA_FACTOR;

    /// @dev Flag to prevent reentrancy attacks.
    bool private locked;

    address public timeLock;

    uint public minLiquidity;

    /// @dev Event to be emitted when a bet is completed.

    event BetResult(
        address indexed _better,
        string _symbol,
        uint _amount,
        int _direction,
        uint _result,
        uint _initialPrice,
        uint _finalPrice,
        uint _startTimestamp,
        uint _endTimestamp
    );

    /// @dev Modifier to prevent reentrancy.
    modifier reentrancyGuard() {
        require(!locked, "Reentrancy denied");
        locked = true;
        _;
        locked = false;
    }

    modifier onlyTimelock() {
        require(
            address(msg.sender) == timeLock,
            "Only timelock can call this function"
        );
        _;
    }

    /// @notice Initializer function.
    /// @dev Initializes the contract.
    function initialize(address _timeLock) public initializer {
        _transferOwnership(_msgSender());

        nextUpdateTimestamp = block.timestamp + 86400;
        INITIAL_WIN_RATE = ud(0.5e18);
        EMA_FACTOR = ud(0.02e18);
        OWNER_COMISSION = ud(0.05e18);
        LIQUIDITY_PROVIDERS_COMISSION = ud(0.1e18);
        MAXBET_COEF = 2;
        minBet = 0.003 ether;
        timeLock = _timeLock;
        minLiquidity = 0.05 ether;
        addTradingPair("BTCUSDT");
    }

    /// @dev Function to authorize upgrades.
    function _authorizeUpgrade(address) internal override onlyTimelock {}

    function updateTimeLock(address _timeLock) public onlyTimelock {
        timeLock = _timeLock;
    }

    /// @notice This function pauses the contract.
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice This function unpauses the contract.
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice This function allows depositing liquidity into the contract.
    function depositLiquidity() public payable whenNotPaused {
        require(
            msg.value >= minLiquidity,
            "Value should be greater than minimal treshold"
        ); // value should be greater than minLiquidity
        require(
            liquidityProviderBalances[msg.sender].balance == 0,
            "Already deposited"
        );
        liquidityPool += msg.value;

        // create a new struct instance
        LiquidityProviderBalance memory newBalance = LiquidityProviderBalance({
            timestamp: block.timestamp,
            balance: msg.value
        });

        // push the new struct instance into the corresponding array in the mapping
        liquidityProviderBalances[msg.sender] = newBalance;
    }

    // @notice Updates fee.
    /// @dev This function calculates and updates the fee, owners commission and timestamps.
    function updateFee() internal {
        uint _curTimestamp = block.timestamp;
        require(comissionsPool > prevComissionsPool, "Delta negative");
        uint _delta = uint(comissionsPool - prevComissionsPool);
        uint _ownersComission = convert(convert(_delta).mul(OWNER_COMISSION));
        ownerComissions += _ownersComission;
        _delta -= _ownersComission;
        UD60x18 _newFee = convert(_delta).div(convert(liquidityPool));
        Timestamp memory _timestamp = Timestamp({
            timestamp: _curTimestamp,
            feePerLiquidityUnit: _newFee
        });
        timestamps.push(_timestamp);
        prevComissionsPool = comissionsPool;
        nextUpdateTimestamp = nextUpdateTimestamp + 86400;
    }

    /// @notice Deposits user balance.
    /// @dev Public function to deposit user balance which is invokable only when the contract is not paused.
    function depositUserBalance() public payable whenNotPaused {
        userBalance[msg.sender] += msg.value;
    }

    /// @notice Views liquidity provider initial balance.
    /// @dev It returns the initial balance of the liquidity provider.
    function viewLiquidityProviderInitialBalance() public view returns (uint) {
        return liquidityProviderBalances[msg.sender].balance;
    }

    /// @notice Calculates and returns liquidity providers current balance.
    /// @dev It calculates the current balance of the liquidity provider.
    function calculateLiquidityProvidersCurrentBalance()
        public
        view
        returns (uint)
    {
        if (liquidityProviderBalances[msg.sender].balance == 0) {
            return 0;
        }
        int _comission;
        for (uint i = 0; i < timestamps.length; i++) {
            if (
                timestamps[i].timestamp >
                liquidityProviderBalances[msg.sender].timestamp
            ) {
                _comission += int(
                    convert(
                        timestamps[i].feePerLiquidityUnit.mul(
                            convert(
                                liquidityProviderBalances[msg.sender].balance
                            )
                        )
                    )
                );
            }
        }
        if (comissionsPool < prevComissionsPool) {
            _comission -= int(
                convert(
                    (
                        convert(uint(prevComissionsPool - comissionsPool)).div(
                            convert(liquidityPool)
                        )
                    ).mul(
                            convert(
                                liquidityProviderBalances[msg.sender].balance
                            )
                        )
                )
            );
        }

        uint _toWithdraw;
        if (_comission <= 0) {
            require(
                liquidityProviderBalances[msg.sender].balance >
                    uint(-_comission),
                "Insufficient balance"
            );
            _toWithdraw =
                liquidityProviderBalances[msg.sender].balance -
                uint(-_comission);
        } else {
            _toWithdraw =
                liquidityProviderBalances[msg.sender].balance +
                uint(_comission);
        }
        return _toWithdraw;
    }

    /// @notice Allows liquidity providers to withdraw their liquidity.
    /// @dev This function performs several checks before effectively removing the liquidity
    function withdrawLiquidity() public reentrancyGuard {
        require(
            liquidityProviderBalances[msg.sender].balance > 0,
            "Not deposited"
        );
        uint _toWithdraw = calculateLiquidityProvidersCurrentBalance();
        liquidityPool -= liquidityProviderBalances[msg.sender].balance;
        LiquidityProviderBalance
            memory _zeroBalance = LiquidityProviderBalance({
                timestamp: 0,
                balance: 0
            });
        liquidityProviderBalances[msg.sender] = _zeroBalance;
        address payable _receiver = payable(msg.sender);
        (bool success, ) = _receiver.call{value: _toWithdraw}("");
        require(success, "withdrawLiquidity() failed");
    }

    /// @notice Allows users to withdraw their balance.
    /// @param _amount This is the amount the user wishes to withdraw.
    /// @dev This function performs a balance check before effectively removing from the user's balance.
    function withdrawUserBalance(uint _amount) public reentrancyGuard {
        require(userBalance[msg.sender] >= _amount, "Not enough balance");
        userBalance[msg.sender] -= _amount;
        address payable _receiver = payable(msg.sender);
        (bool success, ) = _receiver.call{value: _amount}("");
        require(success, "withdrawUserBalance() failed");
    }

    /// @notice Adds trading pair
    /// @param _symbol Token name or symbol for the pair.
    /// @dev Only callable by the owner of the contract.
    function addTradingPair(string memory _symbol) public onlyOwner {
        winRates[_symbol] = INITIAL_WIN_RATE;
    }

    receive() external payable {
        depositUserBalance();
    }

    fallback() external payable {
        depositUserBalance();
    }

    /**
     *  @notice Calculate the maximum allowable bet
     *  @return Returns the value of the maximum bet
     */
    function calculateMaxBet() public view returns (uint) {
        return minBet * MAXBET_COEF;
    }

    /**
     *  @notice Update's the winning rate for a given symbol based on the result
     *  @param _symbol The symbol for which the winning rate is to be updated
     *  @param _result The result used to update the winning rate
     */
    function updateWinrate(string memory _symbol, uint _result) internal {
        if (_result == 1 && winRates[_symbol] <= convert(_result)) {
            winRates[_symbol] = (
                (convert(_result).sub(winRates[_symbol])).mul(EMA_FACTOR)
            ).add(winRates[_symbol]);
        } else {
            winRates[_symbol] = winRates[_symbol].sub(
                winRates[_symbol].mul(EMA_FACTOR)
            );
        }
    }

    /**
     *  @notice Calculate the commission share for a given symbol
     *  @param _symbol The symbol for which the commission share is to be calculated
     *  @return Returns calculated commission share
     */
    function calculateComissionShare(
        string memory _symbol
    ) public view returns (UD60x18) {
        UD60x18 _comissionToComsissionPool;
        winRates[_symbol] >= ud(0.5e18)
            ? _comissionToComsissionPool =
                ud(2e18) -
                ud(1e18) /
                winRates[_symbol] +
                LIQUIDITY_PROVIDERS_COMISSION
            : _comissionToComsissionPool = LIQUIDITY_PROVIDERS_COMISSION;
        return _comissionToComsissionPool;
    }

    /**
     *  @notice It handles result of the bet. It sets conditions for valid bet and makes the necessary changes upon winning or losing
     *  @param _better Address of the person who is betting
     *  @param _symbol The symbol that's part of the bet
     *  @param _amount The size of the bet
     *  @param _direction The direction of the bet
     *  @param _result The outcome of the bet
     *  @param _initialPrice Initial price at the time of the bet
     *  @param _finalPrice Final price at the time of the bet
     *  @param _startTimestamp Start time of the bet
     *  @param _endTimestamp End time of the bet
     */
    function betResult(
        address _better,
        string memory _symbol,
        uint _amount,
        int _direction,
        uint _result,
        uint _initialPrice,
        uint _finalPrice,
        uint _startTimestamp,
        uint _endTimestamp
    ) external onlyOwner whenNotPaused {
        require(_amount >= minBet, "Bet too small");
        require(_amount <= liquidityPool, "Not enough liquidity");
        require(userBalance[_better] >= _amount, "Not enough balance");
        uint _maxBet = calculateMaxBet();
        require(_amount <= _maxBet, "Bet too big");
        require(winRates[_symbol] > ud(0), "Trading pair not initialized");
        require(_result == 1 || _result == 0, "Invalid result");
        if (comissionsPool < 0) {
            require(
                liquidityPool + uint(prevComissionsPool) >
                    uint(-comissionsPool) + _amount,
                "Not enough liquidity"
            );
        }
        uint gasStart = gasleft();
        if (_result == 1) {
            UD60x18 _comissionToComsissionPool = calculateComissionShare(
                _symbol
            );
            uint _comissionValue = convert(
                _comissionToComsissionPool.mul(convert(_amount))
            );
            if (_amount < _comissionValue) {
                _comissionValue = _amount;
            }
            userBalance[_better] += _amount - _comissionValue;
            comissionsPool = comissionsPool - int(_amount - _comissionValue);
        } else {
            userBalance[_better] -= _amount;
            comissionsPool = comissionsPool + int(_amount);
        }

        updateWinrate(_symbol, _result);
        emit BetResult(
            _better,
            _symbol,
            _amount,
            _direction,
            _result,
            _initialPrice,
            _finalPrice,
            _startTimestamp,
            _endTimestamp
        );
        if (
            block.timestamp > nextUpdateTimestamp &&
            comissionsPool - prevComissionsPool > 0
        ) {
            updateFee();
        }
        uint gasUsed = gasStart - gasleft();
        uint cost = tx.gasprice * gasUsed;
        if (cost > userBalance[_better]) {
            userBalance[_better] = 0;
            ownerComissions += cost - userBalance[_better];
        } else {
            userBalance[_better] -= cost;
            ownerComissions += cost;
        }
    }

    /**
     *  @notice Get the balance of the contract
     *  @return Returns the balance of the contract
     */
    function getBalance() external view returns (uint) {
        return address(this).balance;
    }

    /**
     *  @notice Withdraw owner's commissions to the contract's owner address
     */
    function withdrawOwnerComissions(
        address _to
    ) external onlyOwner reentrancyGuard {
        (bool success, ) = _to.call{value: ownerComissions}("");
        require(success, "withdrawOwnerComissions() failed");
        ownerComissions = 0;
    }

    /**
     *  @notice Set the commission for the contract's owner
     *  @param _comission The new commission value to be set
     */
    function setOwnerComission(uint256 _comission) external onlyOwner {
        require(_comission <= 10, "Comission must be less than 5%");
        OWNER_COMISSION = convert(_comission).mul(ud(0.01e18));
    }

    /**
     *  @notice Set the commission for the liquidity providers
     *  @param _comission The new commission value to be set
     */
    function setLiquidityProvidersComission(
        uint256 _comission
    ) external onlyOwner {
        require(_comission <= 10, "Comission must be less than 10%");
        LIQUIDITY_PROVIDERS_COMISSION = convert(_comission).mul(ud(0.01e18));
    }

    /**
     *  @notice Set the EMA factor for the contract
     *  @param _factor The new EMA factor to be set
     */
    function setEmaFactor(uint256 _factor) external onlyOwner {
        require(_factor <= 100, "EMA factor too big");
        EMA_FACTOR = convert(_factor).mul(ud(0.001e18));
    }

    /**
     *  @notice Set the minimum bet size
     *  @param _bet The new minimum bet size to be set
     */
    function setMinBet(uint256 _bet) external onlyOwner {
        minBet = _bet;
    }

    /**
     *  @notice Set the maximum bet coefficient for the contract
     *  @param _maxBet The new maximum bet coefficient to be set
     */
    function setMaxBetCoef(uint256 _maxBet) external onlyOwner {
        MAXBET_COEF = _maxBet;
    }

    function setMinLiquidity(uint _minLiquidity) external onlyOwner {
        minLiquidity = _minLiquidity;
    }

    /**
     *  @notice Get the number of timestamps in the contract
     *  @return Returns the current number of timestamps in the contract
     */
    function getTimestapsLength() external view returns (uint) {
        return timestamps.length;
    }

    /**
     *  @notice Get the current block time (time when the current Ethereum block was mined)
     *  @return Returns the current block time
     */
    function getCurrentTimestamp() external view returns (uint) {
        return block.timestamp;
    }

    /**
     *  @notice Get various states of the contract
     *  @param key The key for which certain elements are to be returned
     */
    function getContractState(
        string memory key
    )
        external
        view
        returns (
            uint getUserBalance,
            UD60x18 getWinRate,
            uint getMinBet,
            uint getMaxBet,
            UD60x18 comissionShare,
            uint getLiquidityProvided,
            uint getCurrentLiquidity
        )
    {
        return (
            userBalance[msg.sender],
            winRates[key],
            minBet,
            calculateMaxBet(),
            calculateComissionShare(key),
            viewLiquidityProviderInitialBalance(),
            calculateLiquidityProvidersCurrentBalance()
        );
    }

    function viewUserBalance() external view returns (uint) {
        return userBalance[msg.sender];
    }

    function viewOwnerComissions() external view onlyOwner returns (uint) {
        return ownerComissions;
    }
}

