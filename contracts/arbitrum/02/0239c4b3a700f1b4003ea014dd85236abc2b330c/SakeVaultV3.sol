// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./ISettingManager.sol";
import "./IMasterChef.sol";
import "./ITokenBurnable.sol";
import "./IWater.sol";
import {IVault} from "./IVault.sol";
import {ITokenFarm} from "./ITokenFarm.sol";

import "./console.sol";

interface ISwapHandler {
    function fulfilledRequestSwap(
        uint256 _positionID,
        bytes calldata _data,
        bool _swapSimple,
        address _outputAsset
    ) external;

    function sakeSwap(
        uint256 _amount,
        bytes calldata _data,
        bool _swapSimple,
        address _asset
    ) external returns (uint256);

    function addPositionRequest(address _user, uint256 _positionID, uint256 _amountAfterFee) external;
}

contract SakeVaultV3 is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    struct UserInfo {
        address user; // user that created the position
        uint256 deposit; // total amount of deposit
        uint256 leverage; // leverage used
        uint256 position; // position size
        uint256 price; // VLP price
        bool liquidated; // true if position was liquidated
        uint256 cooldownPeriodElapse; // epoch when user can withdraw
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
        uint256 profits;
        uint256 currentDTV;
        uint256 fulldebtValue;
        uint256 returnedValue;
        uint256 positionID;
        uint256 assetPercent;
        uint256 restakeAmount;
        uint256 closeAmount;
        uint256 debtRepayment;
    }

    struct StrategyAddresses {
        address USDC;
        address water;
        address velaMintBurnVault;
        address velaStakingVault;
        address velaSettingManager;
        address vlpToken;
        address esVela;
        address VELA;
        address MasterChef;
        address KyberRouter;
    }

    FeeConfiguration public feeConfiguration;
    StrategyAddresses public strategyAddresses;

    address[] public allUsers;
    address public keeper;
    address public SwapHandler;

    uint256 public MCPID;
    uint256 public MAX_BPS;
    uint256 public MAX_LEVERAGE;
    uint256 public MIN_LEVERAGE;
    uint256 public timeAdjustment;

    uint256 private constant DENOMINATOR = 1_000;
    uint256 private constant DECIMAL = 1e18;

    mapping(address => UserInfo[]) public userInfo;
    mapping(address => bool) public allowedSenders;
    mapping(address => bool) public allowedClosers;
    mapping(address => bool) public burner;
    mapping(address => bool) public isUser;
    mapping(address => uint256) public userTimelock;
    mapping(address => bool) public isWhitelistedAsset;
    mapping(address => mapping(uint256 => bool)) public closePositionRequest;
    mapping(address => mapping(uint256 => uint256)) public closePositionAmount;
    
    uint256[50] private __gaps;
    mapping(address => mapping(uint256 => uint256)) public positionValue;
    
    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < userInfo[user].length, "Sake: positionID is not valid");
        _;
    }

    modifier onlyBurner() {
        require(burner[msg.sender], "Not allowed to burn");
        _;
    }

    // only keeper
    modifier onlyKeeper() {
        require(msg.sender == keeper, "Not keeper");
        _;
    }

    /** --------------------- Event --------------------- */
    event WaterContractChanged(address newWater);
    event VaultContractChanged(address newVault, address newTokenFarm, address newSettingManager, address newVlpToken);
    event Deposit(address indexed depositer, uint256 depositTokenAmount, uint256 createdAt, uint256 vlpAmount);
    event Withdraw(address indexed user, uint256 amount, uint256 time, uint256 newVLPAmount);
    event ProtocolFeeChanged(
        address newFeeReceiver,
        uint256 newWithdrawalFee,
        address newWaterFeeReceiver,
        uint256 liquidatorsRewardPercentage,
        uint256 fixedFeeSplit
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
    event UpdateMCAndPID(address indexed newMC, uint256 mcpPid);
    event UpdateMaxAndMinLeverage(uint256 maxLeverage, uint256 minLeverage);
    event UpdateKyberRouter(address newKyberRouter);
    event OpenRequest(address indexed user, uint256 amountAfterFee);
    event SetAssetWhitelist(address indexed asset, bool isWhitelisted);
    event Harvested(bool vela, bool esVela, bool vlp, bool vesting);
    event Liquidated(
        address indexed user,
        uint256 indexed positionId,
        address liquidator,
        uint256 amount,
        uint256 reward
    );
    event SetTimeAdjustment(uint256 timeAdjustment);
    event SetDebtValueRatio(uint256 debtValueRatio);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdc,
        address _water,
        address _velaMintBurnVault,
        address _velaStakingVault,
        address _velaSettingManager,
        address _velaToken
    ) external initializer {
        require(
            _usdc != address(0) &&
                _water != address(0) &&
                _velaMintBurnVault != address(0) &&
                _velaStakingVault != address(0) &&
                _velaSettingManager != address(0) &&
                _velaToken != address(0),
            "Zero address"
        );

        strategyAddresses.USDC = _usdc;
        strategyAddresses.water = _water;
        strategyAddresses.velaMintBurnVault = _velaMintBurnVault;
        strategyAddresses.velaStakingVault = _velaStakingVault;
        strategyAddresses.velaSettingManager = _velaSettingManager;
        strategyAddresses.vlpToken = _velaToken;
        strategyAddresses.esVela = address(ITokenFarm(_velaStakingVault).esVELA());
        strategyAddresses.VELA = address(ITokenFarm(_velaStakingVault).VELA());

        MAX_BPS = 100_000;
        MAX_LEVERAGE = 10_000;
        MIN_LEVERAGE = 2_000;

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("SakePOD", "SPOD");
    }

    /** ----------- Change onlyOwner functions ------------- */

    function setHandlers(
        address _keeper,
        address _SwapHandler) external onlyOwner {
        keeper = _keeper;
        SwapHandler = _SwapHandler;
    }

    //MC or any other whitelisted contracts
    function setAllowed(address _sender, bool _allowed) public onlyOwner {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setAssetWhitelist(address _asset, bool _status) public onlyOwner {
        isWhitelistedAsset[_asset] = _status;
        emit SetAssetWhitelist(_asset, _status);
    }

    function setCloser(address _closer, bool _allowed) public onlyOwner {
        allowedClosers[_closer] = _allowed;
        emit SetAllowedClosers(_closer, _allowed);
    }

    function setBurner(address _burner, bool _allowed) public onlyOwner {
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setMC(address _MasterChef, uint256 _MCPID) public onlyOwner {
        strategyAddresses.MasterChef = _MasterChef;
        MCPID = _MCPID;
        emit UpdateMCAndPID(_MasterChef, _MCPID);
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
    ) external onlyOwner {
        require(_withdrawalFee <= MAX_BPS && _fixedFeeSplit < 100, "Invalid fees");
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

    function setVelaContracts(
        address _velaMintBurnVault,
        address _velaStakingVault,
        address _velaSettingManager,
        address _vlpToken
    )
        external
        onlyOwner
    {
        strategyAddresses.velaMintBurnVault = _velaMintBurnVault;
        strategyAddresses.velaStakingVault = _velaStakingVault;
        strategyAddresses.velaSettingManager = _velaSettingManager;
        strategyAddresses.vlpToken = _vlpToken;
        emit VaultContractChanged(_velaMintBurnVault, _velaStakingVault, _velaSettingManager, _vlpToken);
    }

    function setWater(address _water) external onlyOwner {
        strategyAddresses.water = _water;
        emit WaterContractChanged(_water);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /** ----------- Admin VELA functions ------------- */

    function harvestMany(bool _vela, bool _esvela, bool _vlp, bool _vesting) external onlyOwner {
        ITokenFarm(strategyAddresses.velaStakingVault).harvestMany(_vela, _esvela, _vlp, _vesting);
        emit Harvested(_vela, _esvela, _vlp, _vesting);
    }

    /**
     * @notice Withdraw vested ESVELA tokens and transfer vested VELA tokens to the fee receiver.
     * @dev The function can only be called by the contract owner (usually the deployer of the contract).
     *      The function first gets the current balance of ESVELA tokens held by the contract before withdrawal.
     *      It then calls the `withdrawVesting` function of the `velaStakingVault` contract to withdraw vested ESVELA tokens.
     *      After withdrawal, the function gets the new balance of ESVELA tokens held by the contract.
     *      It calculates the amount of ESVELA tokens vested by subtracting the balance before withdrawal from the balance after withdrawal.
     *      The vested ESVELA tokens are transferred to the fee receiver specified in the `feeConfiguration`.
     *      The function also transfers any vested VELA tokens held by the contract to the fee receiver.
     */
    function withdrawVesting() external onlyOwner {
        uint256 esVelaBeforeWithdrawal = IERC20Upgradeable(strategyAddresses.esVela).balanceOf(address(this));
        ITokenFarm(strategyAddresses.velaStakingVault).withdrawVesting();
        uint256 esVelaAfterWithdrawal = IERC20Upgradeable(strategyAddresses.esVela).balanceOf(address(this));
        IERC20Upgradeable(strategyAddresses.esVela).safeTransfer(
            feeConfiguration.feeReceiver,
            esVelaAfterWithdrawal - esVelaBeforeWithdrawal
        );
        IERC20Upgradeable(strategyAddresses.VELA).safeTransfer(
            feeConfiguration.feeReceiver,
            IERC20Upgradeable(strategyAddresses.VELA).balanceOf(address(this))
        );
    }

    // deposit vesting
    function depositVesting() external onlyOwner {
        uint256 esVelaContractBalance = IERC20Upgradeable(strategyAddresses.esVela).balanceOf(address(this));
        IERC20Upgradeable(strategyAddresses.esVela).safeIncreaseAllowance(
            strategyAddresses.velaStakingVault,
            esVelaContractBalance
        );
        ITokenFarm(strategyAddresses.velaStakingVault).depositVesting(esVelaContractBalance);
    }

    function claim() external onlyOwner {
        ITokenFarm(strategyAddresses.velaStakingVault).claim();
        IERC20Upgradeable(strategyAddresses.VELA).safeTransfer(
            feeConfiguration.feeReceiver,
            IERC20Upgradeable(strategyAddresses.VELA).balanceOf(address(this))
        );
    }

    // withdraw all vela tokens from the vault
    function withdrawAllVELA() external onlyOwner {
        IERC20Upgradeable(strategyAddresses.VELA).safeTransfer(
            feeConfiguration.feeReceiver,
            IERC20Upgradeable(strategyAddresses.VELA).balanceOf(address(this))
        );
    }

    // withdraw all esvela tokens from the vault
    function withdrawAllESVELA() external onlyOwner {
        IERC20Upgradeable(strategyAddresses.esVela).safeTransfer(
            feeConfiguration.waterFeeReceiver,
            IERC20Upgradeable(strategyAddresses.esVela).balanceOf(address(this))
        );
    }

    /** ----------- View functions ------------- */

    function getVLPPrice() public view returns (uint256) {
        return IVault(strategyAddresses.velaMintBurnVault).getVLPPrice();
    }

    function getVlpBalance() public view returns (uint256) {
        return IERC20Upgradeable(strategyAddresses.vlpToken).balanceOf(address(this));
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
        uint256 totalWaterDebt = IWater(strategyAddresses.water).totalDebt();
        uint256 totalWaterAssets = IWater(strategyAddresses.water).balanceOfUSDC();
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
    ) public view returns (uint256, uint256, uint256) {
        UserInfo memory _userInfo = userInfo[_user][_positionID];
        if (_userInfo.closed || _userInfo.liquidated) return (0, 0, 0);

        (uint256 currentPosition,) = getCurrentPosition(_positionID, _userInfo.position, _user);
        uint256 owedToWater = _userInfo.leverageAmount;
        uint256 currentDTV = owedToWater.mulDiv(DECIMAL, currentPosition);

        return (currentDTV, currentPosition, owedToWater);
    }

    function getPositionProfits(
        uint256 _positionID,
        address _user
    ) public view returns (uint256, uint256) {
        UserInfo memory _userInfo = userInfo[_user][_positionID];
        if (_userInfo.closed || _userInfo.liquidated) return (0, 0);

        (uint256 currentPosition, uint256 previousValueInUSDC) = getCurrentPosition(_positionID, _userInfo.position, _user);
        uint256 leverage = _userInfo.leverageAmount;

        uint256 profitOrLoss;
        uint256 rewardSplitToWater;
        uint256 owedToWater;
        if (currentPosition > previousValueInUSDC) {
            profitOrLoss = currentPosition - previousValueInUSDC;
            (rewardSplitToWater, ) = _getProfitSplit(profitOrLoss, _userInfo.leverage);
            owedToWater = leverage + rewardSplitToWater;
        } else {
            owedToWater = leverage;
        }

        return (owedToWater, rewardSplitToWater);
    }

    function getCurrentPosition(
        uint256 _positionID,
        uint256 _shares,
        address _user
    ) public view returns (uint256 currentPosition, uint256 previousValueInUSDC) {
        UserInfo memory _userInfo = userInfo[_user][_positionID];
        uint256 userShares = (_shares == 0) ? _userInfo.position : _shares;
        return (_convertVLPToUSDC(userShares, getVLPPrice()), _convertVLPToUSDC(userShares, _userInfo.price));
    }

    /** ----------- User functions ------------- */

    /**
     * @notice Opens a new position with the specified amount and leverage.
     * @param _amount The amount of tokens to use for opening the position.
     * @param _leverage The leverage to apply for the position.
     * @param _data The data to be used for swapping tokens if necessary.
     * @param _swapSimple Flag to indicate if simple token swapping is allowed.
     * @param _inputAsset The address of the input asset (token) for the position.
     * @dev The contract must be in a non-paused state and meet the leverage requirements.
     *      If the input asset is not USDC, it must be whitelisted.
     *      The `_amount` must be greater than zero.
     *      If `_inputAsset` is not USDC, the function swaps the input asset to USDC.
     *      The function then lends the leveraged amount of USDC using the `water` contract.
     *      The `xAmount` is calculated by adding the leveraged amount to the initial amount.
     *      The contract increases allowance and stakes the `xAmount` to the `velaMintBurnVault`.
     *      The vela shares are minted to the user and deposited to the `velaStakingVault`.
     */
    function openPosition(
        uint256 _amount,
        uint256 _leverage,
        bytes calldata _data,
        bool _swapSimple,
        address _inputAsset
    ) external whenNotPaused nonReentrant {
        require(_leverage >= MIN_LEVERAGE && _leverage <= MAX_LEVERAGE, "Sake: Invalid leverage");
        require(_amount > 0, "Sake: amount must be greater than zero");
        IERC20Upgradeable(_inputAsset).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 amount;
        // swap to USDC if input is not USDC
        if (_inputAsset != strategyAddresses.USDC) {
            require(isWhitelistedAsset[_inputAsset], "Sake: Invalid assets choosen");
            IERC20Upgradeable(_inputAsset).safeTransfer(SwapHandler,_amount);
            amount = ISwapHandler(SwapHandler).sakeSwap(_amount, _data, _swapSimple, _inputAsset);
        } else {
            amount = _amount;
        }
        // get leverage amount
        uint256 leveragedAmount = amount.mulDiv(_leverage, DENOMINATOR) - amount;
        bool status = IWater(strategyAddresses.water).lend(leveragedAmount);
        require(status, "Water: Lend failed");
        // add leverage amount to amount
        uint256 xAmount = amount + leveragedAmount;
        positionValue[msg.sender][userInfo[msg.sender].length] = xAmount;

        uint256 velaShares = _depositAndStakeVLP(xAmount);
        console.log("velaShares", velaShares);
        console.log("xAmount", xAmount);

        UserInfo memory _userInfo = UserInfo({
            user: msg.sender,
            deposit: amount,
            leverage: _leverage,
            position: velaShares,
            price: getVLPPrice(),
            liquidated: false,
            cooldownPeriodElapse: block.timestamp +
                ISettingManager(strategyAddresses.velaSettingManager).cooldownDuration(),
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
        // mint vela shares to user
        _mint(msg.sender, velaShares);
        emit Deposit(msg.sender, amount, block.timestamp, velaShares);
    }

    /**
     * @notice Closes a position with the specified position ID, asset percent, and user address.
     * @param _positionID The ID of the position to close.
     * @param _assetPercent The percentage of the asset to be withdrawn.
     * @param _user The address of the user associated with the product ID.
     * @param _sameSwap Flag to indicate if the same swap is allowed.
     * @dev The function requires that the position is not already liquidated and the cooldown period has expired.
     *      The caller must be allowed to close the position or be the position owner.
     *      The function calculates the withdrawable shares, profits, and if the user is withdrawing in full.
     *      If the user is not withdrawing in full, it calculates the debt value and after loan payment.
     *      The function burns the withdrawable shares from the user.
     *      It then withdraws and unstakes the user's withdrawable shares.
     *      If the user is not withdrawing in full, it repays debt to the `water` contract.
     *      If the withdrawal fee is applicable, it takes a protocol fee.
     *      and if `_sameSwap` is true, it transfers the amount after fee to the user in USDC.
     *      If `_sameSwap` is false, it makes a withdrawal request for the user to withdraw the asset and emits the `OpenRequest` event.
     */
    function closePosition(
        uint256 _positionID,
        uint256 _assetPercent,
        address _user,
        bool _sameSwap
    ) external InvalidID(_positionID, _user) nonReentrant {
        // Retrieve user information for the given position
        UserInfo storage _userInfo = userInfo[_user][_positionID];
        // Validate that the position is not liquidated
        require(!_userInfo.liquidated, "Sake: position is liquidated");
        require(_assetPercent <= DENOMINATOR, "Sake: invalid share percent");
        // Validate that the position has enough shares to close
        require(_userInfo.position > 0, "Sake: position is not enough to close");
        require(block.timestamp >= _userInfo.cooldownPeriodElapse, "Sake: user timelock not expired");
        require(allowedClosers[msg.sender] || msg.sender == _userInfo.user, "SAKE: not allowed to close position");

        // Struct to store intermediate data during calculation
        Datas memory data;
        data.positionID = _positionID;
        data.assetPercent = _assetPercent;
        data.fulldebtValue = _userInfo.leverageAmount;

        (data.currentDTV, ,) = getUpdatedDebt(data.positionID, _user);
        if (data.currentDTV >= (95 * 1e17) / 10) {
            revert("Wait for liquidation");
        }

        _burn(_userInfo.user, _userInfo.position);
        (data.returnedValue, ) = _withdrawAndUnstakeVLP(_userInfo.position);
        //data.returnedValue = 4e6;
        console.log("data.returnedValue", data.returnedValue);


        uint256 previousValueInUSDC = positionValue[_user][data.positionID];
        console.log("previousValueInUSDC", previousValueInUSDC);
        console.log("_userInfo.position", _userInfo.position);
        console.log("_userInfo.price",_userInfo.price);

        if (data.returnedValue > previousValueInUSDC) {
            data.profits = data.returnedValue - previousValueInUSDC;
            console.log("profits", data.profits);
        }
        
        uint256 toLeverageUser;
        uint256 waterProfits;
        uint256 leverageUserProfits;
        if (data.assetPercent < 900) {
            
            if (data.profits <= 1 ) {
                data.profits = 0;
            }

            data.closeAmount = (data.returnedValue - data.profits).mulDiv(data.assetPercent, DENOMINATOR);
            console.log("data.closeAmount", data.closeAmount);

            data.restakeAmount = (data.returnedValue - data.profits) - data.closeAmount;
            console.log("data.restakeAmount", data.restakeAmount);
            
            data.debtRepayment = _userInfo.leverageAmount.mulDiv(data.assetPercent, DENOMINATOR);
            console.log("data.debtRepayment", data.debtRepayment);

            (waterProfits, leverageUserProfits) = _getProfitSplit(data.profits, _userInfo.leverage);
            console.log("waterProfits", waterProfits);
            console.log("leverageUserProfits", leverageUserProfits);

            uint256 userShares = data.closeAmount - data.debtRepayment;
            console.log("userShares", userShares);
            toLeverageUser = userShares + leverageUserProfits;
            console.log("toLeverageUser", toLeverageUser);

            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, data.debtRepayment);
            IWater(strategyAddresses.water).repayDebt(data.debtRepayment, data.debtRepayment);

            _userInfo.leverageAmount -= data.debtRepayment;
            positionValue[_user][data.positionID] = data.restakeAmount;
            _userInfo.position = _depositAndStakeVLP(data.restakeAmount);
            _userInfo.price = getVLPPrice();
            _mint(_user, _userInfo.position);
        } else {
            uint256 waterRepayment;
            (waterProfits, leverageUserProfits) = _getProfitSplit(data.profits, _userInfo.leverage);
            console.log("leverageUserProfits", leverageUserProfits);

            if (data.returnedValue < (data.fulldebtValue + waterProfits)) {
                _userInfo.liquidator = msg.sender;
                _userInfo.liquidated = true;
                waterRepayment = data.returnedValue;
            } else {
                toLeverageUser = (data.returnedValue - data.fulldebtValue - data.profits) + leverageUserProfits;
                console.log("toLeverageUser", toLeverageUser);
                _userInfo.closed = true;
                waterRepayment = data.returnedValue - toLeverageUser - waterProfits;
                console.log("waterRepayment", waterRepayment);
            }

            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, waterRepayment);
            IWater(strategyAddresses.water).repayDebt(_userInfo.leverageAmount, waterRepayment);
            _userInfo.leverageAmount = 0;
            positionValue[_user][data.positionID] = 0; 
            _userInfo.position = 0;
            _userInfo.price = getVLPPrice();
        }

        if (waterProfits > 0) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(feeConfiguration.waterFeeReceiver, waterProfits);
            console.log("waterProfits", waterProfits);
        }

        if (_userInfo.liquidated) {
            return;
        }

        // take protocol fee
        uint256 amountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = toLeverageUser.mulDiv(feeConfiguration.withdrawalFee, MAX_BPS);
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(feeConfiguration.feeReceiver, fee);
            amountAfterFee = toLeverageUser - fee;
        } else {
            amountAfterFee = toLeverageUser;
        }

        // if user is withdrawing USDC then transfer amount after fee to user else
        // make a withdrawal request for user to withdraw asset and emmit OpenRequest event
        if (_sameSwap) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(_user, amountAfterFee);
        } else {
            ISwapHandler(SwapHandler).addPositionRequest(_user, _positionID,amountAfterFee);
            emit OpenRequest(_user, amountAfterFee);
        }

        _userInfo.closedPositionValue += data.returnedValue;
        _userInfo.closePNL += amountAfterFee;

        emit Withdraw(_user, amountAfterFee, block.timestamp, _userInfo.position);
    }

    function liquidatePosition(uint256 _positionId, address _user) external nonReentrant {
        UserInfo storage _userInfo = userInfo[_user][_positionId];
        require(!_userInfo.liquidated, "Sake: Already liquidated");
        require(_userInfo.user != address(0), "Sake: liquidation request does not exist");
        (uint256 currentDTV, ,) = getUpdatedDebt(_positionId, _user);
        require(currentDTV >= (95 * 1e17) / 10, "Liquidation Threshold Has Not Reached");

        Datas memory data;
        data.positionID = _positionId;

        uint256 position = _userInfo.position;

        uint256 userAmountStaked;
        if (strategyAddresses.MasterChef != address(0)) {
            (userAmountStaked, ) = IMasterChef(strategyAddresses.MasterChef).userInfo(MCPID, _user);
            if (userAmountStaked > 0) {
                uint256 amountToBurnFromUser;
                if (userAmountStaked > position) {
                    amountToBurnFromUser = position;
                } else {
                    amountToBurnFromUser = userAmountStaked;
                    uint256 _position = position - userAmountStaked;
                    _burn(_user, _position);
                }
                IMasterChef(strategyAddresses.MasterChef).unstakeAndLiquidate(MCPID, _user, amountToBurnFromUser);
            }
        }

        if (userAmountStaked == 0) {
            _burn(_user, position);
        }

        IERC20Upgradeable(strategyAddresses.vlpToken).approve(strategyAddresses.velaStakingVault, _userInfo.position);
        uint256 vlpBalanceBeforeWithdrawal = getVlpBalance();
        ITokenFarm(strategyAddresses.velaStakingVault).withdrawVlp(position);
        uint256 vlpBalanceAfterWithdrawal = getVlpBalance();

        uint256 usdcBalanceBefore = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));
        IVault(strategyAddresses.velaMintBurnVault).unstake(
            strategyAddresses.USDC,
            (vlpBalanceAfterWithdrawal - vlpBalanceBeforeWithdrawal)
        );
        uint256 usdcBalanceAfter = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));
        uint256 returnedValue = usdcBalanceAfter - usdcBalanceBefore;

        _userInfo.liquidator = msg.sender;
        _userInfo.liquidated = true;

        uint256 liquidatorReward = returnedValue.mulDiv(feeConfiguration.liquidatorsRewardPercentage, MAX_BPS);
        uint256 amountAfterLiquidatorReward = returnedValue - liquidatorReward;

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(
            strategyAddresses.water,
            amountAfterLiquidatorReward
        );
        bool success = IWater(strategyAddresses.water).repayDebt(_userInfo.leverageAmount, amountAfterLiquidatorReward);
        require(success, "Water: Repay failed");
        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(msg.sender, liquidatorReward);

        emit Liquidated(_user, _positionId, msg.sender, returnedValue, liquidatorReward);
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

    function _getProfitSplit(uint256 _profit, uint256 _leverage) internal view returns (uint256, uint256) {
        uint256 split = (feeConfiguration.fixedFeeSplit * _leverage + (feeConfiguration.fixedFeeSplit * 10000)) / 100;
        uint256 toWater = (_profit * split) / 10000;
        uint256 toSakeUser = _profit - toWater;

        return (toWater, toSakeUser);
    }

    function _getProfitState(uint256 _positionId, address _user) internal view returns (uint256 profit) {
        (uint256 currentValues, uint256 previousValue) = getCurrentPosition(_positionId, 0, _user);
        if (currentValues > previousValue) {
            profit = currentValues - previousValue;
        }
    }

    function _convertVLPToUSDC(uint256 _amount, uint256 _vlpPrice) internal pure returns (uint256) {
        return _amount * (_vlpPrice * 1e13) / 1e18 / 1e12;
    }

    function _withdrawAndUnstakeVLP(uint256 _shares) internal returns (uint256, uint256) {
        IERC20Upgradeable(strategyAddresses.vlpToken).safeIncreaseAllowance(
            strategyAddresses.velaStakingVault,
            _shares
        );
        uint256 vlpBalanceBeforeWithdrawal = getVlpBalance();
        ITokenFarm(strategyAddresses.velaStakingVault).withdrawVlp(_shares);
        uint256 vlpBalanceAfterWithdrawal = getVlpBalance();

        uint256 usdcBalanceBefore = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));
        uint256 vlpAmount = (vlpBalanceAfterWithdrawal - vlpBalanceBeforeWithdrawal);
        IVault(strategyAddresses.velaMintBurnVault).unstake(strategyAddresses.USDC, vlpAmount);
        uint256 usdcBalanceAfter = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));

        return (usdcBalanceAfter - usdcBalanceBefore, vlpAmount);
    }

    function _depositAndStakeVLP(uint256 _amount) internal returns (uint256){
        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.velaMintBurnVault, _amount);

        uint256 balanceBefore = getVlpBalance();
        console.log("stake");
        IVault(strategyAddresses.velaMintBurnVault).stake(address(this), strategyAddresses.USDC, _amount);
        uint256 balanceAfter = getVlpBalance();

        uint256 velaShares = balanceAfter - balanceBefore;
        console.log("velaShares",velaShares);
        IERC20Upgradeable(strategyAddresses.vlpToken).safeIncreaseAllowance(strategyAddresses.velaStakingVault,velaShares);
        ITokenFarm(strategyAddresses.velaStakingVault).depositVlp(velaShares);
        return velaShares;
    }
}

