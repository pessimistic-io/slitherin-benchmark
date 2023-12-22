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
import {IVault} from "./IVault.sol";
import {ITokenFarm} from "./ITokenFarm.sol";

interface IWater {
    function lend(uint256 _amount) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external;

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfUSDC() external view returns (uint256);
}

import "./console.sol";

contract SakeVault is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    struct UserInfo {
        address user; // user that created the position
        uint256 deposit; // total amount of deposit
        uint256 leverage; // leverage used
        uint256 position; // position size
        uint256 price; // gToken (gUSDC) price when position was created
        bool liquidated; // true if position was liquidated
        uint256 cooldownPeriodElapse; // epoch when user can withdraw
        uint256 closedPositionValue; // value of position when closed
        address liquidator; //address of the liquidator
        uint256 closePNL;
    }

    struct FeeConfiguration {
        address feeReceiver;
        uint256 withdrawalFee;
    }

    FeeConfiguration public feeConfiguration;
    address[] public allUsers;

    address public USDC;
    address public water;
    address public velaMintBurnVault;
    address public velaStakingVault;
    address public velaSettingManager;
    address public vlpToken;
    address public esVela;
    address public VELA;
    address public MasterChef;
    uint256 public MCPID;
    uint256 public MAX_BPS;

    uint256 public constant DECIMAL = 1e18;
    uint256 public liquidatorsRewardPercentage;

    mapping(address => UserInfo[]) public userInfo;
    mapping(address => bool) public allowedSenders;
    mapping(address => bool) public burner;
    mapping(address => bool) public isUser;
    mapping(address => uint256) public userTimelock;
    mapping(address => bool) public allowedClosers;
    uint256 public fixedFeeSplit;
    uint256[50] private __gaps;

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

    /** --------------------- Event --------------------- */
    event WaterContractChanged(address newWater);
    event VaultContractChanged(address newVault, address newTokenFarm, address newSettingManager, address newVlpToken);
    event Deposit(address indexed depositer, uint256 depositTokenAmount, uint256 createdAt, uint256 vlpAmount);
    event Withdraw(address indexed user, uint256 amount, uint256 time, uint256 vlpAmount);
    event ProtocolFeeChanged(address newFeeReceiver, uint256 newWithdrawalFee);
    event LiquidatorsRewardPercentageChanged(uint256 newPercentage);
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
    event UpdateMCAndPID(address indexed _newMC, uint256 _mcpPid);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdc,
        address _water,
        address _vault,
        address _tokenFarm,
        address _velaSettingManager,
        address _velaToken
    ) external initializer {
        require(
            _usdc != address(0) &&
                _water != address(0) &&
                _vault != address(0) &&
                _tokenFarm != address(0) &&
                _velaSettingManager != address(0) &&
                _velaToken != address(0),
            "Zero address"
        );
        USDC = _usdc;
        water = _water;
        velaMintBurnVault = _vault;
        velaStakingVault = _tokenFarm;
        velaSettingManager = _velaSettingManager;
        vlpToken = _velaToken;
        esVela = address(ITokenFarm(_tokenFarm).esVELA());
        VELA = address(ITokenFarm(_tokenFarm).VELA());

        MAX_BPS = 100_000;
        liquidatorsRewardPercentage = 500;
        fixedFeeSplit = 30; //%
        

        __Ownable_init();
        __Pausable_init();
        __ERC20_init("SakePOD", "SPOD");
    }

    /** ----------- Change onlyOwner functions ------------- */

    //MC or any other whitelisted contracts
    function setAllowed(address _sender, bool _allowed) public onlyOwner zeroAddress(_sender) {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setCloser(address _closer, bool _allowed) public onlyOwner zeroAddress(_closer) {
        allowedClosers[_closer] = _allowed;
        emit SetAllowedClosers(_closer, _allowed);
    }

    function setFeeSplit(uint256 _feeSplit) public onlyOwner {
        require(_feeSplit <= 90, "Fee split cannot be more than 100%");
        fixedFeeSplit = _feeSplit;
    }

    function setBurner(address _burner, bool _allowed) public onlyOwner zeroAddress(_burner) {
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setMC(address _mc, uint256 _mcPid) public onlyOwner zeroAddress(_mc) {
        MasterChef = _mc;
        MCPID = _mcPid;
        emit UpdateMCAndPID(_mc, _mcPid);
    }

    function changeProtocolFee(address newFeeReceiver, uint256 newWithdrawalFee) external onlyOwner {
        feeConfiguration.withdrawalFee = newWithdrawalFee;
        feeConfiguration.feeReceiver = newFeeReceiver;
        emit ProtocolFeeChanged(newFeeReceiver, newWithdrawalFee);
    }

    function changeVelaContracts(
        address _vault,
        address _tokenFarm,
        address _settingManager,
        address _vlpToken
    )
        external
        onlyOwner
        zeroAddress(_vault)
        zeroAddress(_tokenFarm)
        zeroAddress(_settingManager)
        zeroAddress(_vlpToken)
    {
        velaMintBurnVault = _vault;
        velaStakingVault = _tokenFarm;
        velaSettingManager = _settingManager;
        vlpToken = _vlpToken;
        emit VaultContractChanged(_vault, _tokenFarm, _settingManager, _vlpToken);
    }

    function changeWater(address _water) external onlyOwner zeroAddress(_water) {
        water = _water;
        emit WaterContractChanged(_water);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function harvestMany(bool _vela, bool _esvela, bool _vlp, bool _vesting) external onlyOwner {
        ITokenFarm(velaStakingVault).harvestMany(_vela, _esvela, _vlp, _vesting);
    }

    function withdrawVesting() external onlyOwner {
        uint256 esVelaBeforeWithdrawal = IERC20Upgradeable(esVela).balanceOf(address(this));
        ITokenFarm(velaStakingVault).withdrawVesting();
        uint256 esVelaAfterWithdrawal = IERC20Upgradeable(esVela).balanceOf(address(this));
        IERC20Upgradeable(esVela).safeTransfer(
            feeConfiguration.feeReceiver,
            esVelaAfterWithdrawal - esVelaBeforeWithdrawal
        );
        IERC20Upgradeable(VELA).safeTransfer(
            feeConfiguration.feeReceiver,
            IERC20Upgradeable(VELA).balanceOf(address(this))
        );
    }

    // deposit vesting
    function depositVesting() external onlyOwner {
        uint256 esVelaContractBalance = IERC20Upgradeable(esVela).balanceOf(address(this));
        IERC20Upgradeable(esVela).safeApprove(velaStakingVault, esVelaContractBalance);
        ITokenFarm(velaStakingVault).depositVesting(esVelaContractBalance);
    }

    function claim() external onlyOwner {
        ITokenFarm(velaStakingVault).claim();
        IERC20Upgradeable(VELA).safeTransfer(
            feeConfiguration.feeReceiver,
            IERC20Upgradeable(VELA).balanceOf(address(this))
        );
    }

    // withdraw all vela tokens from the vault
    function withdrawAllVELA() external onlyOwner {
        IERC20Upgradeable(VELA).safeTransfer(
            feeConfiguration.feeReceiver,
            IERC20Upgradeable(VELA).balanceOf(address(this))
        );
    }

    // withdraw all esvela tokens from the vault
    function withdrawAllESVELA() external onlyOwner {
        IERC20Upgradeable(esVela).safeTransfer(
            feeConfiguration.feeReceiver,
            IERC20Upgradeable(esVela).balanceOf(address(this))
        );
    }

    function updateLiquidatorsRewardPercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= MAX_BPS, "SAKE: invalid percentage");
        liquidatorsRewardPercentage = newPercentage;
        emit LiquidatorsRewardPercentageChanged(newPercentage);
    }

    function getAllUsers() public view returns (address[] memory) {
        return allUsers;
    }

    function getClaimable() public view returns (uint256) {
        return ITokenFarm(velaStakingVault).claimable(address(this));
    }

    function getTotalNumbersOfOpenPositionBy(address user) public view returns (uint256) {
        return userInfo[user].length;
    }

    function getUpdatedDebtAndValue(
        uint256 positionID,
        address user
    ) public view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt) {
        UserInfo memory _userInfo = userInfo[user][positionID];

        uint256 previousValueInUSDC;
        (currentPosition, previousValueInUSDC) = getCurrentPosition(positionID, user);

        uint256 profitOrLoss;
        uint256 getFeeSplit;
        uint256 rewardSplitToWater;
        uint256 owedToWater;

        if (currentPosition > previousValueInUSDC) {
            profitOrLoss = currentPosition - previousValueInUSDC;
            getFeeSplit = fixedFeeSplit;
            rewardSplitToWater = (profitOrLoss * getFeeSplit) / 100;
            owedToWater = _userInfo.leverage + rewardSplitToWater;
        } else if (previousValueInUSDC > currentPosition) {
            owedToWater = _userInfo.leverage;
        } else {
            owedToWater = _userInfo.leverage;
        }
        currentDTV = owedToWater.mulDiv(DECIMAL, currentPosition);

        return (currentDTV, currentPosition, owedToWater);
    }

    function getCurrentPosition(
        uint256 positionID,
        address user
    ) public view returns (uint256 currentPosition, uint256 previousValueInUSDC) {
        UserInfo memory _userInfo = userInfo[user][positionID];
        if (_userInfo.closedPositionValue == 0) {
            currentPosition = convertVLPToUSDC(_userInfo.position, getVLPPrice());
        } else {
            currentPosition = _userInfo.closedPositionValue;
        }
        previousValueInUSDC = convertVLPToUSDC(_userInfo.position, _userInfo.price);

        return (currentPosition, previousValueInUSDC);
    }

    function convertVLPToUSDC(uint256 _amount, uint256 _vlpPrice) public pure returns (uint256) {
        return _amount.mulDiv(_vlpPrice * 10, (10 ** 18));
    }

    function getVLPPrice() public view returns (uint256) {
        return IVault(velaMintBurnVault).getVLPPrice();
    }

    function getVlpBalance() public view returns (uint256) {
        return IERC20Upgradeable(vlpToken).balanceOf(address(this));
    }

    function getStakedVlpBalance() public view returns (uint256) {
        return ITokenFarm(velaStakingVault).getStakedVLP(address(this));
    }

    function getVelaCooldownPeriod() public view returns (uint256) {
        uint256 cooldown = ISettingManager(velaSettingManager).cooldownDuration();
        return cooldown;
    }

    /**
     * @notice Token Deposit
     * @dev Users can deposit with USDC
     * @param amount Deposit token amount
     */
    function openPosition(uint256 amount) external whenNotPaused {
        IERC20Upgradeable(USDC).safeTransferFrom(msg.sender, address(this), amount);
        uint256 leverage = amount * 2;

        bool status = IWater(water).lend(leverage);
        require(status, "Water: Lend failed");

        // Actual deposit amount to Gains network
        uint256 xAmount = amount + leverage;

        IERC20Upgradeable(USDC).safeApprove(velaMintBurnVault, xAmount);
        uint256 balanceBefore = getVlpBalance();
        IVault(velaMintBurnVault).stake(address(this), USDC, xAmount);
        uint256 balanceAfter = getVlpBalance();

        uint256 velaShares = balanceAfter - balanceBefore;
        IERC20Upgradeable(vlpToken).safeApprove(velaStakingVault, velaShares);
        ITokenFarm(velaStakingVault).depositVlp(velaShares);

        UserInfo memory _userInfo = UserInfo({
            user: msg.sender,
            deposit: amount,
            leverage: leverage,
            position: velaShares,
            price: getVLPPrice(),
            liquidated: false,
            cooldownPeriodElapse: block.timestamp + getVelaCooldownPeriod(),
            closedPositionValue: 0,
            liquidator: address(0),
            closePNL: 0
        });

        //frontend helper to fetch all users and then their userInfo
        if (isUser[msg.sender] == false) {
            isUser[msg.sender] = true;
            allUsers.push(msg.sender);
        }

        userInfo[msg.sender].push(_userInfo);
        _mint(msg.sender, velaShares);
        emit Deposit(msg.sender, amount, block.timestamp, velaShares);
    }

    function closePosition(
        uint256 _positionID,
        address _user
    ) external whenNotPaused InvalidID(_positionID, _user) nonReentrant {
        UserInfo storage _userInfo = userInfo[_user][_positionID];
        uint256 userPosition = _userInfo.position;
        require(!_userInfo.liquidated, "Sake: position is liquidated");
        require(userPosition > 0, "Sake: position is not enough to close");
        require(block.timestamp >= _userInfo.cooldownPeriodElapse, "Sake: user timelock not expired");
        require(allowedClosers[msg.sender] || msg.sender == _userInfo.user, "SAKE: not allowed to close position");

        _burn(_userInfo.user, _userInfo.position);

        IERC20Upgradeable(vlpToken).safeApprove(velaStakingVault, userPosition);
        uint256 vlpBalanceBeforeWithdrawal = getVlpBalance();
        ITokenFarm(velaStakingVault).withdrawVlp(userPosition);
        uint256 vlpBalanceAfterWithdrawal = getVlpBalance();

        uint256 usdcBalanceBefore = IERC20Upgradeable(USDC).balanceOf(address(this));
        uint256 vlpAmount = (vlpBalanceAfterWithdrawal - vlpBalanceBeforeWithdrawal);
        IVault(velaMintBurnVault).unstake(USDC, vlpAmount);
        uint256 usdcBalanceAfter = IERC20Upgradeable(USDC).balanceOf(address(this));
        uint256 returnedValue = usdcBalanceAfter - usdcBalanceBefore;

        _userInfo.closedPositionValue = returnedValue;
        (uint256 currentDTV, , uint256 debtValue) = getUpdatedDebtAndValue(_positionID, _user);

        _userInfo.position = 0;

        uint256 afterLoanPayment;
        if (currentDTV >= (9 * DECIMAL) / 10 || returnedValue < debtValue) {
            // @dev return asset in USDC can still be greater than debtValue
            // even when current dtv is greater than 90% in some cases
            _userInfo.liquidated = true;
            IERC20Upgradeable(USDC).safeApprove(water, returnedValue);
            IWater(water).repayDebt(_userInfo.leverage, returnedValue);
            return;
        } else {
            afterLoanPayment = returnedValue - debtValue;
        }

        IERC20Upgradeable(USDC).safeApprove(water, debtValue);
        IWater(water).repayDebt(_userInfo.leverage, debtValue);

        // take protocol fee
        uint256 amountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = afterLoanPayment.mulDiv(feeConfiguration.withdrawalFee, MAX_BPS);
            IERC20Upgradeable(USDC).safeTransfer(feeConfiguration.feeReceiver, fee);
            amountAfterFee = afterLoanPayment - fee;
        } else {
            amountAfterFee = afterLoanPayment;
        }
        IERC20Upgradeable(USDC).safeTransfer(_user, amountAfterFee);
        _userInfo.closePNL = amountAfterFee;
        emit Withdraw(_user, amountAfterFee, block.timestamp, vlpAmount);
    }

    function liquidatePosition(address _user, uint256 _positionId) external nonReentrant {
        UserInfo storage _userInfo = userInfo[_user][_positionId];
        require(!_userInfo.liquidated, "Sake: Already liquidated");
        require(_userInfo.user != address(0), "Sake: liquidation request does not exist");
        (uint256 currentDTV, , ) = getUpdatedDebtAndValue(_positionId, _user);
        require(currentDTV >= (9 * DECIMAL) / 10, "Liquidation Threshold Has Not Reached");
        uint256 position = _userInfo.position;

        uint256 userAmountStaked;
        if (MasterChef != address(0)) {
            (userAmountStaked, ) = IMasterChef(MasterChef).userInfo(MCPID, _user);
            if (userAmountStaked > 0) {
                uint256 amountToBurnFromUser;
                if(userAmountStaked > position) {
                    amountToBurnFromUser = position;
                } else {
                    amountToBurnFromUser = userAmountStaked;
                    uint256 _position = position - userAmountStaked;
                    _burn(_user, _position);
                }                
                IMasterChef(MasterChef).unstakeAndLiquidate(MCPID, _user, amountToBurnFromUser);
            }
        }
        
        if (userAmountStaked == 0) {
            _burn(_user, position);
        }

        IERC20Upgradeable(vlpToken).approve(velaStakingVault, _userInfo.position);
        uint256 vlpBalanceBeforeWithdrawal = getVlpBalance();
        ITokenFarm(velaStakingVault).withdrawVlp(position);
        uint256 vlpBalanceAfterWithdrawal = getVlpBalance();

        uint256 usdcBalanceBefore = IERC20Upgradeable(USDC).balanceOf(address(this));
        IVault(velaMintBurnVault).unstake(USDC, (vlpBalanceAfterWithdrawal - vlpBalanceBeforeWithdrawal));
        uint256 usdcBalanceAfter = IERC20Upgradeable(USDC).balanceOf(address(this));
        uint256 returnedValue = usdcBalanceAfter - usdcBalanceBefore;

        _userInfo.liquidator = msg.sender;

        uint256 liquidatorReward = returnedValue.mulDiv(liquidatorsRewardPercentage, MAX_BPS);
        // deduct liquidator reward from returnedAssetInUSDC
        uint256 amountAfterLiquidatorReward = returnedValue - liquidatorReward;
        // repay debt
        IERC20Upgradeable(USDC).safeApprove(water, amountAfterLiquidatorReward);
        IWater(water).repayDebt(_userInfo.leverage, amountAfterLiquidatorReward);

        IERC20Upgradeable(USDC).safeTransfer(msg.sender, liquidatorReward);
    }

    function getUtilizationRate() public view returns (uint256) {
        uint256 totalWaterDebt = IWater(water).totalDebt();
        uint256 totalWaterAssets = IWater(water).balanceOfUSDC();
        return totalWaterDebt == 0 ? 0 : totalWaterDebt.mulDiv(DECIMAL, totalWaterAssets + totalWaterDebt);
    }

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
}

