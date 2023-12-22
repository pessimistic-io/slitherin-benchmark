// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IMasterChef.sol";
import "./IRewardRouterV2.sol";
import "./IVault.sol";
import "./IGlpManager.sol";
import "./IGlpRewardHandler.sol";

import "./console.sol";

interface IWater {
    function lend(uint256 _amount) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external returns (bool);

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfUSDC() external view returns (uint256);

    function increaseTotalUSDC(uint256 amount) external;
}

contract VodkaV1 is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    address public keeper;

    struct UserInfo {
        address user; // user that created the position
        uint256 deposit; // total amount of deposit
        uint256 leverage; // leverage used
        uint256 position; // position size
        uint256 price; // glp price
        bool liquidated; // true if position was liquidated
        uint256 closedPositionValue; // value of position when closed
        address liquidator; //address of the liquidator
        uint256 closePNL;
        uint256 leverageAmount;
        uint256 positionId;
        bool closed;
    }

    struct FeeConfiguration {
        address feeReceiver;
        uint256 withdrawalFee;
        address waterFeeReceiver;
        uint256 liquidatorsRewardPercentage;
        uint256 fixedFeeSplit;
    }

    struct Datas {
        uint256 withdrawableShares;
        uint256 profits;
        bool inFull;
        bool success;
        uint256 leverageUserProfits;
    }

    struct StrategyAddresses {
        address USDC;
        address water;
        address rewardRouterV2;
        address glp;
        address stakedGlpTracker;
        address feeGlpTracker;
        address glpManager;
        address glpRewardHandler;
        address Vault;
        address rewardVault;
        address MasterChef;
        address KyberRouter;
        address WETH;
    }

    struct SwapDescriptionV2 {
        IERC20Upgradeable srcToken;
        IERC20Upgradeable dstToken;
        address[] srcReceivers; // transfer src token to these addresses, default
        uint256[] srcAmounts;
        address[] feeReceivers;
        uint256[] feeAmounts;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    struct SwapExecutionParams {
        address callTarget; // call this address
        address approveTarget; // approve this address if _APPROVE_FUND set
        bytes targetData;
        SwapDescriptionV2 generic;
        bytes clientData;
    }

    FeeConfiguration public feeConfiguration;
    StrategyAddresses public strategyAddresses;
    address[] public allUsers;

    uint256 public MCPID;
    uint256 public MAX_BPS;
    uint256 public MAX_LEVERAGE;
    uint256 public MIN_LEVERAGE;

    uint256 public constant DENOMINATOR = 1_000;
    uint256 public constant DECIMAL = 1e18;

    mapping(address => UserInfo[]) public userInfo;
    mapping(address => bool) public allowedSenders;
    mapping(address => bool) public burner;
    mapping(address => bool) private isUser;
    mapping(address => uint256) public userTimelock;
    mapping(address => bool) private allowedClosers;
    mapping(address => bool) private isWhitelistedAsset;
    mapping(address => mapping(uint256 => bool)) public closePositionRequest;
    mapping(address => mapping(uint256 => uint256)) public closePositionAmount;

    uint256[50] private __gaps;
    uint256 public liquidationThreshold;
    uint256 public mFeePercent;
    address public mFeeReceiver;

    struct CloseData {
        uint256 toLeverageUser;
        uint256 waterProfits;
        uint256 mFee;
        uint256 waterRepayment;
    }

    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < userInfo[user].length, "VODKA: positionID is not valid");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    modifier onlyBurner() {
        require(burner[msg.sender], "Not allowed to burn");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == keeper, "Not keeper");
        _;
    }

    /** --------------------- Event --------------------- */
    event RewardRouterContractChanged(address newVault, address glpRewardHandler);
    event Deposit(address indexed depositer, uint256 depositTokenAmount, uint256 createdAt, uint256 glpAmount);
    event Withdraw(
        address indexed user,
        uint256 amount,
        uint256 time,
        uint256 glpAmount,
        uint256 profits,
        uint256 glpprice
    );
    event ProtocolFeeChanged(
        address newFeeReceiver,
        uint256 newWithdrawalFee,
        address newWaterFeeReceiver,
        uint256 liquidatorsRewardPercentage,
        uint256 fixedFeeSplit
    );

    event SetAllowedClosers(address indexed closer, bool allowed);
    event SetAllowedSenders(address indexed sender, bool allowed);
    event SetBurner(address indexed burner, bool allowed);
    event UpdateMCAndPID(address indexed newMC, uint256 mcpPid);
    event UpdateMaxAndMinLeverage(uint256 maxLeverage, uint256 minLeverage);
    event OpenRequest(address indexed user, uint256 amountAfterFee);
    event RequestFulfilled(address indexed user, uint256 openAmount, uint256 closedAmount);
    event SetAssetWhitelist(address indexed asset, bool isWhitelisted);
    event Harvested(bool gmx, bool esgmx, bool glp, bool vesting);
    event Liquidated(
        address indexed user,
        uint256 indexed positionId,
        address liquidator,
        uint256 amount,
        uint256 reward
    );
    event ETHHarvested(uint256 amount);
    event SetManagementFee(uint256 indexed mFeePercent, address indexed mFeeReceiver);


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdc,
        address _water,
        address _rewardRouterV2,
        address _vault,
        address _rewardsVault
    ) external initializer {
        require(
            _usdc != address(0) && _water != address(0) && _rewardRouterV2 != address(0) && _vault != address(0),
            "Zero address"
        );

        strategyAddresses.USDC = _usdc;
        strategyAddresses.water = _water;
        strategyAddresses.rewardRouterV2 = _rewardRouterV2;
        strategyAddresses.Vault = _vault;
        strategyAddresses.rewardVault = _rewardsVault;
        strategyAddresses.glp = IRewardRouterV2(_rewardRouterV2).glp();
        strategyAddresses.stakedGlpTracker = IRewardRouterV2(_rewardRouterV2).stakedGlpTracker();
        strategyAddresses.feeGlpTracker = IRewardRouterV2(_rewardRouterV2).feeGlpTracker();
        strategyAddresses.glpManager = IRewardRouterV2(_rewardRouterV2).glpManager();
        strategyAddresses.WETH = IRewardRouterV2(_rewardRouterV2).weth();

        MAX_BPS = 100_000;
        MAX_LEVERAGE = 10_000;
        MIN_LEVERAGE = 2_000;

        __Ownable_init();
        __Pausable_init();
        __ERC20_init("VODKA-POD", "V1POD");
    }

    /** ----------- Change onlyOwner functions ------------- */

    //MC or any other whitelisted contracts
    function setAllowed(address _sender, bool _allowed) public onlyOwner zeroAddress(_sender) {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setMFeePercent(uint256 _mFeePercent, address _mFeeReceiver) external onlyOwner {
        require(_mFeePercent <= 10000, "Invalid");
        mFeeReceiver = _mFeeReceiver;
        mFeePercent = _mFeePercent;
        emit SetManagementFee(_mFeePercent, _mFeeReceiver);
    }

    function setAssetWhitelist(address _asset, bool _status) public onlyOwner {
        isWhitelistedAsset[_asset] = _status;
        emit SetAssetWhitelist(_asset, _status);
    }

    function setCloser(address _closer, bool _allowed) public onlyOwner zeroAddress(_closer) {
        allowedClosers[_closer] = _allowed;
        emit SetAllowedClosers(_closer, _allowed);
    }

    function setBurner(address _burner, bool _allowed) public onlyOwner zeroAddress(_burner) {
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setMaxAndMinLeverage(uint256 _maxLeverage, uint256 _minLeverage) public onlyOwner {
        require(_maxLeverage >= _minLeverage, "Max < Min");
        MAX_LEVERAGE = _maxLeverage;
        MIN_LEVERAGE = _minLeverage;
        emit UpdateMaxAndMinLeverage(_maxLeverage, _minLeverage);
    }

    function setProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFee,
        address _waterFeeReceiver,
        uint256 _liquidatorsRewardPercentage,
        uint256 _fixedFeeSplit
    ) external onlyOwner zeroAddress(_feeReceiver) zeroAddress(_waterFeeReceiver) {
        feeConfiguration.feeReceiver = _feeReceiver;
        feeConfiguration.withdrawalFee = _withdrawalFee;
        feeConfiguration.waterFeeReceiver = _waterFeeReceiver;
        feeConfiguration.liquidatorsRewardPercentage = _liquidatorsRewardPercentage;
        feeConfiguration.fixedFeeSplit = _fixedFeeSplit;

        emit ProtocolFeeChanged(
            _feeReceiver,
            _withdrawalFee,
            _waterFeeReceiver,
            _liquidatorsRewardPercentage,
            _fixedFeeSplit
        );
    }

    function setStrategyContracts(
        address _rewardRouterV2,
        address _vault,
        address _rewardVault,
        address _glpRewardHandler,
        address _water
    ) external onlyOwner zeroAddress(_rewardRouterV2) zeroAddress(_vault) zeroAddress(_rewardVault) {
        strategyAddresses.rewardRouterV2 = _rewardRouterV2;
        strategyAddresses.Vault = _vault;
        strategyAddresses.rewardVault = _rewardVault;
        strategyAddresses.glp = IRewardRouterV2(_rewardRouterV2).glp();
        strategyAddresses.stakedGlpTracker = IRewardRouterV2(_rewardRouterV2).stakedGlpTracker();
        strategyAddresses.feeGlpTracker = IRewardRouterV2(_rewardRouterV2).feeGlpTracker();
        strategyAddresses.glpManager = IRewardRouterV2(_rewardRouterV2).glpManager();
        strategyAddresses.glpRewardHandler = _glpRewardHandler;
        strategyAddresses.water = _water;

        emit RewardRouterContractChanged(_rewardRouterV2, _glpRewardHandler);
    }

    function setStrategyAddresses(
        address _masterChef,
        uint256 _mcPid,
        address _keeper,
        address _kyberRouter
    ) public onlyOwner {
        strategyAddresses.KyberRouter = _kyberRouter;
        strategyAddresses.MasterChef = _masterChef;
        keeper = _keeper;
        MCPID = _mcPid;
    }

    function setLiquidationThreshold(uint256 _threshold) public onlyOwner {
        liquidationThreshold = _threshold;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function transferEsGMX(address _destination) public onlyOwner {
        IRewardRouterV2(strategyAddresses.rewardVault).signalTransfer(_destination);
    }

    /** ----------- View functions ------------- */

    function getGLPPrice(bool _maximise) public view returns (uint256) {
        uint256 price_In_Precision = IGlpManager(strategyAddresses.glpManager).getPrice(_maximise);
        // glp is 18 decimals https://arbiscan.io/address/0x4277f8f2c384827b5273592ff7cebd9f2c1ac258#readContract#F6
        // price precision is 30 decimals https://arbiscan.io/address/0x3963ffc9dff443c2a94f21b129d429891e32ec18#readContract#F4
        return (price_In_Precision * (10 ** 18)) / 10 ** 30;
    }

    function getAllUsers() public view returns (address[] memory) {
        return allUsers;
    }

    function getTotalNumbersOfOpenPositionBy(address _user) public view returns (uint256) {
        return userInfo[_user].length;
    }

    function getAggregatePosition(address _user) public view returns (uint256) {
        uint256 aggregatePosition;
        for (uint256 i = 0; i < userInfo[_user].length; i++) {
            UserInfo memory _userInfo = userInfo[_user][i];
            if (!_userInfo.liquidated) {
                aggregatePosition += userInfo[_user][i].position;
            }
        }
        return aggregatePosition;
    }

    function getUpdatedDebt(
        uint256 _positionID,
        address _user
    ) public view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt) {
        UserInfo memory _userInfo = userInfo[_user][_positionID];
        if (_userInfo.closed || _userInfo.liquidated) return (0, 0, 0);

        uint256 previousValueInUSDC;
        // Get the current position and previous value in USDC using the `getCurrentPosition` function
        (currentPosition, previousValueInUSDC) = getCurrentPosition(_positionID, _userInfo.position, _user);
        uint256 leverage = _userInfo.leverageAmount;

        uint256 profitOrLoss;
        uint256 rewardSplitToWater;
        uint256 owedToWater;

        if (currentPosition > previousValueInUSDC) {
            profitOrLoss = currentPosition - previousValueInUSDC;
            // Call the `_getProfitSplit` function to calculate the reward split to water and the amount owed to water
            (rewardSplitToWater, ,) = _getProfitSplit(profitOrLoss, _userInfo.leverage);
            // The amount owed to water is the user's leverage amount plus the reward split to water
            owedToWater = leverage + rewardSplitToWater;
        } else {
            owedToWater = leverage;
        }
        // Calculate the current DTV by dividing the amount owed to water by the current position
        currentDTV = owedToWater.mulDiv(DECIMAL, currentPosition);
        // Return the current DTV, current position, and amount owed to water
        return (currentDTV, currentPosition, owedToWater);
    }

    function getCurrentPosition(
        uint256 _positionID,
        uint256 _shares,
        address _user
    ) public view returns (uint256 currentPosition, uint256 previousValueInUSDC) {
        UserInfo memory _userInfo = userInfo[_user][_positionID];
        uint256 userShares = (_shares == 0) ? _userInfo.position : _shares;
        uint256 userShareAfterFee = _removeVaultSwapFees(strategyAddresses.USDC, userShares);
        return (
            _convertGLPToUSDC(userShareAfterFee, getGLPPrice(true)),
            _convertGLPToUSDC(userShares, _userInfo.price)
        );
    }

    /** ----------- User functions ------------- */

    function handleAndCompoundRewards() public returns (uint256) {
        uint256 balanceBefore = IERC20Upgradeable(strategyAddresses.WETH).balanceOf(address(this));
        IRewardRouterV2(strategyAddresses.rewardVault).handleRewards(true, true, true, true, true, true, false);

        uint256 balanceAfter = IERC20Upgradeable(strategyAddresses.WETH).balanceOf(address(this));
        uint256 balanceDiff = balanceAfter - balanceBefore;
        if (balanceDiff > 0) {
            (uint256 toOwner, uint256 toWater, uint256 toVodkaUsers) = IGlpRewardHandler(
                strategyAddresses.glpRewardHandler
            ).getVodkaSplit(balanceDiff);
            IERC20Upgradeable(strategyAddresses.WETH).transfer(strategyAddresses.glpRewardHandler, balanceDiff);

            IGlpRewardHandler(strategyAddresses.glpRewardHandler).distributeGlp(toVodkaUsers);
            IGlpRewardHandler(strategyAddresses.glpRewardHandler).distributeRewards(toOwner, toWater);
            emit ETHHarvested(toVodkaUsers);
            return toVodkaUsers;
        }

        return 0;
    }

    function openPosition(
        uint256 _amount,
        uint256 _leverage,
        bytes calldata _data,
        bool _swapSimple,
        address _inputAsset
    ) external whenNotPaused {
        require(_leverage >= MIN_LEVERAGE && _leverage <= MAX_LEVERAGE, "VODKA: Invalid leverage");
        require(_amount > 0, "VODKA: amount must be greater than zero");

        IGlpRewardHandler(strategyAddresses.glpRewardHandler).claimETHRewards(msg.sender);

        IERC20Upgradeable(_inputAsset).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 amount;
        address asset;
        // swap to USDC if input is not USDC and it not whitelisted on GMX
        if (_inputAsset != strategyAddresses.USDC) {
            require(isWhitelistedAsset[_inputAsset], "VODKA: Invalid assets choosen");
            amount = _swap(_amount, _data, _swapSimple, true, _inputAsset);
            asset = strategyAddresses.USDC;
        } else {
            amount = _amount;
            asset = _inputAsset;
        }
        // get leverage amount
        uint256 leveragedAmount = amount.mulDiv(_leverage, DENOMINATOR) - amount;
        bool status = IWater(strategyAddresses.water).lend(leveragedAmount);
        require(status, "Water: Lend failed");
        // add leverage amount to amount
        uint256 xAmount = amount + leveragedAmount;

        IERC20Upgradeable(asset).safeIncreaseAllowance(strategyAddresses.glpManager, xAmount);
        uint256 glpAmount = IRewardRouterV2(strategyAddresses.rewardRouterV2).mintAndStakeGlp(asset, xAmount, 0, 0);

        UserInfo memory _userInfo = UserInfo({
            user: msg.sender,
            deposit: amount,
            leverage: _leverage,
            position: glpAmount,
            price: getGLPPrice(true),
            liquidated: false,
            closedPositionValue: 0,
            liquidator: address(0),
            closePNL: 0,
            leverageAmount: leveragedAmount,
            positionId: userInfo[msg.sender].length,
            closed: false
        });

        //frontend helper to fetch all users and then their userInfo
        if (isUser[msg.sender] == false) {
            isUser[msg.sender] = true;
            allUsers.push(msg.sender);
        }

        userInfo[msg.sender].push(_userInfo);
        // mint gmx shares to user
        _mint(msg.sender, glpAmount);

        IGlpRewardHandler(strategyAddresses.glpRewardHandler).setDebtRecordWETH(msg.sender);
        emit Deposit(msg.sender, amount, block.timestamp, glpAmount);
    }

    function closePosition(
        uint256 _positionID,
        uint256 _assetPercent,
        address _user,
        bool _sameSwap
    ) external InvalidID(_positionID, _user) nonReentrant {
        // Retrieve user information for the given position
        UserInfo storage _userInfo = userInfo[_user][_positionID];
        // Validate that the position is not liquidated
        require(!_userInfo.liquidated, "VODKA: position is liquidated");
        require(_assetPercent <= DENOMINATOR, "VODKA: invalid share percent");
        // Validate that the position has enough shares to close
        require(_userInfo.position > 0, "VODKA: position is not enough to close");
        require(allowedClosers[msg.sender] || msg.sender == _userInfo.user, "VODKA: not allowed to close position");

        IGlpRewardHandler(strategyAddresses.glpRewardHandler).claimETHRewards(_user);

        // Struct to store intermediate data during calculation
        Datas memory data;
        CloseData memory closeData;
        // this function will return withdrawable shares, profits and boolean to check if user is withdrawing in full
        (data.withdrawableShares, data.profits, data.inFull) = _convertToShares(_positionID, _assetPercent, _user);
        // check for liquidation
        (uint256 currentDTV, , uint256 fulldebtValue) = getUpdatedDebt(_positionID, _user);

        if (currentDTV >= (liquidationThreshold /* 95 * 1e17**/) / 10) {
            revert("Wait for liquidation");
        }

        uint256 returnedValue;
        if (data.inFull) {
            _handlePODToken(_user, _userInfo.position);
            returnedValue = _withdrawAndUnstakeGLP(_userInfo.position);
        } else {
            _handlePODToken(_user, data.withdrawableShares);
            returnedValue = _withdrawAndUnstakeGLP(data.withdrawableShares);
        }

        // if user is not withdrawing in full then calculate debt and after loan payment
        (closeData.waterProfits, closeData.mFee, data.leverageUserProfits) = _getProfitSplit(data.profits, _userInfo.leverage);
        if (!data.inFull) {

            uint256 userShares = ((returnedValue - data.profits) * 1e3) / _userInfo.leverage;
            uint256 waterShares = (returnedValue - data.profits) - userShares;

            _mFeePayment(closeData.mFee);

            closeData.toLeverageUser = userShares + data.leverageUserProfits;
            _userInfo.position -= data.withdrawableShares;

            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, waterShares + closeData.waterProfits);
            data.success = IWater(strategyAddresses.water).repayDebt(waterShares, waterShares + closeData.waterProfits);
            _userInfo.leverageAmount -= waterShares;
            _userInfo.price = getGLPPrice(true);
        } else {
            if (returnedValue < fulldebtValue) {
                _userInfo.liquidator = msg.sender;
                _userInfo.liquidated = true;
                closeData.waterRepayment = returnedValue;
            } else {
                // already added water profits to fulldebtValue
                closeData.waterRepayment = fulldebtValue;
                // since we have water profits already added to fulldebtValue, we need to subtract it again from returnedValue
                closeData.toLeverageUser = (returnedValue - closeData.waterRepayment) - closeData.mFee;

                _mFeePayment(closeData.mFee);
                // set position to 0 when user is withdrawing in full to mitigate rounding errors
                _userInfo.closed = true;
            }

            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, closeData.waterRepayment);
            data.success = IWater(strategyAddresses.water).repayDebt(_userInfo.leverageAmount, closeData.waterRepayment);
            _userInfo.position = 0;
            _userInfo.leverageAmount = 0;
        }

        require(data.success, "Water: Repay failed");

        if (_userInfo.liquidated) {
            return;
        }

        // take protocol fee
        uint256 amountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = closeData.toLeverageUser.mulDiv(feeConfiguration.withdrawalFee, MAX_BPS);
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(feeConfiguration.feeReceiver, fee);
            amountAfterFee = closeData.toLeverageUser - fee;
        } else {
            amountAfterFee = closeData.toLeverageUser;
        }

        // if user is withdrawing USDC then transfer amount after fee to user else
        // make a withdrawal request for user to withdraw asset and emmit OpenRequest event
        if (_sameSwap) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(_user, amountAfterFee);
        } else {
            closePositionAmount[_user][_positionID] = amountAfterFee;
            closePositionRequest[_user][_positionID] = true;
            emit OpenRequest(_user, amountAfterFee);
        }

        _userInfo.closedPositionValue += returnedValue;
        _userInfo.closePNL += amountAfterFee;

        IGlpRewardHandler(strategyAddresses.glpRewardHandler).setDebtRecordWETH(_user);
        emit Withdraw(
            _user,
            amountAfterFee,
            block.timestamp,
            data.withdrawableShares,
            data.leverageUserProfits,
            getGLPPrice(true)
        );
    }

    function fulfilledRequestSwap(
        uint256 _positionID,
        bytes calldata _data,
        bool _swapSimple,
        address _outputAsset
    ) external nonReentrant {
        // Retrieve the amount after fee from the `closePositionAmount` mapping
        uint256 amountAfterFee = closePositionAmount[msg.sender][_positionID];
        require(isWhitelistedAsset[_outputAsset], "VODKA: Invalid assets choosen");
        require(amountAfterFee > 0, "VODKA: position is not enough to close");
        require(closePositionRequest[msg.sender][_positionID], "VODKA: Close only open position");
        closePositionAmount[msg.sender][_positionID] = 0;
        uint256 amountOut = _swap(amountAfterFee, _data, _swapSimple, false, _outputAsset);
        IERC20Upgradeable(_outputAsset).safeTransfer(msg.sender, amountOut);
        emit RequestFulfilled(msg.sender, amountAfterFee, amountOut);
    }

    function liquidatePosition(uint256 _positionId, address _user) external nonReentrant {
        UserInfo storage _userInfo = userInfo[_user][_positionId];
        require(!_userInfo.liquidated, "VODKA: Already liquidated");
        require(_userInfo.user != address(0), "VODKA: liquidation request does not exist");
        (uint256 currentDTV, , ) = getUpdatedDebt(_positionId, _user);
        require(currentDTV >= (95 * 1e17) / 10, "Liquidation Threshold Has Not Reached");

        IGlpRewardHandler(strategyAddresses.glpRewardHandler).claimETHRewards(_user);

        uint256 position = _userInfo.position;

        _handlePODToken(_user, position);

        uint256 outputAmount = _withdrawAndUnstakeGLP(_userInfo.position);

        _userInfo.liquidator = msg.sender;
        _userInfo.liquidated = true;
        _userInfo.position = 0;

        uint256 liquidatorReward = outputAmount.mulDiv(feeConfiguration.liquidatorsRewardPercentage, MAX_BPS);
        uint256 amountAfterLiquidatorReward = outputAmount - liquidatorReward;

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(
            strategyAddresses.water,
            amountAfterLiquidatorReward
        );
        IWater(strategyAddresses.water).repayDebt(_userInfo.leverageAmount, amountAfterLiquidatorReward);
        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(msg.sender, liquidatorReward);

        IGlpRewardHandler(strategyAddresses.glpRewardHandler).setDebtRecordWETH(_user);

        emit Liquidated(_user, _positionId, msg.sender, outputAmount, liquidatorReward);
    }

    /** ----------- Token functions ------------- */

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        require(allowedSenders[from] || allowedSenders[to] || allowedSenders[spender], "ERC20: transfer not allowed");
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address ownerOf = _msgSender();
        require(allowedSenders[ownerOf] || allowedSenders[to], "ERC20: transfer not allowed");
        _transfer(ownerOf, to, amount);
        return true;
    }

    function burn(uint256 amount) public virtual override onlyBurner {
        _burn(_msgSender(), amount);
    }

    /** ----------- Internal functions ------------- */

    function _mFeePayment(uint256 _amount) internal {
        if (_amount > 0) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(mFeeReceiver, _amount);
        }
    }

    function _getProfitSplit(uint256 _profit, uint256 _leverage) internal view returns (uint256, uint256, uint256) {
        if (_profit == 0) {
            return (0, 0, 0);
        }
        uint256 split = (feeConfiguration.fixedFeeSplit * _leverage + (feeConfiguration.fixedFeeSplit * 10000)) / 100;
        uint256 toWater = (_profit * split) / 10000;
        uint256 mFee = (_profit * mFeePercent) / 10000;
        uint256 toVodkaUser = _profit - (toWater + mFee);

        return (toWater, mFee, toVodkaUser);
    }

    function _convertToShares(
        uint256 _positionId,
        uint256 _assetPercent,
        address _user
    ) internal view returns (uint256, uint256, bool) {
        UserInfo memory _userInfo = userInfo[_user][_positionId];
        uint256 convertUserPositionToAssets = _convertGLPToUSDC(_userInfo.position, _userInfo.price);
        uint256 profit = _getProfitState(_positionId, _user);

        uint256 percent;
        bool inFull;
        // Check if the asset percent is 0 or greater than or equal to 90%. user withdrawal must be in full in this case
        if (_assetPercent == 0 || _assetPercent >= 900) {
            percent = DENOMINATOR;
            inFull = true;
        } else {
            percent = _assetPercent;
        }
        // Calculate the amount of USDC to withdraw based on the withdrawal percentage
        uint256 amountToWithdraw = convertUserPositionToAssets.mulDiv(percent, DENOMINATOR);
        // Convert the USDC amount back to withdrawable shares using the user's position price and return the profit and inFull flag
        return (_convertUSDCToGLP(amountToWithdraw + profit, getGLPPrice(true)), profit, inFull);
    }

    function _getProfitState(uint256 _positionId, address _user) internal view returns (uint256 profit) {
        (uint256 currentValues, uint256 previousValue) = getCurrentPosition(_positionId, 0, _user);
        if (currentValues > previousValue) {
            profit = currentValues - previousValue;
        }
    }

    function _removeVaultSwapFees(address _token, uint256 _usdgAMount) internal view returns (uint256) {
        // ref: https://arbiscan.io/address/0x489ee077994b6658eafa855c308275ead8097c4a#readContract#F22
        uint256 getVaultFeeBasisPoints = IVault(strategyAddresses.Vault).getFeeBasisPoints(
            _token,
            _usdgAMount,
            IVault(strategyAddresses.Vault).mintBurnFeeBasisPoints(),
            IVault(strategyAddresses.Vault).taxBasisPoints(),
            false
        );
        // ref: https://arbiscan.io/address/0x489ee077994b6658eafa855c308275ead8097c4a#readContract#F35
        uint256 getVaultRedemptionAmount = IVault(strategyAddresses.Vault).getRedemptionAmount(_token, _usdgAMount);

        // uint256 public constant BASIS_POINTS_DIVISOR = 10_000;
        // @note base point is a constant variable with value 10_000
        // fee from vault is calculatted based on the below
        // _amount.mul(BASIS_POINTS_DIVISOR.sub(_feeBasisPoints)).div(BASIS_POINTS_DIVISOR);
        // _amount = vault redemption amount
        // _feeBasisPoints = vault fee basis points
        return getVaultRedemptionAmount.mulDiv(10_000 - getVaultFeeBasisPoints, 10_000);
    }

    function _convertGLPToUSDC(uint256 _amount, uint256 _glpPrice) internal pure returns (uint256) {
        return _amount.mulDiv(_glpPrice, 10 ** 18);
    }

    function _convertUSDCToGLP(uint256 _amount, uint256 _glpPrice) internal pure returns (uint256) {
        return _amount.mulDiv(10 ** 18, _glpPrice);
    }

    function _swap(
        uint256 _amount,
        bytes calldata _data,
        bool _swapSimple,
        bool _swapToUnderlying,
        address _asset
    ) internal returns (uint256) {
        SwapDescriptionV2 memory desc;

        if (_swapSimple) {
            // 0x8af033fb -> swapSimpleMode
            // Decode the data for a swap in simple mode
            (, SwapDescriptionV2 memory des, , ) = abi.decode(_data[4:], (address, SwapDescriptionV2, bytes, bytes));
            desc = des;
        } else {
            // 0x59e50fed -> swapGeneric
            // 0xe21fd0e9 -> swap
            // Decode the data for a swap in generic mode
            SwapExecutionParams memory des = abi.decode(_data[4:], (SwapExecutionParams));
            desc = des.generic;
        }

        require(desc.dstReceiver == address(this), "Receiver must be this contract");
        require(desc.amount == _amount, "Swap amounts must match");
        uint256 assetBalBefore;
        uint256 assetBalAfter;
        bool succ;
        // Perform the token swap depending on the `_swapToUnderlying` parameter
        if (_swapToUnderlying) {
            // Swap from Whitelisted token to the underlying asset (USDC)
            require(
                desc.dstToken == IERC20Upgradeable(strategyAddresses.USDC),
                "Output must be the same as _inputAsset"
            );
            require(desc.srcToken == IERC20Upgradeable(_asset), "Input must be the same as _inputAsset");
            assetBalBefore = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));
            IERC20Upgradeable(_asset).safeIncreaseAllowance(strategyAddresses.KyberRouter, desc.amount);
            (succ, ) = address(strategyAddresses.KyberRouter).call(_data);
            assetBalAfter = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));
        } else {
            // Swap from the underlying asset (USDC) to output token
            require(desc.dstToken == IERC20Upgradeable(_asset), "Output must be the same as _inputAsset");
            require(
                desc.srcToken == IERC20Upgradeable(strategyAddresses.USDC),
                "Input must be the same as _inputAsset"
            );
            assetBalBefore = IERC20Upgradeable(_asset).balanceOf(address(this));
            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.KyberRouter, desc.amount);
            (succ, ) = address(strategyAddresses.KyberRouter).call(_data);
            assetBalAfter = IERC20Upgradeable(_asset).balanceOf(address(this));
        }
        require(succ, "Swap failed");
        // Check that the token balance after the swap increased
        require(assetBalAfter > assetBalBefore, "VODKA: Swap failed");
        // Return the amount of tokens received after the swap
        return (assetBalAfter - assetBalBefore);
    }

    function _withdrawAndUnstakeGLP(uint256 _shares) internal returns (uint256) {
        IERC20Upgradeable(strategyAddresses.stakedGlpTracker).safeIncreaseAllowance(
            strategyAddresses.rewardRouterV2,
            _shares
        );

        uint256 tokenOut = IRewardRouterV2(strategyAddresses.rewardRouterV2).unstakeAndRedeemGlp(
            strategyAddresses.USDC,
            _shares,
            0,
            address(this)
        );
        return tokenOut;
    }

    function _handlePODToken(address _user, uint256 position) internal {
        if (strategyAddresses.MasterChef != address(0)) {
            uint256 userBalance = balanceOf(_user);
            if (userBalance >= position) {
                _burn(_user, position);
            } else {
                _burn(_user, userBalance);
                uint256 remainingPosition = position - userBalance;
                IMasterChef(strategyAddresses.MasterChef).unstakeAndLiquidate(MCPID, _user, remainingPosition);
            }
        } else {
            _burn(_user, position);
        }
    }
}

