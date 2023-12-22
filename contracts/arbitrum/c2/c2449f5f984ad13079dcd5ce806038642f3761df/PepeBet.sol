// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {AccessControl} from "./AccessControl.sol";
import {Pausable} from "./Pausable.sol";
import {IPepeBet} from "./IPepeBet.sol";
import {IPepePool} from "./IPepePool.sol";

contract PepeBet is AccessControl, Pausable, IPepeBet {
    bytes32 public constant PEPE_ADMIN = keccak256("PEPE_ADMIN");
    bytes32 public constant PEPE_CROUPIER = keccak256("PEPE_CROUPIER");
    IERC20 public immutable IUSDC;

    struct BetDetails {
        uint256 amount;
        uint256 wagerAmount;
        uint256 openingPrice;
        uint256 closingPrice;
        uint256 startTime;
        uint256 endTime;
        uint256 betId;
        address initiator;
        address asset;
        bool isLong;
        bool active;
    }

    address public liquidityPool;
    address public feeTaker;
    address public oracle;
    uint256 public betId;
    uint256 public minBetAmount;
    uint256 public maxBetAmount;
    uint16 public fee; //in bps
    uint16 public leverage; //in bps
    uint16 public minRunTime;
    uint16 public maxRunTime;
    mapping(uint256 => BetDetails) public betDetails;
    mapping(address => bool) public approvedAssets;
    mapping(address => uint256) public balances;

    event FeeUpdated(uint16 oldFee, uint16 newFee);
    event FeePaid(address indexed payer, address indexed feeTaker, uint256 fee);
    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event BetPlaced(
        uint256 indexed betId,
        address indexed initiator,
        address indexed asset,
        uint256 openingPrice,
        uint256 startTime,
        uint256 endTime,
        uint256 runTime
    );
    event SettledBet(address indexed user, uint256 indexed betId, bool indexed won, uint256 payout);
    event LiquidityPoolUpdated(address indexed oldPool, address indexed newPool);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event NewAssets(address[] assets);
    event RevokedAssets(address[] assets);
    event LeverageUpdated(uint16 oldLeverage, uint16 newLeverage);
    event FeeTakerChanged(address indexed oldFeeTaker, address indexed newFeeTaker);
    event ModifiedBetAmount(uint256 minBetAmount, uint256 maxBetAmount);
    event ModifiedBetRunTime(uint16 minRunTime, uint16 maxRunTime);

    error InvalidTime();
    error InvalidAddress();
    error InsufficientAmount();
    error InvalidAmount();
    error InsufficientPepeBalance(uint256 requested, uint256 available);
    error WithdrawalFailed();
    error UnapprovedAsset(address asset);
    error InvalidLeverage();
    error InvalidFee();
    error FailedToTakeWager();
    error NotOracle();
    error NotExternalOracle();
    error DepositFailed();
    error FailedToTakeFee();
    error LiquidityPoolNotSet();
    error FailedToSettleBet(uint256 betId);
    error UnelapsedBet(uint256 betId);
    error DuplicateAsset(address asset);

    constructor(
        address _usdcAddress,
        address _feeTaker,
        address _liquidityPool,
        address _oracle,
        address[] memory _approveAssets,
        uint16 _fee,
        uint16 _leverage,
        uint16 _minRunTime,
        uint16 _maxRunTime
    ) {
        IUSDC = IERC20(_usdcAddress);
        feeTaker = _feeTaker;
        liquidityPool = _liquidityPool;
        oracle = _oracle;
        minBetAmount = 1e6; //1 USDC
        maxBetAmount = 5e6; //5 USDC
        fee = _fee;
        leverage = _leverage;
        minRunTime = _minRunTime;
        maxRunTime = _maxRunTime;

        uint256 assetLength = _approveAssets.length;
        for (uint256 i = 0; i < assetLength; ) {
            approvedAssets[_approveAssets[i]] = true;
            unchecked {
                ++i;
            }
        }
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PEPE_ADMIN, msg.sender);
        _grantRole(PEPE_CROUPIER, msg.sender);
    }

    modifier onlyOracle() {
        if (msg.sender != oracle) revert NotOracle();
        _;
    }

    ///@param user The user who initiated the bet
    ///@param asset the approved asset betting against, eg BTC
    ///@param amount The amount to place as bet
    ///@param openingPrice The price of asset recorded by oracle when bet was initiated
    ///@param runTime The bet runtime
    ///@param isLong The direction of trade. Long/Short
    function placeBet(
        address user,
        address asset,
        uint256 amount,
        uint256 openingPrice,
        uint256 runTime,
        bool isLong
    ) external onlyRole(PEPE_CROUPIER) whenNotPaused {
        if (runTime < minRunTime || runTime > maxRunTime) revert InvalidTime();
        if (amount < minBetAmount || amount > maxBetAmount) revert InvalidAmount();
        if (balances[user] < amount) revert InsufficientPepeBalance(amount, balances[user]);
        if (!approvedAssets[asset]) revert UnapprovedAsset(asset);
        if (liquidityPool == address(0)) revert LiquidityPoolNotSet();

        balances[user] -= amount;
        uint256 wagerAmount = takeFees(user, amount);
        bool transferred = IUSDC.transfer(liquidityPool, wagerAmount);
        if (!transferred) revert FailedToTakeWager();
        uint256 _betId = ++betId;

        betDetails[_betId] = BetDetails({
            amount: amount,
            wagerAmount: wagerAmount,
            openingPrice: openingPrice,
            closingPrice: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + runTime,
            betId: _betId,
            initiator: user,
            asset: asset,
            isLong: isLong,
            active: true
        });
        emit BetPlaced(_betId, user, asset, openingPrice, block.timestamp, block.timestamp + runTime, runTime);
    }

    ///@param closingPrice The price the oracle recorded after the elapse runTime of the bet
    ///@param betID The ID of the bet to settle
    function settleBet(uint256 betID, uint256 closingPrice) external override onlyOracle {
        BetDetails memory closeBetDetails = betDetails[betID];

        require(closeBetDetails.endTime <= block.timestamp, "PepeBet: UnelapsedBet");
        require(closeBetDetails.active, "PepeBet: InactiveBet");
        require(liquidityPool != address(0), "PepeBet: LiquidityPoolNotSet");
        betDetails[betID].active = false;
        betDetails[betID].closingPrice = closingPrice;

        if (closeBetDetails.isLong) {
            if (closingPrice >= closeBetDetails.openingPrice) {
                uint256 payout = ((closeBetDetails.wagerAmount * leverage) / 1e4) + closeBetDetails.wagerAmount;
                IPepePool(liquidityPool).payout(closeBetDetails.initiator, payout, betID);
                balances[closeBetDetails.initiator] += payout;

                emit SettledBet(closeBetDetails.initiator, betID, true, payout);
                return;
            }

            emit SettledBet(closeBetDetails.initiator, betID, false, 0);
        } else {
            if (closeBetDetails.openingPrice >= closingPrice) {
                uint256 payout = ((closeBetDetails.wagerAmount * leverage) / 1e4) + closeBetDetails.wagerAmount;
                IPepePool(liquidityPool).payout(closeBetDetails.initiator, payout, betID);
                balances[closeBetDetails.initiator] += payout;

                emit SettledBet(closeBetDetails.initiator, betID, true, payout);
                return;
            }

            emit SettledBet(closeBetDetails.initiator, betID, false, 0);
        }
    }

    function deposit(uint256 amount) external whenNotPaused {
        if (amount == 0) revert InsufficientAmount();
        bool status = IUSDC.transferFrom(msg.sender, address(this), amount);
        if (!status) revert DepositFailed();
        balances[msg.sender] += amount;

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        if (amount == 0) revert InsufficientAmount();
        if (balances[msg.sender] < amount) revert InsufficientPepeBalance(amount, balances[msg.sender]);

        balances[msg.sender] -= amount;
        bool success = IUSDC.transfer(msg.sender, amount);
        if (!success) revert WithdrawalFailed();
        emit Withdrawal(msg.sender, amount);
    }

    function takeFees(address payer, uint256 amount) private returns (uint256) {
        if (fee == 0) return amount;
        uint256 fees = ((amount * fee) / 1e4);
        bool paid = IUSDC.transfer(feeTaker, fees);
        if (!paid) revert FailedToTakeFee();

        emit FeePaid(payer, feeTaker, fees);
        return amount - fees;
    }

    ///@notice admin functions
    function pause() external onlyRole(PEPE_ADMIN) {
        _pause();
    }

    function unPause() external onlyRole(PEPE_ADMIN) {
        _unpause();
    }

    function modifyFee(uint16 newFee) external onlyRole(PEPE_ADMIN) {
        if (newFee >= 1e4) revert InvalidFee();
        uint16 oldFee = fee;
        fee = newFee;
        emit FeeUpdated(oldFee, newFee);
    }

    function modifyMinAndMaxBetAmount(uint256 _minAmount, uint256 _maxAmount) external onlyRole(PEPE_ADMIN) {
        if (_minAmount == 0 || _maxAmount == 0 || _minAmount >= _maxAmount) revert InvalidAmount();
        minBetAmount = _minAmount;
        maxBetAmount = _maxAmount;

        emit ModifiedBetAmount(_minAmount, _maxAmount);
    }

    function modifyMinAndMaxBetRunTime(uint16 _minRunTime, uint16 _maxRunTime) external onlyRole(PEPE_ADMIN) {
        if (_minRunTime == 0 || _maxRunTime == 0 || _minRunTime >= _maxRunTime) revert InvalidTime();
        minRunTime = _minRunTime;
        maxRunTime = _maxRunTime;

        emit ModifiedBetRunTime(minRunTime, maxRunTime);
    }

    function setLiquidityPool(address _liquidityPool) external onlyRole(PEPE_ADMIN) {
        if (_liquidityPool == address(0)) revert InvalidAddress();
        address oldPool = liquidityPool;
        liquidityPool = _liquidityPool;
        emit LiquidityPoolUpdated(oldPool, liquidityPool);
    }

    function updateOracle(address _oracle) external onlyRole(PEPE_ADMIN) {
        if (_oracle == address(0)) revert InvalidAddress();
        address oldOracle = oracle;
        oracle = _oracle;
        emit OracleUpdated(oldOracle, _oracle);
    }

    function addNewAssets(address[] calldata newAssets) external onlyRole(PEPE_ADMIN) {
        uint256 newAssetsLength = newAssets.length;
        for (uint256 i = 0; i < newAssetsLength; ) {
            if (approvedAssets[newAssets[i]]) revert DuplicateAsset(newAssets[i]);
            approvedAssets[newAssets[i]] = true;
            unchecked {
                ++i;
            }
        }
        emit NewAssets(newAssets);
    }

    function unapproveAssets(address[] calldata assets) external onlyRole(PEPE_ADMIN) {
        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; ) {
            if (!approvedAssets[assets[i]]) revert UnapprovedAsset(assets[i]);
            approvedAssets[assets[i]] = false;
            unchecked {
                ++i;
            }
        }
        emit RevokedAssets(assets);
    }

    function modifyLeverage(uint16 newLeverage) external onlyRole(PEPE_ADMIN) {
        if (newLeverage == 0 || newLeverage > 9e3) revert InvalidLeverage();
        uint16 oldLeverage = leverage;
        leverage = newLeverage;
        emit LeverageUpdated(oldLeverage, newLeverage);
    }

    function updateFeeTaker(address newFeeTaker) external onlyRole(PEPE_ADMIN) {
        if (newFeeTaker == address(0)) revert InvalidAddress();
        address oldFeeTaker = feeTaker;
        feeTaker = newFeeTaker;
        emit FeeTakerChanged(oldFeeTaker, newFeeTaker);
    }
}

