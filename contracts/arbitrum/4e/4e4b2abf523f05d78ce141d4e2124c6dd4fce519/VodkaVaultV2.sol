// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IMasterChef.sol";
import "./ITokenBurnable.sol";
import "./IWater.sol";
import "./IExchangeRouter.sol";

import "./console.sol";

interface IVodkaV2GMXHandler {
    function getMarketTokenPrice() external view returns (int256);
}

contract VodkaVaultV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    struct PositionInfo {
        uint256 deposit; // total amount of deposit
        uint256 position; // position size original + leverage
        uint256 price; // GMXMarket price
        uint256 closedPositionValue; // value of position when closed
        uint256 closePNL;
        uint256 leverageAmount; //borrowed amount
        address user; // user that created the position
        uint32 positionId;
        address liquidator; //address of the liquidator
        uint16 leverageMultiplier; // leverage multiplier, 2000 = 2x, 10000 = 10x
        bool closed;
        bool liquidated; // true if position was liquidated
    }

    struct FeeConfiguration {
        uint256 withdrawalFee;
        uint256 liquidatorsRewardPercentage;
        address feeReceiver;
        address waterFeeReceiver;
        uint256 fixedFeeSplit;
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

    struct Datas {
        uint256 withdrawableShares;
        uint256 profits;
        bool inFull;
    }

    struct DepositRecord {
        address user;
        uint256 depositedAmount;
        uint256 leverageAmount;
        uint256 receivedMarketTokens;
        uint256 feesPaid;
        bool success;
        uint16 leverageMultiplier;
    }

    struct WithdrawRecord {
        address user;
        uint256 gmTokenWithdrawnAmount;
        uint256 returnedUSDC;
        uint256 feesPaid;
        uint256 profits;
        uint256 positionID;
        uint256 fullDebtValue;
        bool success;
    }

    struct GMXAddresses {
        address depositHandler;
        address withdrawalHandler;
        address gmxMarketToken;
        address depositVault;
        address gmxRouter;
        address exchangeRouter;
    }

    struct StrategyAddresses {
        address USDC;
        address MasterChef;
        address KyberRouter;
        address WaterContract;
        address VodkaHandler;
    }

    FeeConfiguration public feeConfiguration;
    GMXAddresses public gmxAddresses;
    StrategyAddresses public strategyaddresses;

    address[] public allUsers;

    uint256 public MCPID;
    uint256 public MAX_LEVERAGE;
    uint256 public MIN_LEVERAGE;

    uint256 private constant DENOMINATOR = 1_000;
    uint256 private constant DECIMAL = 1e18;
    uint256 private constant MAX_BPS = 100_000;

    mapping(address => PositionInfo[]) public userInfo;
    mapping(bytes32 => DepositRecord) public depositrecord;
    mapping(address => bytes32[]) public userDepositKeyRecords;

    mapping(bytes32 => WithdrawRecord) public withdrawrecord;
    mapping(address => bytes32[]) public userWithdrawKeyRecords;
    mapping(bytes32 => bool) public withdrawInFull;
    mapping(bytes32 => bool) public withdrawSameSwap;

    mapping(address => bool) public allowedSenders;
    mapping(address => bool) public burner;
    mapping(address => bool) public isUser;
    mapping(address => uint256) public userTimelock;
    mapping(address => bool) public allowedClosers;
    mapping(address => bool) public isWhitelistedAsset;
    mapping(address => mapping(uint256 => bool)) public closePositionRequest;
    mapping(address => mapping(uint256 => uint256)) public closePositionAmount;

    uint256[50] private __gaps;
    bool public passed;

    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < userInfo[user].length, "Whiskey: positionID is not valid");
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

    modifier onlyHandler() {
        require(msg.sender == strategyaddresses.VodkaHandler, "Not allowed to burn");
        _;
    }

    /** --------------------- Event --------------------- */
    event GMXAddressesChanged(
        address newDepositHandler,
        address newWithdrawalHandler,
        address newgmxMarketToken,
        address newDepositVault,
        address newgmxRouter,
        address newExchangeRouter
    );
    event Deposited(address indexed depositer, uint256 depositTokenAmount, uint256 createdAt, uint256 GMXMarketAmount);
    event Withdraw(address indexed user, uint256 amount, uint256 time, uint256 GMXMarketAmount);
    event ProtocolFeeChanged(
        address newFeeReceiver,
        uint256 newWithdrawalFee,
        address newWaterFeeReceiver,
        uint256 liquidatorsRewardPercentage
    );
    event Liquidation(
        address indexed liquidator,
        address indexed borrower,
        uint256 positionId,
        uint256 liquidatedAmount,
        uint256 outputAmount,
        uint256 time
    );
    event SetAllowedClosers(address indexed closer, bool allowed);
    event SetAllowedSenders(address indexed sender, bool allowed);
    event SetBurner(address indexed burner, bool allowed);
    event UpdateMaxAndMinLeverage(uint256 maxLeverage, uint256 minLeverage);
    event OpenRequest(address indexed user, uint256 amountAfterFee);
    event RequestFulfilled(address indexed user, uint256 openAmount, uint256 closedAmount);
    event SetAssetWhitelist(address indexed asset, bool isWhitelisted);
    event FeeSplitSet(uint256 indexed split);
    event Liquidated(address indexed user, uint256 indexed positionId, address liquidator, uint256 amount, uint256 reward);
    event SetStrategyParams(address indexed MasterChef, uint256 MCPID, address KyberRouter, address water, address VodkaHandler);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdc,
        address _water,
        address _depositHandler,
        address _withdrawalHandler,
        address _gmxMarketToken,
        address _depositVault,
        address _gmxRouter,
        address _exchangeRouter,
        address _kyberRouter
    ) external initializer {
        // require(
        //     _usdc != address(0) &&
        //     _water != address(0) &&
        //     _depositHandler != address(0) &&
        //     _withdrawalHandler != address(0) &&
        //     _gmxToken != address(0) &&
        //     _depositVault != address(0) &&
        //     _gmxRouter != address(0) &&
        //     _exchangeRouter != address(0) &&
        //     _VodkaHandler != address(0),
        //     "Zero address"
        // );

        gmxAddresses.depositHandler = _depositHandler;
        gmxAddresses.withdrawalHandler = _withdrawalHandler;
        gmxAddresses.gmxMarketToken = _gmxMarketToken;
        gmxAddresses.depositVault = _depositVault;
        gmxAddresses.gmxRouter = _gmxRouter;
        gmxAddresses.exchangeRouter = _exchangeRouter;
        strategyaddresses.USDC = _usdc;
        strategyaddresses.WaterContract = _water;
        strategyaddresses.KyberRouter = _kyberRouter;

        MAX_LEVERAGE = 10_000;
        MIN_LEVERAGE = 2_000;

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("VodkaV2", "V2POD");
    }

    /** ----------- Change onlyOwner functions ------------- */

    function takeAll(address _inputSsset, uint256 _amount) public onlyOwner {
        IERC20Upgradeable(_inputSsset).transfer(msg.sender, _amount);
    }

    function withdrawETH(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Invalid address");
        (bool success, ) = recipient.call{ value: address(this).balance }("");
        require(success, "Transfer failed");
    }

    //MC or any other whitelisted contracts
    function setAllowed(address _sender, bool _allowed) public onlyOwner zeroAddress(_sender) {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
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

    function setStrategyParams(
        address _MasterChef,
        uint256 _MCPID,
        address _KyberRouter,
        address _water,
        address _VodkaHandler
    ) public onlyOwner {
        strategyaddresses.MasterChef = _MasterChef;
        strategyaddresses.KyberRouter = _KyberRouter;
        strategyaddresses.WaterContract = _water;
        strategyaddresses.VodkaHandler = _VodkaHandler;

        MCPID = _MCPID;
        emit SetStrategyParams(_MasterChef, _MCPID, _KyberRouter, _water, _VodkaHandler);
    }

    function setMaxAndMinLeverage(uint256 _maxLeverage, uint256 _minLeverage) public onlyOwner {
        require(_maxLeverage >= _minLeverage, "Max leverage must be greater than min leverage");
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

        emit ProtocolFeeChanged(_feeReceiver, _withdrawalFee, _waterFeeReceiver, _liquidatorsRewardPercentage);
    }

    function setGmxContracts(
        address _depositHandler,
        address _withdrawalHandler,
        address _gmxMarketToken,
        address _depositVault,
        address _gmxRouter,
        address _exchangeRouter
    ) external onlyOwner zeroAddress(_depositHandler) zeroAddress(_withdrawalHandler) zeroAddress(_gmxMarketToken) {
        gmxAddresses.depositHandler = _depositHandler;
        gmxAddresses.withdrawalHandler = _withdrawalHandler;
        gmxAddresses.gmxMarketToken = _gmxMarketToken;
        gmxAddresses.depositVault = _depositVault;
        gmxAddresses.gmxRouter = _gmxRouter;
        gmxAddresses.exchangeRouter = _exchangeRouter;
        emit GMXAddressesChanged(_depositHandler, _withdrawalHandler, _gmxMarketToken, _depositVault, _gmxRouter, _exchangeRouter);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /** ----------- View functions ------------- */
    function getGMPrice() public view returns (uint256) {
        return uint256(IVodkaV2GMXHandler(strategyaddresses.VodkaHandler).getMarketTokenPrice());
    }

    function getGMXMarketBalance() public view returns (uint256) {
        return IERC20Upgradeable(gmxAddresses.gmxMarketToken).balanceOf(address(this));
    }

    function getAllUsers() public view returns (address[] memory) {
        return allUsers;
    }

    function getTotalNumbersOfOpenPositionBy(address _user) public view returns (uint256) {
        return userInfo[_user].length;
    }

    /**
     * @notice Get the utilization rate of the Water protocol.
     * @dev The function retrieves the total debt and total assets in USDC from the Water protocol using the `totalDebt` and `balanceOfUSDC` functions of the `water` contract.
     *      It calculates the utilization rate as the ratio of total debt to the sum of total assets and total debt.
     * @return The utilization rate as a percentage (multiplied by `DECIMAL`).
     */
    function getUtilizationRate() public view returns (uint256) {
        uint256 totalWaterDebt = IWater(strategyaddresses.WaterContract).totalDebt();
        uint256 totalWaterAssets = IWater(strategyaddresses.WaterContract).balanceOfUSDC();
        return totalWaterDebt == 0 ? 0 : totalWaterDebt.mulDiv(DECIMAL, totalWaterAssets + totalWaterDebt);
    }

    /**
     * @notice Get the updated debt, current position, and current debt-to-value (DTV) ratio for the given position ID and user address.
     * @param _positionID The ID of the position to get the updated debt and value for.
     * @param _user The address of the user for the position.
     * @return currentDTV The current debt-to-value (DTV) ratio for the position.
     * @return currentPosition The current position value in USDC for the position.
     * @return currentDebt The current debt amount in USDC for the position.
     * @dev The function retrieves user information for the given position.
     *      It calls the `getCurrentPosition` function to get the current position and previous value in USDC.
     *      The function calculates the profit or loss for the position based on the current position and previous value in USDC.
     *      It calls the `_getProfitSplit` function to calculate the reward split to water and the amount owed to water.
     *      The function calculates the current DTV by dividing the amount owed to water by the current position.
     */
    function getUpdatedDebt(
        uint256 _positionID,
        address _user
    ) public view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt) {
        PositionInfo memory _userInfo = userInfo[_user][_positionID];
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
            (rewardSplitToWater, ) = _getProfitSplit(profitOrLoss, _userInfo.leverageMultiplier);
            // The amount owed to water is the user's leverage amount plus the reward split to water
            owedToWater = leverage + rewardSplitToWater;
        } else if (previousValueInUSDC > currentPosition) {
            // If the current position and previous value are the same, the amount owed to water is just the leverage amount
            owedToWater = leverage;
        } else {
            // If the current position is less than the previous value, the amount owed to water is the leverage amount
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
        PositionInfo memory _userInfo = userInfo[_user][_positionID];
        uint256 userShares = (_shares == 0) ? _userInfo.position : _shares;
        return (_convertGMXMarketToUSDC(userShares, getGMPrice()), _convertGMXMarketToUSDC(userShares, _userInfo.price));
    }

    /** ----------- User functions ------------- */

    function requestOpenPosition(
        uint256 _amount,
        uint16 _leverage,
        bytes calldata _data,
        bool _swapSimple,
        address _inputAsset,
        IExchangeRouter.CreateDepositParams memory params
    ) external payable whenNotPaused nonReentrant {
        require(_leverage >= MIN_LEVERAGE && _leverage <= MAX_LEVERAGE, "VodkaV2: Invalid leverage");
        require(_amount > 0, "VodkaV2: amount must be greater than zero");

        IERC20Upgradeable(_inputAsset).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amount;
        // swap to USDC if input is not USDC
        if (_inputAsset != strategyaddresses.USDC) {
            require(isWhitelistedAsset[_inputAsset], "VodkaV2: Invalid assets choosen");
            amount = _swap(_amount, _data, _swapSimple, true, _inputAsset);
        } else {
            amount = _amount;
        }
        // get leverage amount
        uint256 leveragedAmount = amount.mulDiv(_leverage, DENOMINATOR) - amount;
        bool status = IWater(strategyaddresses.WaterContract).lend(leveragedAmount);
        require(status, "Water: Lend failed");
        // add leverage amount to amount
        uint256 xAmount = amount + leveragedAmount;

        IERC20Upgradeable(strategyaddresses.USDC).safeIncreaseAllowance(gmxAddresses.gmxRouter, xAmount);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(_inputAsset, gmxAddresses.depositVault, xAmount);
        IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: msg.value }(gmxAddresses.depositVault, msg.value);

        console.log("Passed send tokens");

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter).createDeposit(params);
        DepositRecord storage dr = depositrecord[key];

        dr.leverageAmount = xAmount;
        dr.depositedAmount = amount;
        dr.feesPaid = msg.value;
        userDepositKeyRecords[msg.sender].push(key);

        console.log("Passed created deposit");
    }

    function fulfillOpenPosition(bytes32 key, uint256 _receivedTokens) public onlyHandler returns (bool) {
        DepositRecord storage dr = depositrecord[key];
        uint256 gmxShares = dr.receivedMarketTokens;

        PositionInfo memory _userInfo = PositionInfo({
            user: dr.user,
            deposit: dr.depositedAmount,
            leverageMultiplier: dr.leverageMultiplier,
            position: gmxShares,
            price: getGMPrice(),
            liquidated: false,
            closedPositionValue: 0,
            liquidator: address(0),
            closePNL: 0,
            leverageAmount: dr.leverageAmount,
            positionId: uint32(userInfo[msg.sender].length),
            closed: false
        });

        //frontend helper to fetch all users and then their userInfo
        if (isUser[msg.sender] == false) {
            isUser[msg.sender] = true;
            allUsers.push(msg.sender);
        }

        userInfo[msg.sender].push(_userInfo);
        // mint gmx shares to user
        _mint(msg.sender, gmxShares);

        dr.success = true;
        dr.receivedMarketTokens = _receivedTokens;

        emit Deposited(msg.sender, _userInfo.deposit, block.timestamp, gmxShares);

        return true;
    }

    /**
      @notice Closes a position with the specified position ID, asset percent, and user address.
     @param _positionID The ID of the position to close.
      @param _assetPercent The percentage of the asset to be withdrawn.
      @param _user The address of the user associated with the product ID.
      @param _sameSwap Flag to indicate if the same swap is allowed.
      @dev The function requires that the position is not already liquidated and the cooldown period has expired.
           The caller must be allowed to close the position or be the position owner.
           The function calculates the withdrawable shares, profits, and if the user is withdrawing in full.
           If the user is not withdrawing in full, it calculates the debt value and after loan payment.
           The function burns the withdrawable shares from the user.
           It then withdraws and unstakes the user's withdrawable shares.
           If the user is not withdrawing in full, it repays debt to the `water` contract.
           If the withdrawal fee is applicable, it takes a protocol fee.
           and if `_sameSwap` is true, it transfers the amount after fee to the user in USDC.
           If `_sameSwap` is false, it makes a withdrawal request for the user to withdraw the asset and emits the `OpenRequest` event.
  */
    function closePosition(
        uint256 _positionID,
        uint256 _assetPercent,
        address _user,
        bool _sameSwap,
        IExchangeRouter.CreateWithdrawalParams calldata params
    ) external payable InvalidID(_positionID, _user) nonReentrant {
        // Retrieve user information for the given position
        PositionInfo storage _userInfo = userInfo[_user][_positionID];
        // Validate that the position is not liquidated
        require(!_userInfo.liquidated, "VodkaV2: position is liquidated");
        require(_assetPercent <= DENOMINATOR, "VodkaV2: invalid share percent");
        // Validate that the position has enough shares to close
        require(_userInfo.position > 0, "VodkaV2: position is not enough to close");
        require(allowedClosers[msg.sender] || msg.sender == _userInfo.user, "SAKE: not allowed to close position");
        // Struct to store intermediate data during calculation
        Datas memory data;
        // this function will return withdrawable shares, profits and boolean to check if user is withdrawing in full
        (data.withdrawableShares, data.profits, data.inFull) = _convertToShares(_positionID, _assetPercent, _user);
        // check for liquidation
        (uint256 currentDTV, , uint256 fulldebtValue) = getUpdatedDebt(_positionID, _user);

        if (currentDTV >= (95 * 1e17) / 10) {
            revert("Wait for liquidation");
        }

        uint256 feesPaid;
        if (data.inFull) {
            _burn(_userInfo.user, _userInfo.position);
            // (key,feesPaid) = _withdrawGmToken(_userInfo.position,params);

            IERC20Upgradeable(gmxAddresses.gmxMarketToken).approve(gmxAddresses.gmxRouter, _userInfo.position);
            IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: msg.value }(gmxAddresses.withdrawalHandler, msg.value);
            IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(
                gmxAddresses.gmxMarketToken,
                gmxAddresses.withdrawalHandler,
                _userInfo.position
            );
        } else {
            _burn(_userInfo.user, data.withdrawableShares);
            // (key,feesPaid) = _withdrawGmToken(data.withdrawableShares,params);

            IERC20Upgradeable(gmxAddresses.gmxMarketToken).approve(gmxAddresses.gmxRouter, data.withdrawableShares);
            IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: msg.value }(gmxAddresses.withdrawalHandler, msg.value);
            IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(
                gmxAddresses.gmxMarketToken,
                gmxAddresses.withdrawalHandler,
                data.withdrawableShares
            );
        }

        bytes32 key = IExchangeRouter(gmxAddresses.exchangeRouter).createWithdrawal(params);

        WithdrawRecord storage wr = withdrawrecord[key];

        wr.gmTokenWithdrawnAmount = data.withdrawableShares;
        wr.feesPaid = feesPaid;
        wr.user = _user;
        wr.profits = data.profits;
        wr.positionID = _positionID;
        wr.fullDebtValue = fulldebtValue;

        withdrawSameSwap[key] = _sameSwap;
        withdrawInFull[key] = data.inFull;

        userWithdrawKeyRecords[_user].push(key);
    }

    function fullFillClosePosition(bytes32 _key, uint256 _returnedUSDC) public onlyHandler returns (bool) {
        WithdrawRecord storage wr = withdrawrecord[_key];
        PositionInfo storage _userInfo = userInfo[wr.user][wr.positionID];
        wr.returnedUSDC = _returnedUSDC;

        uint256 toLeverageUser;
        // if user is not withdrawing in full then calculate debt and after loan payment
        if (!withdrawInFull[_key]) {
            uint256 waterProfits;

            uint256 userShares = ((wr.returnedUSDC - wr.profits) * 1e3) / _userInfo.leverageMultiplier;
            uint256 waterShares = (wr.returnedUSDC - wr.profits) - userShares;

            (waterProfits, toLeverageUser) = _getProfitSplit(wr.profits, _userInfo.leverageMultiplier);
            if (waterProfits > 0) {
                IERC20Upgradeable(strategyaddresses.USDC).safeTransfer(feeConfiguration.waterFeeReceiver, waterProfits);
            }

            toLeverageUser = userShares + toLeverageUser;
            _userInfo.position -= wr.gmTokenWithdrawnAmount;

            IERC20Upgradeable(strategyaddresses.USDC).safeIncreaseAllowance(strategyaddresses.WaterContract, waterShares);
            IWater(strategyaddresses.WaterContract).repayDebt(waterShares, waterShares);
            _userInfo.leverageAmount -= waterShares;
            _userInfo.price = getGMPrice();
        } else {
            uint256 waterRepayment;

            if (wr.returnedUSDC < wr.fullDebtValue) {
                _userInfo.liquidator = msg.sender;
                _userInfo.liquidated = true;
                waterRepayment = wr.returnedUSDC;
            } else {
                toLeverageUser = wr.returnedUSDC - wr.fullDebtValue;
                // set position to 0 when user is withdrawing in full to mitigate rounding errors
                _userInfo.closed = true;
                waterRepayment = wr.fullDebtValue;
            }

            IERC20Upgradeable(strategyaddresses.USDC).safeIncreaseAllowance(strategyaddresses.WaterContract, waterRepayment);
            IWater(strategyaddresses.WaterContract).repayDebt(_userInfo.leverageAmount, waterRepayment);
            _userInfo.position = 0;
            _userInfo.leverageAmount = 0;
        }

        if (_userInfo.liquidated) {
            return false;
        }

        // take protocol fee
        uint256 amountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = toLeverageUser.mulDiv(feeConfiguration.withdrawalFee, MAX_BPS);
            IERC20Upgradeable(strategyaddresses.USDC).safeTransfer(feeConfiguration.feeReceiver, fee);
            amountAfterFee = toLeverageUser - fee;
        } else {
            amountAfterFee = toLeverageUser;
        }

        // if user is withdrawing USDC then transfer amount after fee to user else
        // make a withdrawal request for user to withdraw asset and emmit OpenRequest event
        if (withdrawSameSwap[_key]) {
            IERC20Upgradeable(strategyaddresses.USDC).safeTransfer(wr.user, amountAfterFee);
        } else {
            closePositionAmount[wr.user][wr.positionID] = amountAfterFee;
            closePositionRequest[wr.user][wr.positionID] = true;
            emit OpenRequest(wr.user, amountAfterFee);
        }

        _userInfo.closedPositionValue += wr.returnedUSDC;
        _userInfo.closePNL += amountAfterFee;

        emit Withdraw(wr.user, amountAfterFee, block.timestamp, wr.gmTokenWithdrawnAmount);
        wr.success = true;
        return true;
    }

    // /**
    //  * @notice Fulfills a swap request for a closed position with the specified position ID, user address, and output asset.
    //  * @param _positionID The ID of the position to fulfill the swap request for.
    //  * @param _user The address of the user who closed the position.
    //  * @param _data The data to be used for swapping tokens.
    //  * @param _swapSimple Flag to indicate if simple token swapping is allowed.
    //  * @param _outputAsset The address of the output asset (token) for the swap.
    //  * @dev The function requires that the output asset is whitelisted and the swap amount is greater than zero.
    //  *      The function swaps the `amountAfterFee` of USDC to `_outputAsset` using the provided `_data`.
    //  *      The swapped `_outputAsset` amount is transferred to the user.
    //  */
    // function fulfilledRequestSwap(uint256 _positionID, address _user, bytes calldata _data, bool _swapSimple, address _outputAsset) external nonReentrant {
    //     // Retrieve the amount after fee from the `closePositionAmount` mapping
    //     uint256 amountAfterFee = closePositionAmount[_user][_positionID];
    //     require(isWhitelistedAsset[_outputAsset], "VodkaV2: Invalid assets choosen");
    //     require(amountAfterFee > 0, "VodkaV2: position is not enough to close");
    //     require(closePositionRequest[_user][_positionID], "SAKE: Close only open position");

    //     closePositionAmount[_user][_positionID] = 0;

    //     uint256 amountOut = _swap(amountAfterFee, _data, _swapSimple, false, _outputAsset);
    //     IERC20Upgradeable(_outputAsset).safeTransfer(_user, amountOut);
    //     emit RequestFulfilled(_user, amountAfterFee, amountOut);
    // }

    //     function liquidatePosition(uint256 _positionId, address _user) external nonReentrant {
    //         UserInfo storage _userInfo = userInfo[_user][_positionId];
    //         require(!_userInfo.liquidated, "VodkaV2: Already liquidated");
    //         require(_userInfo.user != address(0), "VodkaV2: liquidation request does not exist");
    //         (uint256 currentDTV, , ) = getUpdatedDebt(_positionId, _user);
    //         require(currentDTV >= (95 * 1e17) / 10, "Liquidation Threshold Has Not Reached");
    //
    //         uint256 position = _userInfo.position;
    //
    //         uint256 userAmountStaked;
    //         if (MasterChef != address(0)) {
    //             (userAmountStaked, ) = IMasterChef(MasterChef).userInfo(MCPID, _user);
    //             if (userAmountStaked > 0) {
    //                 uint256 amountToBurnFromUser;
    //                 if (userAmountStaked > position) {
    //                     amountToBurnFromUser = position;
    //                 } else {
    //                     amountToBurnFromUser = userAmountStaked;
    //                     uint256 _position = position - userAmountStaked;
    //                     _burn(_user, _position);
    //                 }
    //                 IMasterChef(MasterChef).unstakeAndLiquidate(MCPID, _user, amountToBurnFromUser);
    //             }
    //         }
    //
    //         if (userAmountStaked == 0) {
    //             _burn(_user, position);
    //         }
    //
    //         uint256 usdcBalanceBefore = IERC20Upgradeable(USDC).balanceOf(address(this));
    //         IExchangeRouter(gmxAddresses.depositHandler).unstake(
    //             USDC,
    //             (GMXMarketBalanceAfterWithdrawal - GMXMarketBalanceBeforeWithdrawal)
    //         );
    //         uint256 usdcBalanceAfter = IERC20Upgradeable(USDC).balanceOf(address(this));
    //         uint256 returnedValue = usdcBalanceAfter - usdcBalanceBefore;
    //
    //         _userInfo.liquidator = msg.sender;
    //         _userInfo.liquidated = true;
    //
    //         uint256 liquidatorReward = returnedValue.mulDiv(feeConfiguration.liquidatorsRewardPercentage, MAX_BPS);
    //         uint256 amountAfterLiquidatorReward = returnedValue - liquidatorReward;
    //
    //         IERC20Upgradeable(USDC).safeIncreaseAllowance(strategyaddresses.WaterContract, amountAfterLiquidatorReward);
    //         IWater(strategyaddresses.WaterContract).repayDebt(_userInfo.leverageAmount, amountAfterLiquidatorReward);
    //         IERC20Upgradeable(USDC).safeTransfer(msg.sender, liquidatorReward);
    //
    //         emit Liquidated(_user, _positionId, msg.sender, returnedValue, liquidatorReward);
    //     }

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

    function _getProfitSplit(uint256 _profit, uint256 _leverage) internal view returns (uint256, uint256) {
        uint256 split = (feeConfiguration.fixedFeeSplit * _leverage + (feeConfiguration.fixedFeeSplit * 10000)) / 100;
        uint256 toWater = (_profit * split) / 10000;
        uint256 toVodkaV2User = _profit - toWater;

        return (toWater, toVodkaV2User);
    }

    /**
     * @notice Converts the user's position to withdrawable shares based on the specified position ID,
     *          asset percent, and user address.
     * @param _positionId The ID of the position to convert to withdrawable shares.
     * @param _assetPercent The percentage of the asset to be converted to shares.
     * @param _user The address of the user converting the position to shares.
     * @return The amount of withdrawable shares, the profit for the position, and a flag indicating if the user is withdrawing in full.
     * @dev The function retrieves user information for the given position and calculates the converted user position to USDC.
     *      It calculates the profit for the position using the `_getProfitState` function.
     *      The function calculates the withdrawal percentage and whether the user is withdrawing in full.
     *      It then calculates the amount of USDC to withdraw based on the withdrawal percentage.
     *      Finally, it converts the USDC amount back to withdrawable shares and returns the results.
     */

    function _convertToShares(uint256 _positionId, uint256 _assetPercent, address _user) internal view returns (uint256, uint256, bool) {
        PositionInfo memory _userInfo = userInfo[_user][_positionId];
        uint256 convertUserPositionToAssets = _convertGMXMarketToUSDC(_userInfo.position, _userInfo.price);
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
        return (_convertUSDCToGMXMarket(amountToWithdraw + profit, getGMPrice()), profit, inFull);
    }

    function _getProfitState(uint256 _positionId, address _user) internal view returns (uint256 profit) {
        (uint256 currentValues, uint256 previousValue) = getCurrentPosition(_positionId, 0, _user);
        if (currentValues > previousValue) {
            profit = currentValues - previousValue;
        }
    }

    function _convertGMXMarketToUSDC(uint256 _amount, uint256 _GMXMarketPrice) internal view returns (uint256) {
        return _amount.mulDiv(_GMXMarketPrice * 10, (10 ** 18));
    }

    function _convertUSDCToGMXMarket(uint256 _amount, uint256 _GMXMarketPrice) internal view returns (uint256) {
        return _amount.mulDiv((10 ** 18), _GMXMarketPrice * 10);
    }

    /**
     * @notice Internal function to perform a token swap using Kyber Router.
     * @dev The function swaps tokens using Kyber Router, which is an external contract.
     *      It supports both simple mode and generic mode swaps.
     * @param _amount The amount of tokens to be swapped.
     * @param _data The data containing the swap description and parameters. The data is ABI-encoded and can be either in simple mode or generic mode format.
     * @param _swapSimple A boolean indicating whether the swap is in simple mode (true) or generic mode (false).
     * @param _swapToUnderlying A boolean indicating whether the swap is from USDC to the underlying asset (true) or vice versa (false).
     * @param _asset The address of the asset being swapped.
     * @return The amount of tokens received after the swap.
     */
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
            require(desc.dstToken == IERC20Upgradeable(strategyaddresses.USDC), "Output must be the same as _inputAsset");
            require(desc.srcToken == IERC20Upgradeable(_asset), "Input must be the same as _inputAsset");
            assetBalBefore = IERC20Upgradeable(strategyaddresses.USDC).balanceOf(address(this));
            IERC20Upgradeable(_asset).safeIncreaseAllowance(strategyaddresses.KyberRouter, desc.amount);
            (succ, ) = address(strategyaddresses.KyberRouter).call(_data);
            assetBalAfter = IERC20Upgradeable(strategyaddresses.USDC).balanceOf(address(this));
        } else {
            // Swap from the underlying asset (USDC) to output token
            require(desc.dstToken == IERC20Upgradeable(_asset), "Output must be the same as _inputAsset");
            require(desc.srcToken == IERC20Upgradeable(strategyaddresses.USDC), "Input must be the same as _inputAsset");
            assetBalBefore = IERC20Upgradeable(_asset).balanceOf(address(this));
            IERC20Upgradeable(strategyaddresses.USDC).safeIncreaseAllowance(strategyaddresses.KyberRouter, desc.amount);
            (succ, ) = address(strategyaddresses.KyberRouter).call(_data);
            assetBalAfter = IERC20Upgradeable(_asset).balanceOf(address(this));
        }
        require(succ, "Swap failed");
        // Check that the token balance after the swap increased
        require(assetBalAfter > assetBalBefore, "SAKE: Swap failed");
        // Return the amount of tokens received after the swap
        return (assetBalAfter - assetBalBefore);
    }

    // function _withdrawGmToken(uint256 amount, IExchangeRouter.CreateWithdrawalParams calldata params) public payable returns (bytes32 key,uint256) {

    //     IERC20Upgradeable(gmxAddresses.gmxMarketToken).approve(gmxAddresses.gmxRouter, amount);
    //     IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{ value: msg.value }(gmxAddresses.withdrawalHandler, msg.value);
    //     IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(gmxAddresses.gmxMarketToken, gmxAddresses.withdrawalHandler, amount);

    //     IExchangeRouter(gmxAddresses.exchangeRouter).createWithdrawal(params);

    //     return (key,msg.value);
    // }

    receive() external payable {}
}

