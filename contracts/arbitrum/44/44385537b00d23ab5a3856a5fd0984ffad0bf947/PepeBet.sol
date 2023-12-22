// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { AccessControl } from "./AccessControl.sol";
import { Pausable } from "./Pausable.sol";
import { BetDetails, WagerTokenDetails } from "./Structs.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeBet } from "./IPepeBet.sol";
import { IPepePool } from "./IPepePool.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepeBet is AccessControl, Pausable, IPepeBet {
    using SafeERC20 for IERC20;

    bytes32 public constant PEPE_ADMIN = keccak256("PEPE_ADMIN");
    bytes32 public constant PEPE_CROUPIER = keccak256("PEPE_CROUPIER");

    address public override liquidityPool;
    address public override feeTaker;
    address public override oracle;
    uint256 public override betId;
    uint16 public override fee; //in bps
    uint16 public override leverage; //in bps
    uint16 public override minRunTime;
    uint16 public override maxRunTime;

    mapping(address => WagerTokenDetails) public wagerTokenDetails; ///@dev wager token details
    mapping(uint256 => BetDetails) public betDetails; ///@dev bet details
    mapping(address => bool) public approvedAssets; ///@dev approved assets to bet against
    mapping(address => bool) public approvedWagerTokens; ///@dev approved wager tokens
    mapping(address => mapping(address => uint256)) public balances; ///@dev user balances

    event FeeUpdated(uint16 oldFee, uint16 newFee);
    event FeePaid(address indexed payer, address indexed token, address indexed feeTaker, uint256 fee);
    event Deposit(address indexed depositor, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event BetPlaced(
        uint256 indexed betId,
        address indexed initiator,
        address indexed asset,
        address betToken,
        uint256 openingPrice,
        uint256 startTime,
        uint256 endTime,
        uint256 runTime
    );
    event ApprovedWagerTokens(WagerTokenDetails[] tokens);
    event RevokedWagerToken(address indexed token);
    event SettledBet(address indexed user, uint256 indexed betId, address indexed betToken, bool won, uint256 payout);
    event LiquidityPoolUpdated(address indexed oldPool, address indexed newPool);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event ApprovedAssets(address[] assets);
    event RevokedAssets(address[] assets);
    event LeverageUpdated(uint16 oldLeverage, uint16 newLeverage);
    event FeeTakerChanged(address indexed oldFeeTaker, address indexed newFeeTaker);
    event ModifiedBetRunTime(uint16 minRunTime, uint16 maxRunTime);
    event TokenDetailsUpdated(address indexed token, uint256 minBetAmount, uint256 maxBetAmount);

    error InvalidTime();
    error InvalidAddress();
    error InsufficientAmount();
    error InvalidAmount();
    error InsufficientPepeBalance(uint256 requested, uint256 available);
    error WithdrawalFailed();
    error UnapprovedAsset(address asset);
    error UnapprovedToken(address token);
    error InvalidLeverage();
    error InvalidFee();
    error FailedToTakeWager();
    error NotOracle();
    error NotExternalOracle();
    error DepositFailed();
    error FailedToTakeFee();
    error LiquidityPoolNotSet();
    error DuplicateAsset(address asset);
    error TokenNotAllowed(address token);

    constructor(
        address _feeTaker,
        address _liquidityPool,
        address _oracle,
        address[] memory _approveAssets,
        uint16 _fee,
        uint16 _leverage,
        uint16 _minRunTime,
        uint16 _maxRunTime
    ) {
        feeTaker = _feeTaker;
        liquidityPool = _liquidityPool;
        oracle = _oracle;
        fee = _fee;
        leverage = _leverage;
        minRunTime = _minRunTime;
        maxRunTime = _maxRunTime;

        uint256 assetLength = _approveAssets.length;
        uint256 i;
        for (; i < assetLength; ) {
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
    ///@param betToken The token used to place the bet (wager token)
    ///@param amount The amount to place as bet
    ///@param openingPrice The price of asset recorded by oracle when bet was initiated
    ///@param runTime The bet runtime
    ///@param isLong The direction of trade. Long/Short
    function placeBet(
        address user,
        address asset,
        address betToken,
        uint256 amount,
        uint256 openingPrice,
        uint256 runTime,
        bool isLong
    ) external override onlyRole(PEPE_CROUPIER) whenNotPaused {
        if (!approvedWagerTokens[betToken]) revert TokenNotAllowed(betToken);
        if (!approvedAssets[asset]) revert UnapprovedAsset(asset);
        if (runTime < minRunTime || runTime > maxRunTime) revert InvalidTime();
        if (liquidityPool == address(0)) revert LiquidityPoolNotSet();
        if (balances[betToken][user] < amount) {
            revert InsufficientPepeBalance(amount, balances[betToken][user]);
        }

        WagerTokenDetails memory tokenDetail = wagerTokenDetails[betToken];

        if (amount < tokenDetail.minBetAmount || amount > tokenDetail.maxBetAmount) revert InvalidAmount();

        balances[betToken][user] -= amount;

        uint256 wagerAmount = takeFees(user, betToken, amount);
        IERC20(betToken).safeTransfer(liquidityPool, wagerAmount);
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
            betToken: betToken,
            asset: asset,
            isLong: isLong,
            active: true
        });
        emit BetPlaced(
            _betId,
            user,
            asset,
            betToken,
            openingPrice,
            block.timestamp,
            block.timestamp + runTime,
            runTime
        );
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
                payoutWinnings(
                    closeBetDetails.initiator,
                    closeBetDetails.betToken,
                    closeBetDetails.wagerAmount,
                    closeBetDetails.betId
                );
                return;
            }
            emit SettledBet(closeBetDetails.initiator, betID, closeBetDetails.betToken, false, 0);
        } else {
            if (closeBetDetails.openingPrice >= closingPrice) {
                payoutWinnings(
                    closeBetDetails.initiator,
                    closeBetDetails.betToken,
                    closeBetDetails.wagerAmount,
                    closeBetDetails.betId
                );
                return;
            }
            emit SettledBet(closeBetDetails.initiator, betID, closeBetDetails.betToken, false, 0);
        }
    }

    function payoutWinnings(address initiator, address betToken, uint256 wagerAmount, uint256 betID) private {
        uint256 payout = ((wagerAmount * leverage) / 1e4) + wagerAmount;
        IPepePool(liquidityPool).payout(initiator, betToken, payout, betID);
        balances[betToken][initiator] += payout;

        emit SettledBet(initiator, betID, betToken, true, payout);
    }

    function deposit(uint256 amount, address token) external override whenNotPaused {
        if (amount == 0) revert InsufficientAmount();
        if (!approvedWagerTokens[token]) revert TokenNotAllowed(token);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        balances[token][msg.sender] += amount; //configure this to get the balance per token address

        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(uint256 amount, address token) external override {
        if (amount == 0) revert InsufficientAmount();
        if (balances[token][msg.sender] < amount) revert InsufficientPepeBalance(amount, balances[token][msg.sender]);

        balances[token][msg.sender] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawal(msg.sender, token, amount);
    }

    function takeFees(address payer, address token, uint256 amount) private returns (uint256) {
        if (fee == 0) return amount;
        uint256 fees = ((amount * fee) / 1e4);
        IERC20(token).safeTransfer(feeTaker, fees);

        emit FeePaid(payer, token, feeTaker, fees);
        return amount - fees;
    }

    ///@notice admin functions
    function pause() external override onlyRole(PEPE_ADMIN) {
        _pause();
    }

    function unPause() external override onlyRole(PEPE_ADMIN) {
        _unpause();
    }

    function modifyFee(uint16 newFee) external override onlyRole(PEPE_ADMIN) {
        if (newFee >= 1e4) revert InvalidFee();
        uint16 oldFee = fee;
        fee = newFee;
        emit FeeUpdated(oldFee, newFee);
    }

    function modifyMinAndMaxBetRunTime(uint16 _minRunTime, uint16 _maxRunTime) external override onlyRole(PEPE_ADMIN) {
        if (_minRunTime == 0 || _maxRunTime == 0 || _minRunTime >= _maxRunTime) {
            revert InvalidTime();
        }
        minRunTime = _minRunTime;
        maxRunTime = _maxRunTime;

        emit ModifiedBetRunTime(minRunTime, maxRunTime);
    }

    function setLiquidityPool(address _liquidityPool) external override onlyRole(PEPE_ADMIN) {
        if (_liquidityPool == address(0)) revert InvalidAddress();
        address oldPool = liquidityPool;
        liquidityPool = _liquidityPool;
        emit LiquidityPoolUpdated(oldPool, liquidityPool);
    }

    function updateOracle(address _oracle) external override onlyRole(PEPE_ADMIN) {
        if (_oracle == address(0)) revert InvalidAddress();
        address oldOracle = oracle;
        oracle = _oracle;
        emit OracleUpdated(oldOracle, _oracle);
    }

    ///@notice add token(s) to the list of allowed wager tokens
    ///@param tokenDetails_ the details of the token(s) to be added
    function approveWagerTokens(WagerTokenDetails[] calldata tokenDetails_) external override onlyRole(PEPE_ADMIN) {
        uint256 tokenDetailsLength = tokenDetails_.length;
        uint256 i;
        for (; i < tokenDetailsLength; ) {
            WagerTokenDetails memory tokenDetail = tokenDetails_[i];

            require(!approvedWagerTokens[tokenDetail.token], "PepeBet: Token already approved");
            require(tokenDetail.token != address(0), "PepeBet: Invalid token address");
            require(
                tokenDetail.minBetAmount != 0 && tokenDetail.maxBetAmount > tokenDetail.minBetAmount,
                "PepeBet: Invalid bet amounts"
            );

            approvedWagerTokens[tokenDetail.token] = true;
            wagerTokenDetails[tokenDetail.token] = tokenDetail;

            unchecked {
                ++i;
            }
        }
        emit ApprovedWagerTokens(tokenDetails_);
    }

    ///@notice remove a token from the list of allowed wager tokens
    ///@param tokens_ the addresses of the token(s) to be removed
    function revokeWagerTokens(address[] calldata tokens_) external override onlyRole(PEPE_ADMIN) {
        uint256 tokensLength = tokens_.length;
        uint256 i;
        for (; i < tokensLength; ) {
            if (!approvedWagerTokens[tokens_[i]]) revert TokenNotAllowed(tokens_[i]);
            delete approvedWagerTokens[tokens_[i]];
            delete wagerTokenDetails[tokens_[i]];

            emit RevokedWagerToken(tokens_[i]);

            unchecked {
                ++i;
            }
        }
    }

    ///@notice update the details of a wager token.
    ///@param tokenAddress the address of the token to be added
    ///@param _maxBetAmount the maximum amount of the token that can be used as a wager
    ///@param _minBetAmount the minimum amount of the token that can be used as a wager
    function updateWagerTokenDetails(
        address tokenAddress,
        uint256 _maxBetAmount,
        uint256 _minBetAmount
    ) external override onlyRole(PEPE_ADMIN) {
        require(approvedWagerTokens[tokenAddress], "PepeBet: Token does not exist");
        require(tokenAddress != address(0), "PepeBet: Invalid token address");
        require(_minBetAmount != 0 && _maxBetAmount > _minBetAmount, "PepeBet: Invalid bet amounts");

        wagerTokenDetails[tokenAddress].maxBetAmount = _maxBetAmount;
        wagerTokenDetails[tokenAddress].minBetAmount = _minBetAmount;

        emit TokenDetailsUpdated(tokenAddress, _minBetAmount, _maxBetAmount);
    }

    ///@notice approves new tokens to be bet against. Eg: ARB, ETH
    ///@param newAssets array of new assets to be approved
    function approveAssets(address[] calldata newAssets) external override onlyRole(PEPE_ADMIN) {
        uint256 newAssetsLength = newAssets.length;
        uint256 i;
        for (; i < newAssetsLength; ) {
            if (approvedAssets[newAssets[i]]) revert DuplicateAsset(newAssets[i]);
            approvedAssets[newAssets[i]] = true;
            unchecked {
                ++i;
            }
        }
        emit ApprovedAssets(newAssets);
    }

    ///@notice unapproves assets that can be bet against
    ///@param assets array of assets to be unapproved
    function unapproveAssets(address[] calldata assets) external override onlyRole(PEPE_ADMIN) {
        uint256 assetsLength = assets.length;
        uint256 i;
        for (; i < assetsLength; ) {
            if (!approvedAssets[assets[i]]) revert UnapprovedAsset(assets[i]);
            approvedAssets[assets[i]] = false;
            unchecked {
                ++i;
            }
        }
        emit RevokedAssets(assets);
    }

    function modifyLeverage(uint16 newLeverage) external override onlyRole(PEPE_ADMIN) {
        if (newLeverage == 0 || newLeverage > 1e4) revert InvalidLeverage();
        uint16 oldLeverage = leverage;
        leverage = newLeverage;
        emit LeverageUpdated(oldLeverage, newLeverage);
    }

    function updateFeeTaker(address newFeeTaker) external override onlyRole(PEPE_ADMIN) {
        if (newFeeTaker == address(0)) revert InvalidAddress();
        address oldFeeTaker = feeTaker;
        feeTaker = newFeeTaker;
        emit FeeTakerChanged(oldFeeTaker, newFeeTaker);
    }
}

