// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./ITokenBurnable.sol";
import "./IOpenTradesPnlFeed.sol";
import "./IGainsVault.sol";
import "./IMasterChef.sol";
import "./ILendingVault.sol";

//import "hardhat/console.sol";

contract LeverageVaultV7 is
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  ERC20BurnableUpgradeable
{
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using MathUpgradeable for uint256;
  using MathUpgradeable for uint128;

  struct UserInfo {
    address user; // user that created the position
    uint256 deposit; // total amount of deposit
    uint256 leverage; // leverage used
    uint256 position; // position size
    uint256 price; // gToken (gDAI) price when position was created
    bool liquidated; // true if position was liquidated
    bool withdrawalRequested; // true if user requested withdrawal
    uint256 epochUnlock; // epoch when user can withdraw
    uint256 closedPositionValue; // value of position when closed
  }

  struct LiquidationRequests {
    uint256 positionID; // position ID
    address user; // user that created the position
    uint256 leverage; // leverage used
    uint256 epochUnlock; // epoch when liquation can be executed
    address liquidatorRequestForWithdrawal; // address of liquidator that requested withdrawal
    address liquidator; // address of liquidator that executed liquidation
  }

  struct FeeSplitStrategyInfo {
    // slope 1 used to control the change of reward fee split when reward is inbetween  0-40%
    uint128 maxFeeSplitSlope1;
    // slope 2 used to control the change of reward fee split when reward is inbetween  40%-80%
    uint128 maxFeeSplitSlope2;
    // slope 3 used to control the change of reward fee split when reward is inbetween  80%-100%
    uint128 maxFeeSplitSlope3;
    uint128 utilizationThreshold1;
    uint128 utilizationThreshold2;
    uint128 utilizationThreshold3;
  }

  struct FeeConfiguration {
    address feeReceiver;
    uint256 withdrawalFee;
  }

  FeeSplitStrategyInfo public feeStrategy;
  FeeConfiguration public feeConfiguration;
  LiquidationRequests[] public liquidationRequests;
  address[] public allUsers;

  address public dai; // DAI
  address public gainsVault;
  address public lendingVault;
  address public MasterChef;
  address public openPNL;
  uint256 public MCPID;
  uint256 public MAX_BPS;
  

  uint256 public constant DECIMAL = 1e18;
  uint256 public liquidatorsRewardPercentage;
  uint256[50] private __gaps;

  mapping(address => UserInfo[]) public userInfo;
  mapping(uint256 => bool) public isPositionLiquidated;
  mapping(address => bool) public allowedSenders;
  mapping(address => bool) public burner;
  mapping(address => bool) public isUser;
  mapping(address => bool) public allowedClosers;
  
  uint256 public fixedFeeSplit;

  modifier InvalidID(uint256 positionId,address user) {
    require(
      positionId < userInfo[user].length,
      "Whiskey: positionID is not valid"
    );
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
  event LendingVaultChanged(address newLendingVault);
  event GainsAddressesChanged(address newGainsVault);
  event Deposit(
    address indexed depositer,
    uint256 depositTokenAmount,
    uint256 createdAt,
    uint256 GDAIAmount
  );
  event PendingWithdrawRequested(
    address indexed owner,
    uint256 positionId,
    uint256 position,
    uint256 createdAt,
    uint256 epochUnlock
  );
  event Withdraw(address indexed user, uint256 amount, uint256 time, uint256 GDAIAmount);
  event FeeStrategyUpdated(FeeSplitStrategyInfo newFeeStrategy);
  event ProtocolFeeChanged(
    address newFeeReceiver,
    uint256 newWithdrawalFee
  );
  event LiquidationRequest(
    address indexed liquidator,
    address indexed borrower,
    uint256 positionId,
    uint256 time
  );
  event LiquidatorsRewardPercentageChanged(uint256 newPercentage);
  event Liquidation(
    address indexed liquidator,
    address indexed borrower,
    uint256 positionId,
    uint256 liquidatedAmount,
    uint256 outputAmount,
    uint256 time
  );
  event SetAllowaedClosers(address indexed closer, bool allowed);
  event SetAllowedSenders(address indexed sender, bool allowed);
  event SetBurner(address indexed burner, bool allowed);
  event UpdateMCAndPID(address indexed _newMC, uint256 _mcpPid);


  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _dai,
    address _gDAI,
    address _lendingVault,
    address _openPNL
  ) external initializer {
    require(_dai != address(0) &&
      _gDAI != address(0) &&
      _lendingVault != address(0) &&
      _openPNL != address(0), "Zero address");
    dai = _dai;
    gainsVault = _gDAI;
    lendingVault = _lendingVault;
    openPNL = _openPNL;

    MAX_BPS = 100_000;
    liquidatorsRewardPercentage = 500;

    __Ownable_init();
    __Pausable_init();
    __ERC20_init("WhiskeyPOD", "WPOD");
  }

  /** ----------- Change onlyOwner functions ------------- */

  //MC or any other whitelisted contracts
  function setAllowed(address _sender, bool _allowed) public onlyOwner zeroAddress(_sender) {
    allowedSenders[_sender] = _allowed;
    emit SetAllowedSenders(_sender, _allowed);
  }

  function setFeeSplit(uint256 _feeSplit) public onlyOwner {
    require(_feeSplit <= 90, "Fee split cannot be more than 100%");
    fixedFeeSplit = _feeSplit;
  }

  function setBurner(address _burner,bool _allowed) public onlyOwner zeroAddress(_burner) {
    burner[_burner] = _allowed;
    emit SetBurner(_burner, _allowed);
  }
  
  function setMC(address _mc, uint256 _mcPid) public onlyOwner zeroAddress(_mc) {
    MasterChef = _mc;
    MCPID = _mcPid;
    emit UpdateMCAndPID(_mc, _mcPid);
  }

  function setCloser(address _closer,bool _allowed) public onlyOwner zeroAddress(_closer) {
    allowedClosers[_closer] = _allowed;
    emit SetAllowaedClosers(_closer, _allowed);
  }

  function changeProtocolFee(
    address newFeeReceiver,
    uint256 newWithdrawalFee
  ) external onlyOwner {
    feeConfiguration.withdrawalFee = newWithdrawalFee;
    feeConfiguration.feeReceiver = newFeeReceiver;
    emit ProtocolFeeChanged(newFeeReceiver, newWithdrawalFee);
  }

  function changeGainsContracts(
    address _gainsVault,
    address _openPNL
  ) external onlyOwner zeroAddress(_gainsVault) zeroAddress(_openPNL) {
    gainsVault = _gainsVault;
    openPNL = _openPNL;
    emit GainsAddressesChanged(_gainsVault);
  }

  function changeLendingVault(
    address _lendingVault
  ) external onlyOwner zeroAddress(_lendingVault) {
    lendingVault = _lendingVault;
    emit LendingVaultChanged(_lendingVault);
  }

  function updateFeeStrategyParams(
    FeeSplitStrategyInfo calldata _feeStrategy
  ) external onlyOwner {
    require(
        _feeStrategy.maxFeeSplitSlope1 >= 0 &&
        _feeStrategy.maxFeeSplitSlope1 <= DECIMAL &&
        _feeStrategy.maxFeeSplitSlope2 >= _feeStrategy.maxFeeSplitSlope1 &&
        _feeStrategy.maxFeeSplitSlope2 <= DECIMAL &&
        _feeStrategy.maxFeeSplitSlope3 >= _feeStrategy.maxFeeSplitSlope2 &&
        _feeStrategy.maxFeeSplitSlope3 <= DECIMAL &&
        _feeStrategy.utilizationThreshold1 >= 0 &&
        _feeStrategy.utilizationThreshold1 <=
        _feeStrategy.utilizationThreshold2 &&
        _feeStrategy.utilizationThreshold2 >=
        _feeStrategy.utilizationThreshold1 &&
        _feeStrategy.utilizationThreshold2 <=
        _feeStrategy.utilizationThreshold3 &&
        _feeStrategy.utilizationThreshold3 >=
        _feeStrategy.utilizationThreshold2 &&
        _feeStrategy.utilizationThreshold3 <= DECIMAL,
      "Invalid fee strategy parameters"
    );

    feeStrategy = _feeStrategy;
    emit FeeStrategyUpdated(_feeStrategy);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function updateLiquidatorsRewardPercentage(uint256 newPercentage) external onlyOwner {
    require(newPercentage <= MAX_BPS, "Whiskey: invalid percentage");
    liquidatorsRewardPercentage = newPercentage;
    emit LiquidatorsRewardPercentageChanged(newPercentage);
  }

  function getAllUsers() public view returns (address[] memory) {
    return allUsers;
  }

  function getTotalNumbersOfOpenPositionBy(address user) public view returns (uint256) {
    return userInfo[user].length;
  }

  function getGainsBalance() public view returns (uint256) {
    return IGainsVault(gainsVault).balanceOf(address(this));
  }

  function getPositionUnlockEpoch(uint256 positionID,address user, bool state) public view returns (bool) {
    bool canBeUnlocked;
    uint256 currentGainsEpoch = IGainsVault(gainsVault).currentEpoch();

    if (state) {
      UserInfo memory _userInfo = userInfo[user][positionID];
      if (currentGainsEpoch == _userInfo.epochUnlock && IOpenTradesPnlFeed(openPNL).nextEpochValuesRequestCount() == 0) {
        canBeUnlocked = true;
      } else {
        canBeUnlocked = false;
      }
    } else {
      LiquidationRequests memory liquidationRequest = liquidationRequests[positionID];
      if (currentGainsEpoch == liquidationRequest.epochUnlock) {
        canBeUnlocked = true;
      } else {
        canBeUnlocked = false;
      }
    }
    
    return canBeUnlocked;
  }

  function getUpdatedDebtAndValue(
    uint256 positionID,
    address user
  )
    public
    view
    returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt)
  {
    UserInfo memory _userInfo = userInfo[user][positionID];
    if (_userInfo.position == 0 || _userInfo.liquidated) return (0, 0, 0);

    uint256 previousValueInDAI;
    (currentPosition, previousValueInDAI) = getCurrentPosition(
      positionID,
      user
    );

    uint256 profitOrLoss;
    uint256 getFeeSplit;
    uint256 rewardSplitToWater;
    uint256 owedToWater;

    if (currentPosition > previousValueInDAI) {
      profitOrLoss = currentPosition - previousValueInDAI;
      getFeeSplit = fixedFeeSplit;
      rewardSplitToWater = profitOrLoss * getFeeSplit / 100;
      owedToWater = _userInfo.leverage + rewardSplitToWater;
    } 
    else if (previousValueInDAI > currentPosition){
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
  ) public view returns (uint256 currentPosition, uint256 previousValueInDAI) {
    UserInfo memory _userInfo = userInfo[user][positionID];
    uint256 userPosition;
    if (_userInfo.closedPositionValue == 0) {
      userPosition = _userInfo.position;
      currentPosition = userPosition.mulDiv(gTokenPrice(), DECIMAL);
    } else {
      currentPosition = _userInfo.closedPositionValue;
    }
    previousValueInDAI = _userInfo.position.mulDiv(_userInfo.price, DECIMAL);
    
    
    return (currentPosition, previousValueInDAI);
  }

  /**
   * @notice Token Deposit
   * @dev Users can deposit with DAI
   * @param amount Deposit token amount
   * @param user User address
   */
  function openPosition(uint256 amount, address user) external whenNotPaused {
    IERC20Upgradeable(dai).safeTransferFrom(msg.sender, address(this), amount);
    user = msg.sender;
    uint256 leverage = amount * 2;
    
    bool status = ILendingVault(lendingVault).lend(leverage);
    require(status, "LendingVault: Lend failed");

    // Actual deposit amount to Gains network
    uint256 xAmount = amount + leverage;

    IERC20Upgradeable(dai).safeApprove(gainsVault, xAmount);
    uint256 balanceBefore = getGainsBalance();

    IGainsVault(gainsVault).deposit(xAmount, address(this));
    
    uint256 balanceAfter = getGainsBalance();
    uint256 gdaiShares = balanceAfter - balanceBefore;

    UserInfo memory _userInfo = UserInfo({
      user: user,
      deposit: amount,
      leverage: leverage,
      position: gdaiShares,
      price: gTokenPrice(),
      liquidated: false,
      withdrawalRequested: false,
      epochUnlock: 0,
      closedPositionValue: 0
    });

    //frontend helper to fetch all users and then their userInfo
    if (isUser[msg.sender] == false) {
      isUser[msg.sender] = true;
      allUsers.push(msg.sender);
    } 

    userInfo[msg.sender].push(_userInfo);
    _mint(msg.sender, gdaiShares);

    emit Deposit(msg.sender, amount, block.timestamp, gdaiShares);
  }

  function closePosition(
    uint256 positionID,
    address _user
  ) external whenNotPaused InvalidID(positionID,_user) nonReentrant {
    UserInfo storage _userInfo = userInfo[_user][positionID];
    require(!_userInfo.liquidated, "Whiskey: position is liquidated");
    require(_userInfo.position > 0, "Whiskey: position is not enough to close");
    require(_userInfo.withdrawalRequested,"Whiskey: user has not requested a withdrawal");
    require(getPositionUnlockEpoch(positionID, _user, true), "Whiskey: position is not unlocked yet");
    require(allowedClosers[msg.sender] || msg.sender == _userInfo.user, "Whiskey: not allowed to close position");

    uint256 balanceBefore = IERC20Upgradeable(dai).balanceOf(address(this));
    uint256 returnedAssetInDAI = IGainsVault(gainsVault).redeem(
      _userInfo.position,
      address(this),
      address(this)
    );
    uint256 balanceAfter = IERC20Upgradeable(dai).balanceOf(address(this));
    _userInfo.closedPositionValue = balanceAfter - balanceBefore;

    (uint256 currentDTV, , uint256 debtValue) = getUpdatedDebtAndValue(positionID, _user);

    _userInfo.position = 0;

    uint256 afterLoanPayment;
    if (currentDTV >= (9 * DECIMAL) / 10 || returnedAssetInDAI < debtValue) {
      _userInfo.liquidated = true;
      IERC20Upgradeable(dai).safeApprove(lendingVault, returnedAssetInDAI);
      ILendingVault(lendingVault).repayDebt(_userInfo.leverage, returnedAssetInDAI);
      emit LiquidationRequest(_user, _user, positionID, block.timestamp);
      return;
    } else {
      afterLoanPayment = returnedAssetInDAI - debtValue;
    }

    IERC20Upgradeable(dai).safeApprove(lendingVault, debtValue);
    ILendingVault(lendingVault).repayDebt(_userInfo.leverage, debtValue);

    // take protocol fee
    uint256 amountAfterFee;
    if (feeConfiguration.withdrawalFee > 0) {
      uint256 fee = afterLoanPayment.mulDiv(
        feeConfiguration.withdrawalFee,
        MAX_BPS
      );
      IERC20Upgradeable(dai).safeTransfer(feeConfiguration.feeReceiver, fee);
      amountAfterFee = afterLoanPayment - fee;
    } else {
      amountAfterFee = afterLoanPayment;
    }
    IERC20Upgradeable(dai).safeTransfer(_user, amountAfterFee);
    emit Withdraw(_user, amountAfterFee, block.timestamp, _userInfo.closedPositionValue);
  }

  function requestLiquidationPosition(uint256 positionId, address user) external {
    UserInfo storage _userInfo = userInfo[user][positionId];
    uint256 userPosition = _userInfo.position;
    require(!_userInfo.liquidated, "Whiskey: position is liquidated");
    require(userPosition > 0, "Whiskey: position is not enough to close");
    (uint256 currentDTV, ,) = getUpdatedDebtAndValue(positionId, user);
    require(currentDTV >= (9 * DECIMAL) / 10, "Liquidation Threshold Has Not Reached");

    //delete any amounts staked in MC or user wallet. We assume only the MC is whitelisted to stake.
    uint256 userAmountStaked;
    if (MasterChef != address(0)) {
        (userAmountStaked,) = IMasterChef(MasterChef).userInfo(MCPID,user);
        if (userAmountStaked > 0) {
          IMasterChef(MasterChef).unstakeAndLiquidate(MCPID, user, userPosition);
        }
    }
    
    if (userAmountStaked == 0) {
      _burn(user, userPosition);
    }
    
    IGainsVault(gainsVault).makeWithdrawRequest(userPosition, address(this));

    _userInfo.liquidated = true;

    liquidationRequests.push(
      LiquidationRequests({
        positionID: positionId,
        user: user,
        leverage: _userInfo.leverage,
        epochUnlock : getWithdrawableEpochTime(),
        liquidatorRequestForWithdrawal: msg.sender,
        liquidator: address(0)
      })
    );

    emit LiquidationRequest(msg.sender, user, positionId, block.timestamp);
  }

  function liquidatePosition(uint256 liquidationId) external {
    LiquidationRequests storage liquidationRequest = liquidationRequests[liquidationId];
    require(!isPositionLiquidated[liquidationId], "Whiskey: Not Liquidatable");
    require(liquidationRequest.user != address(0), "Whiskey: liquidation request does not exist");
    require(getPositionUnlockEpoch(liquidationId, address(this), false), "Whiskey: position is not unlocked yet");
    uint256 position = userInfo[liquidationRequest.user][liquidationRequest.positionID].position;
    // redeem all asset from gains vault
    uint256 returnedAssetInDAI = IGainsVault(gainsVault).redeem(
      position,
      address(this),
      address(this)
    );
    liquidationRequest.liquidator = msg.sender;
    isPositionLiquidated[liquidationId] = true;

    // liquidaorsRewardPercentage
    // liquidator and liquidatorRequestForWithdrawal can share the reward
    // @dev taking liquidation reward from returnedAssetInDAI instead
    // of checking if returnedAssetInDAI is greater than debtValue
    // if yes then remove the debt value first and then take liquidation reward from  remnant
    // then the remaining should be added to the debt value as water users bonus
    uint256 liquidatorReward = returnedAssetInDAI.mulDiv(
      liquidatorsRewardPercentage,
      MAX_BPS
    );
    // deduct liquidator reward from returnedAssetInDAI
    uint256 amountAfterLiquidatorReward = returnedAssetInDAI - liquidatorReward;
    // repay debt
    IERC20Upgradeable(dai).safeApprove(lendingVault, amountAfterLiquidatorReward);
    ILendingVault(lendingVault).repayDebt(liquidationRequest.leverage, amountAfterLiquidatorReward);

    if (msg.sender != liquidationRequest.liquidatorRequestForWithdrawal) {
      uint256 liquidatorRequestForWithdrawalReward = liquidatorReward / 2;
      IERC20Upgradeable(dai).safeTransfer(
        liquidationRequest.liquidatorRequestForWithdrawal,
        liquidatorRequestForWithdrawalReward
      );
      IERC20Upgradeable(dai).safeTransfer(
        msg.sender,
        liquidatorReward - liquidatorRequestForWithdrawalReward
      );
    } else {
      IERC20Upgradeable(dai).safeTransfer(msg.sender, liquidatorReward);
    }
    // emit event
    emit Liquidation(
      liquidationRequest.liquidator,
      liquidationRequest.user,
      liquidationRequest.positionID,
      position,
      liquidatorReward,
      block.timestamp
    );
  }

  function makeWithdrawRequestWithAssets(
    uint256 positionId
  ) public InvalidID(positionId,msg.sender) {
    UserInfo storage _userInfo = userInfo[msg.sender][positionId];
    require(!_userInfo.liquidated, "Whiskey: position is liquidated");
    require(_userInfo.position > 0, "Whiskey: position is not enough to close");

    //normal unstake from MC/redeem flow, user needs to unstake from MC then redeem if staked
    ITokenBurnable(address(this)).burnFrom(msg.sender,_userInfo.position);
    require(IOpenTradesPnlFeed(openPNL).nextEpochValuesRequestCount() == 0, "Whiskey: gdai next epoch values request count is not 0");
    IGainsVault(gainsVault).makeWithdrawRequest(_userInfo.position, address(this));

    // withdrawal request can be made multiple time cause if user did not withdraw
    // GDAi will be staked in the next epoch
    _userInfo.withdrawalRequested = true;
    _userInfo.epochUnlock = getWithdrawableEpochTime();
    emit PendingWithdrawRequested(
        msg.sender,
        positionId,
        _userInfo.position,
        block.timestamp,
        _userInfo.epochUnlock
    );
  }

  function getWithdrawableEpochTime() public view returns (uint256) {
    return IGainsVault(gainsVault).currentEpoch() + IGainsVault(gainsVault).withdrawEpochsTimelock();
  }

  function totalShares() public view returns (uint256) {
    return IERC20Upgradeable(gainsVault).balanceOf(address(this));
  }

  function gTokenPrice() public view returns (uint256) {
    return IGainsVault(gainsVault).shareToAssetsPrice();
  }

  function calculateFeeSplit() public view returns (uint256 feeSplitRate) {
    uint256 utilizationRate = getUtilizationRate();
    if (utilizationRate <= feeStrategy.utilizationThreshold1) {
      /* Slope 1
            rewardFee_{slope2} =  
                {maxFeeSplitSlope1 *  {(utilization Ratio / URThreshold1)}}
            */
      feeSplitRate = (feeStrategy.maxFeeSplitSlope1).mulDiv(
        utilizationRate,
        feeStrategy.utilizationThreshold1
      );
    } else if (
      utilizationRate > feeStrategy.utilizationThreshold1 &&
      utilizationRate < feeStrategy.utilizationThreshold2
    ) {
      /* Slope 2
            rewardFee_{slope2} =  
                maxFeeSplitSlope1 + 
                {(utilization Ratio - URThreshold1) / 
                (1 - UR Threshold1 - (UR Threshold3 - URThreshold2)}
                * (maxFeeSplitSlope2 -maxFeeSplitSlope1) 
            */
      uint256 subThreshold1FromUtilizationRate = utilizationRate -
        feeStrategy.utilizationThreshold1;
      uint256 maxBpsSubThreshold1 = DECIMAL - feeStrategy.utilizationThreshold1;
      uint256 threshold3SubThreshold2 = feeStrategy.utilizationThreshold3 -
        feeStrategy.utilizationThreshold2;
      uint256 mSlope2SubMSlope1 = feeStrategy.maxFeeSplitSlope2 -
        feeStrategy.maxFeeSplitSlope1;
      uint256 feeSlpope = maxBpsSubThreshold1 - threshold3SubThreshold2;
      uint256 split = subThreshold1FromUtilizationRate.mulDiv(
        DECIMAL,
        feeSlpope
      );
      feeSplitRate = mSlope2SubMSlope1.mulDiv(split, DECIMAL);
      feeSplitRate = feeSplitRate + (feeStrategy.maxFeeSplitSlope1);
    } else if (
      utilizationRate > feeStrategy.utilizationThreshold2 &&
      utilizationRate < feeStrategy.utilizationThreshold3
    ) {
      /* Slope 3
            rewardFee_{slope3} =  
                maxFeeSplitSlope2 + {(utilization Ratio - URThreshold2) / 
                (1 - UR Threshold2}
                * (maxFeeSplitSlope3 -maxFeeSplitSlope2) 
            */
      uint256 subThreshold2FromUtilirationRatio = utilizationRate -
        feeStrategy.utilizationThreshold2;
      uint256 maxBpsSubThreshold2 = DECIMAL - feeStrategy.utilizationThreshold2;
      uint256 mSlope3SubMSlope2 = feeStrategy.maxFeeSplitSlope3 -
        feeStrategy.maxFeeSplitSlope2;
      uint256 split = subThreshold2FromUtilirationRatio.mulDiv(
        DECIMAL,
        maxBpsSubThreshold2
      );

      feeSplitRate =
        (split.mulDiv(mSlope3SubMSlope2, DECIMAL)) +
        (feeStrategy.maxFeeSplitSlope2);
    }
    return feeSplitRate;
  }

  function getUtilizationRate() public view returns (uint256) {
    uint256 totalWaterDebt = ILendingVault(lendingVault).totalDebt();
    uint256 totalWaterAssets = ILendingVault(lendingVault).balanceOfDAI();
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
