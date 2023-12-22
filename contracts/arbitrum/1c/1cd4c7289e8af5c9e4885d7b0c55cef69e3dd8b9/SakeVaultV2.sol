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

contract SakeVaultV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
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
        bool success;
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

    uint256 public MCPID;
    uint256 public MAX_BPS;
    uint256 public MAX_LEVERAGE;
    uint256 public MIN_LEVERAGE;

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
    
    uint256 private mFeePercent;
    address private mFeeReceiver;

    struct CloseData {
        uint256 currentDTV;
        uint256 fulldebtValue;
        uint256 returnedValue;
        uint256 userShares;
        uint256 waterShares;
        uint256 waterProfits;
        uint256 mFee;
        uint256 toLeverageUser;
    }

    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < userInfo[user].length, "Sake: positionID is not valid");
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

    /** --------------------- Event --------------------- */
    event WaterContractChanged(address newWater);
    event VaultContractChanged(address newVault, address newTokenFarm, address newSettingManager, address newVlpToken);
    event Deposit(address indexed depositer, uint256 depositTokenAmount, uint256 createdAt, uint256 vlpAmount);
    event Withdraw(address indexed user, uint256 amount, uint256 time, uint256 vlpAmount);
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
    event RequestFulfilled(address indexed user, uint256 openAmount, uint256 closedAmount);
    event SetAssetWhitelist(address indexed asset, bool isWhitelisted);
    event Harvested(bool vela, bool esVela, bool vlp, bool vesting);
    event Liquidated(
        address indexed user,
        uint256 indexed positionId,
        address liquidator,
        uint256 amount,
        uint256 reward
    );

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

    function setMC(address _MasterChef, uint256 _MCPID) public onlyOwner zeroAddress(_MasterChef) {
        strategyAddresses.MasterChef = _MasterChef;
        MCPID = _MCPID;
        emit UpdateMCAndPID(_MasterChef, _MCPID);
    }

    function setKyberRouter(address _KyberRouter) public onlyOwner zeroAddress(_KyberRouter) {
        strategyAddresses.KyberRouter = _KyberRouter;
        emit UpdateKyberRouter(_KyberRouter);
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
        uint256 _fixedFeeSplit,
        uint256 _mFeePercent,
        address _mFeeReceiver
    ) external onlyOwner zeroAddress(_feeReceiver) zeroAddress(_waterFeeReceiver) {
        require(_withdrawalFee <= MAX_BPS && _fixedFeeSplit < 100, "Invalid fees");
        require(_mFeePercent <= 10000, "Invalid mFeePercent");

        feeConfiguration.feeReceiver = _feeReceiver;
        feeConfiguration.withdrawalFee = _withdrawalFee;
        feeConfiguration.waterFeeReceiver = _waterFeeReceiver;
        feeConfiguration.liquidatorsRewardPercentage = _liquidatorsRewardPercentage;
        feeConfiguration.fixedFeeSplit = _fixedFeeSplit;
        mFeeReceiver = _mFeeReceiver;
        mFeePercent = _mFeePercent;
        

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
        address _vlpToken,
        address _water
    )
        external
        onlyOwner
    {
        strategyAddresses.velaMintBurnVault = _velaMintBurnVault;
        strategyAddresses.velaStakingVault = _velaStakingVault;
        strategyAddresses.velaSettingManager = _velaSettingManager;
        strategyAddresses.vlpToken = _vlpToken;
        strategyAddresses.water = _water;
        emit VaultContractChanged(_velaMintBurnVault, _velaStakingVault, _velaSettingManager, _vlpToken);
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

    function getStakedVlpBalance() public view returns (uint256) {
        return ITokenFarm(strategyAddresses.velaStakingVault).getStakedVLP(address(this));
    }

    function getAllUsers() public view returns (address[] memory) {
        return allUsers;
    }

    function getClaimable() public view returns (uint256) {
        return ITokenFarm(strategyAddresses.velaStakingVault).claimable(address(this));
    }

    function getTotalNumbersOfOpenPositionBy(address _user) public view returns (uint256) {
        return userInfo[_user].length;
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
        UserInfo memory _userInfo = userInfo[_user][_positionID];
        if (_userInfo.closed || _userInfo.liquidated) return (0, 0, 0);

        uint256 previousValueInUSDC;
        // Get the current position and previous value in USDC using the `getCurrentPosition` function
        (currentPosition, previousValueInUSDC) = getCurrentPosition(_positionID, _userInfo.position, _user);
        uint256 leverage = _userInfo.leverageAmount;

        // Calculate the current DTV by dividing the amount owed to water by the current position
        currentDTV = leverage.mulDiv(DECIMAL, currentPosition);
        // Return the current DTV, current position, and amount owed to water
        return (currentDTV, currentPosition, leverage);
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
            amount = _swap(_amount, _data, _swapSimple, true, _inputAsset);
        } else {
            amount = _amount;
        }
        // get leverage amount
        uint256 leveragedAmount = amount.mulDiv(_leverage, DENOMINATOR) - amount;
        bool status = IWater(strategyAddresses.water).lend(leveragedAmount);
        require(status, "Water: Lend failed");
        // add leverage amount to amount
        uint256 xAmount = amount + leveragedAmount;

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.velaMintBurnVault, xAmount);
        uint256 balanceBefore = getVlpBalance();
        // stake to vela
        IVault(strategyAddresses.velaMintBurnVault).stake(address(this), strategyAddresses.USDC, xAmount);
        uint256 balanceAfter = getVlpBalance();

        uint256 velaShares = balanceAfter - balanceBefore;
        IERC20Upgradeable(strategyAddresses.vlpToken).safeIncreaseAllowance(
            strategyAddresses.velaStakingVault,
            velaShares
        );
        // deposit to vela staking vault
        ITokenFarm(strategyAddresses.velaStakingVault).depositVlp(velaShares);
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
        address _user,
        bool _sameSwap
    ) external InvalidID(_positionID, _user) nonReentrant {
        // Retrieve user information for the given position
        UserInfo storage _userInfo = userInfo[_user][_positionID];
        // Validate that the position is not liquidated
        require(!_userInfo.liquidated, "Sake: position is liquidated");
        // Validate that the position has enough shares to close
        require(_userInfo.position > 0, "Sake: position is not enough to close");
        require(block.timestamp >= _userInfo.cooldownPeriodElapse, "Sake: user timelock not expired");
        require(allowedClosers[msg.sender] || msg.sender == _userInfo.user, "SAKE: not allowed to close position");

        // Struct to store intermediate data during calculation
        Datas memory data;
        CloseData memory closeData;

        // check for liquidation
        (closeData.currentDTV, ,closeData.fulldebtValue) = getUpdatedDebt(_positionID, _user);

        if (closeData.currentDTV >= (95 * 1e17) / 10) {
            revert("Wait for liquidation");
        }

        _handlePODToken(_userInfo.user, _userInfo.position);
        (closeData.returnedValue, ) = _withdrawAndUnstakeVLP(_userInfo.position);
        uint256 originalPosAmount = _userInfo.deposit + _userInfo.leverageAmount;

        if (closeData.returnedValue > originalPosAmount) {
            data.profits = closeData.returnedValue - originalPosAmount;
        }

        uint256 waterRepayment;
        if (closeData.returnedValue < closeData.fulldebtValue) {
            _userInfo.liquidator = msg.sender;
            _userInfo.liquidated = true;
            waterRepayment = closeData.returnedValue;
        } else {
            if (data.profits > 0) {
                (closeData.waterProfits, closeData.mFee, closeData.userShares) = _getProfitSplit(data.profits, _userInfo.leverage);
            }
            
            waterRepayment = closeData.fulldebtValue;
            closeData.toLeverageUser = (closeData.returnedValue - waterRepayment) - closeData.waterProfits - closeData.mFee;
        }

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, waterRepayment);
        data.success = IWater(strategyAddresses.water).repayDebt(_userInfo.leverageAmount, waterRepayment);
        _userInfo.position = 0;
        _userInfo.leverageAmount = 0;
        _userInfo.closed = true;

        if (_userInfo.liquidated) {
            return;
        }

        if (closeData.waterProfits > 0) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(feeConfiguration.waterFeeReceiver, closeData.waterProfits);
        }

        if (closeData.mFee > 0) {
                IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(mFeeReceiver, closeData.mFee);
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

        _userInfo.closedPositionValue += closeData.returnedValue;
        _userInfo.closePNL += amountAfterFee;

        emit Withdraw(_user, amountAfterFee, block.timestamp, _userInfo.position);
    }


    /**
     * @notice Fulfills a swap request for a closed position with the specified position ID, user address, and output asset.
     * @param _positionID The ID of the position to fulfill the swap request for.
     * @param _data The data to be used for swapping tokens.
     * @param _swapSimple Flag to indicate if simple token swapping is allowed.
     * @param _outputAsset The address of the output asset (token) for the swap.
     * @dev The function requires that the output asset is whitelisted and the swap amount is greater than zero.
     *      The function swaps the `amountAfterFee` of USDC to `_outputAsset` using the provided `_data`.
     *      The swapped `_outputAsset` amount is transferred to the user.
     */
    function fulfilledRequestSwap(
        uint256 _positionID,
        bytes calldata _data,
        bool _swapSimple,
        address _outputAsset
    ) external nonReentrant {
        // Retrieve the amount after fee from the `closePositionAmount` mapping
        uint256 amountAfterFee = closePositionAmount[msg.sender][_positionID];
        require(isWhitelistedAsset[_outputAsset], "Sake: Invalid assets choosen");
        require(amountAfterFee > 0, "Sake: position is not enough to close");
        require(closePositionRequest[msg.sender][_positionID], "SAKE: Close only open position");

        closePositionAmount[msg.sender][_positionID] = 0;
        closePositionRequest[msg.sender][_positionID] = false;

        uint256 amountOut = _swap(amountAfterFee, _data, _swapSimple, false, _outputAsset);
        IERC20Upgradeable(_outputAsset).safeTransfer(msg.sender, amountOut);
        emit RequestFulfilled(msg.sender, amountAfterFee, amountOut);
    }

    /**
     * @notice Liquidate the position of a user if the debt-to-value (DTV) ratio reaches the liquidation threshold.
     * @dev The function can only be called once for each position ID and user address and cannot be called for already liquidated positions.
     * @param _positionId The ID of the position to be liquidated.
     * @param _user The address of the user for the position.
     * @dev The function first retrieves the user information for the given position ID and user address from the `userInfo` mapping.
     *      It checks if the position has already been liquidated and if a valid user exists for the liquidation request.
     *      The function calls the `getUpdatedDebt` function to get the current debt-to-value (DTV) ratio for the position.
     *      It checks if the DTV ratio is greater than or equal to the liquidation threshold (95%).
     *      If the MasterChef contract is specified, the function checks the user's amount staked in the MasterChef pool and performs liquidation from the pool if applicable.
     *      If the user has no amount staked in the MasterChef pool or the staked amount is less than the position, the function burns the user's VELA shares corresponding to the position amount.
     *      It then withdraws the VLP (Vela LP) tokens from the velaStakingVault using the `withdrawVlp` function of the `velaStakingVault` contract.
     *      After withdrawing the VLP tokens, the function unstakes the corresponding USDC tokens from the velaMintBurnVault using the `unstake` function of the `velaMintBurnVault` contract.
     *      The function calculates the returned value in USDC after liquidation and deducts the liquidator's reward from it.
     *      It repays the debt using the remaining amount after deducting the liquidator's reward.
     *      The liquidator's reward is transferred to the liquidator's address, and the position is marked as liquidated in the user information.
     */
    function liquidatePosition(uint256 _positionId, address _user) external nonReentrant {
        UserInfo storage _userInfo = userInfo[_user][_positionId];
        require(!_userInfo.liquidated, "Sake: Already liquidated");
        require(_userInfo.user != address(0), "Sake: liquidation request does not exist");
        (uint256 currentDTV, , ) = getUpdatedDebt(_positionId, _user);
        require(currentDTV >= (95 * 1e17) / 10, "Liquidation Threshold Has Not Reached");

        uint256 position = _userInfo.position;

        _handlePODToken(_user, position);

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

    function _getProfitSplit(uint256 _profit, uint256 _leverage) internal view returns (uint256, uint256, uint256) {
        uint256 split = (feeConfiguration.fixedFeeSplit * _leverage + (feeConfiguration.fixedFeeSplit * 10000)) / 100;
        uint256 toWater = (_profit * split) / 10000;
        uint256 mFee = (_profit * mFeePercent) / 10000;
        uint256 toSakeUser = _profit - (toWater + mFee);

        return (toWater, mFee, toSakeUser);
    }

    function _getProfitState(uint256 _positionId, address _user) internal view returns (uint256 profit) {
        (uint256 currentValues, uint256 previousValue) = getCurrentPosition(_positionId, 0, _user);
        if (currentValues > previousValue) {
            profit = currentValues - previousValue;
        }
    }

    function _convertVLPToUSDC(uint256 _amount, uint256 _vlpPrice) internal view returns (uint256) {
        return _amount.mulDiv(_vlpPrice * 10, (10 ** 18));
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
        require(assetBalAfter > assetBalBefore, "SAKE: Swap failed");
        // Return the amount of tokens received after the swap
        return (assetBalAfter - assetBalBefore);
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
}

