// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC721Enumerable.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IGeNftDescriptor.sol";
import "./IGoodEntryPositionManager.sol";
import "./IVaultConfigurator.sol";
import "./IGoodEntryVault.sol";
import "./IGoodEntryCore.sol";
import "./IReferrals.sol";
import "./StrikeManager.sol";
import "./GoodEntryCommons.sol";


contract GoodEntryPositionManager is GoodEntryCommons, ERC721Enumerable, IGoodEntryPositionManager {
  using SafeERC20 for ERC20;

  event OpenedPosition(address indexed user, bool indexed isCall, uint indexed strike, uint amount, uint tokenId);
  event ClosedPosition(address indexed user, address closer, uint tokenId, int pnl);

  mapping(uint => Position) private _positions;
  uint private _nextPositionId;
  
  uint public openInterestCalls;
  uint public openInterestPuts;
  mapping(uint => uint) public strikeToOpenInterestCalls;
  mapping(uint => uint) public strikeToOpenInterestPuts;
  /// @notice Tracks all strikes with non zero OI
  mapping(uint => uint) private openStrikeIds;
  uint[] public openStrikes;
  
  /// @notice Vault from which to borrow
  address public vault;
  /// @notice Referrals contract
  IReferrals private referrals;

  // maximum OI in percent of total vault assets
  uint8 private constant MAX_UTILIZATION_RATE = 60;
  // time to expiry for streaming options
  uint private constant STREAMING_OPTION_TTE = 21600;
  // min position size: avoid dust sized positions that create liquidation issues
  uint private constant MIN_POSITION_VALUE_X8 = 50e8;
  // @notice flat closing gas fee if position closed by 3rd party // currently based on USDC 6 decimals
  uint private constant FIXED_EXERCISE_FEE = 4e6;
  
  uint private constant YEARLY_SECONDS = 31_536_000;
  uint private constant UINT256MAX = type(uint256).max;
  // Max open strikes as looping on strikes to get amounts due is costly, excess would break. when reaching max, allow forced liquidations
  uint private constant MAX_OPEN_STRIKES = 200; 
  // Min amount of collateral in a streaming position
  uint private constant MIN_COLLATERAL_AMOUNT = 1e6;
  // Min/max tte for regular options
  uint private constant MIN_FIXED_OPTIONS_TTE = 86400;
  uint private constant MAX_FIXED_OPTIONS_TTE = 86400 * 10;
  // Address of the NFT descriptor library beacon
  address private constant GENFT_PROXY = 0xBFD31f052d1dD207Bc4FfD9DD60EF2E00b9b531E;
  // Max strike distance to avoid DOS attacks by opening very deep OTM options with low cost and filling up allowed open strikes pool
  uint8 private constant MAX_STRIKE_DISTANCE_X2 = 25;
  

  constructor() ERC721("GoodEntry V2 Positions", "GEP") {}

  function initProxy(address _oracle, address _baseToken, address _quoteToken, address _vault, address _referrals) public {
    require(vault == address(0x0), "PM: Already Init");
    vault = _vault;
    baseToken = ERC20(_baseToken);
    quoteToken  = ERC20(_quoteToken);
    oracle = IGoodEntryOracle(_oracle);
    openStrikes.push(0); // dummy value, invalid openStrikeIds
    referrals = IReferrals(_referrals);
  }
  
  
  /// @notice Getter for pm parameters
  function getParameters() public view returns (uint, uint, uint, uint, uint, uint, uint8, uint8) {
    return (
      MIN_POSITION_VALUE_X8, 
      MIN_COLLATERAL_AMOUNT, 
      FIXED_EXERCISE_FEE, 
      STREAMING_OPTION_TTE, 
      MIN_FIXED_OPTIONS_TTE, 
      MAX_FIXED_OPTIONS_TTE, 
      MAX_UTILIZATION_RATE, 
      MAX_STRIKE_DISTANCE_X2
    );
  }


  /// @notice Get open strikes length
  function getOpenStrikesLength() public view returns (uint) { return openStrikes.length; }

  
  /// @notice Get position by Id
  function getPosition(uint tokenId) public view returns (Position memory) {
    return _positions[tokenId];
  }
  
  /// @notice Get a nice NFT representation of a position
  function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
    Position memory position = _positions[tokenId];
    (, uint pnl) = getValueAtStrike(position.isCall, IGoodEntryVault(vault).getBasePrice(), position.strike, position.notionalAmount);
    int actualPnl = int(pnl) - int(getFeesAccumulated(tokenId));
    return IGeNftDescriptor(GENFT_PROXY).constructTokenURI(IGeNftDescriptor.ConstructTokenURIParams(
      tokenId, address(quoteToken), address(baseToken), baseToken.symbol(), quoteToken.symbol(), position.isCall, actualPnl
    ));

  }
  
  
  /// @notice Opens a fixed duration option
  function openFixedPosition(bool isCall, uint strike, uint notionalAmount, uint timeToExpiry) external returns (uint tokenId){
    require(timeToExpiry >= MIN_FIXED_OPTIONS_TTE, "GEP: Min Duration");
    require(timeToExpiry <= MAX_FIXED_OPTIONS_TTE, "GEP: Max Duration");
    require(StrikeManager.isValidStrike(strike), "GEP: Invalid Strike");
    uint basePrice = IGoodEntryVault(vault).getBasePrice();
    require((isCall && basePrice <= strike) || (!isCall && basePrice >= strike), "GEP: Not OTM");
    uint strikeDistance = isCall ? strike - basePrice : basePrice - strike;
    require(100 * strikeDistance / basePrice <= MAX_STRIKE_DISTANCE_X2, "GEP: Strike too far OTM");
    return openPosition(isCall, strike, notionalAmount, 0, timeToExpiry);
  }
  
  /// @notice Opens a streaming option which is a 6h expiry option paying a pay-as-you-go funding rate
  function openStreamingPosition(bool isCall, uint notionalAmount, uint collateralAmount) external returns (uint tokenId){
    require(collateralAmount >= MIN_COLLATERAL_AMOUNT, "GEP: Min Collateral Error");
    // Use 0 as strike for streaming option, it will take the closest one
    return openPosition(isCall, 0, notionalAmount, collateralAmount, 0);
  }
  
  /// @notice Open an option streaming position by borrowing an asset from the vault
  /// @param isCall Call or put
  /// @param collateralAmount if isStreamingOption, should give a collateral amount to deposit
  /// @param timeToExpiry if fixed duration (not isStreamingOption), end date will define option price and Collateral transferred from buyer
  function openPosition(bool isCall, uint strike, uint notionalAmount, uint collateralAmount, uint timeToExpiry) internal returns (uint tokenId) {
    uint basePrice = IGoodEntryVault(vault).getBasePrice();
    bool isStreamingOption = strike == 0;
    if(isStreamingOption) strike = isCall ? StrikeManager.getStrikeAbove(basePrice) : StrikeManager.getStrikeBelow(basePrice);

    uint positionValueX8 = notionalAmount * oracle.getAssetPrice(address(isCall ? baseToken : quoteToken)) 
                                          / 10**ERC20(isCall ? baseToken : quoteToken).decimals();
    require(positionValueX8 >= MIN_POSITION_VALUE_X8, "GEP: Min Size Error");
    uint optionCost = getOptionCost(isCall, strike, notionalAmount, isStreamingOption ? STREAMING_OPTION_TTE : timeToExpiry);

    // Funding rate in quoteToken per second X10
    uint fundingRateX10 = 1e10 * optionCost / STREAMING_OPTION_TTE;
    
    // Actual collateral amount
    collateralAmount = FIXED_EXERCISE_FEE + (isStreamingOption ? collateralAmount : optionCost);
    
    tokenId = _nextPositionId++;
    _positions[tokenId] = Position(
      isCall,
      isStreamingOption ? IGoodEntryPositionManager.OptionType.StreamingOption : IGoodEntryPositionManager.OptionType.FixedOption, 
      strike, 
      notionalAmount, 
      collateralAmount,
      block.timestamp, 
      isStreamingOption ? fundingRateX10 : block.timestamp + timeToExpiry
    );
    _mint(msg.sender, tokenId);

    // Borrow assets, those are sent here
    IGoodEntryVault(vault).borrow(address(isCall ? baseToken : quoteToken), notionalAmount);
    ERC20(quoteToken).safeTransferFrom(msg.sender, address(this), collateralAmount);

    // Start tracking if new strike
    if (openStrikeIds[strike] == 0) {
      openStrikes.push(strike);
      openStrikeIds[strike] = openStrikes.length - 1;
    }
    // Update OI
    if (isCall) {
      strikeToOpenInterestCalls[strike] += notionalAmount;
      openInterestCalls += notionalAmount;
    }
    else {
      strikeToOpenInterestPuts[strike] += notionalAmount;
      openInterestPuts += notionalAmount;
    }
    
    emit OpenedPosition(msg.sender, isCall, strike, notionalAmount, tokenId);
  }
  
  
  /// @notice Increase the collateral to maintain a position open for longer
  function increaseCollateral(uint tokenId, uint newCollateralAmount) public {
  require(_positions[tokenId].optionType == IGoodEntryPositionManager.OptionType.StreamingOption, "GEP: Not Streaming Option");
    ERC20(quoteToken).safeTransferFrom(msg.sender, address(this), newCollateralAmount);
    _positions[tokenId].collateralAmount += newCollateralAmount;
  }
  
  
  /// @notice Close a position and get some collateral back
  function closePosition(uint tokenId) external {
    address owner = ownerOf(tokenId);
    Position memory position = _positions[tokenId];
    address positionToken = address(position.isCall ? baseToken : quoteToken);
    uint remainingCollateral = position.collateralAmount;
    // Collateral spent over time as funding fees increase
    uint feesDue = getFeesAccumulated(tokenId);
    require(
      msg.sender == owner
        || (position.optionType == IGoodEntryPositionManager.OptionType.StreamingOption && feesDue >= position.collateralAmount - FIXED_EXERCISE_FEE)
        || (position.optionType == IGoodEntryPositionManager.OptionType.FixedOption && block.timestamp >= position.data )
        ||  _isEmergencyStrike(position.strike),
        "GEP: Invalid Close"
    );
    _burn(tokenId);
    // Invariant check for notional token: vaultDue + pnl = notionalAmount, which was received from the vault when the position was opened
    (uint vaultDue, uint posPnl) = getValueAtStrike(position.isCall, IGoodEntryVault(vault).getBasePrice(), position.strike, position.notionalAmount);
    
    if(position.isCall) checkSetApprove(address(baseToken), vault, vaultDue);
    checkSetApprove(address(quoteToken), vault, vaultDue + feesDue);
    // Referee discount is deduced from option price at open. Referrer  rebate is received from actual fees on close
    (address referrer, uint16 rebateReferrer,) = address(referrals) != address(0x0) ? referrals.getReferralParameters(owner) : (address(0x0), 0, 0);
    uint feesRebate;
    if(referrer != address(0x0) && rebateReferrer > 0) {
      feesRebate = feesDue * rebateReferrer / 10000;
      quoteToken.safeTransfer(referrer, feesRebate);
    }
    IGoodEntryVault(vault).repay(positionToken, vaultDue, feesDue - feesRebate);
    remainingCollateral -= feesDue;
    
    if (posPnl > 0) ERC20(positionToken).safeTransfer(owner, posPnl);
    
    // if exercise time reached, anyone can close the position and claim half of the fixed closing fee, other half goes to treasury
    if (owner != msg.sender) {
      quoteToken.safeTransfer(IGoodEntryCore(IVaultConfigurator(vault).goodEntryCore()).treasury(), FIXED_EXERCISE_FEE / 2);
      quoteToken.safeTransfer(msg.sender, FIXED_EXERCISE_FEE / 2);
      remainingCollateral -= FIXED_EXERCISE_FEE;
    }
    // Invariant: on closing position, no more than the colalteral deposited has been transfered out
    if (remainingCollateral > 0) quoteToken.safeTransfer(owner, remainingCollateral);
    // Invariant check collateral token: the amounts transfered as fees / remainder are deduced step by step from the collateral received
    // Any excess would cause a revert
    
    // update OI state
    if (position.isCall) {
      strikeToOpenInterestCalls[position.strike] -= position.notionalAmount;
      openInterestCalls -= position.notionalAmount;
    }
    else {
      strikeToOpenInterestPuts[position.strike] -= position.notionalAmount;
      openInterestPuts -= position.notionalAmount;
    }
    checkStrikeOi(position.strike);
    // pnl: position Pnl - fees, for event and tracking purposes (and pretty NFTs!)
    {
      int pnl = int(posPnl * oracle.getAssetPrice(positionToken) / 10**ERC20(positionToken).decimals())
              - int((position.collateralAmount - remainingCollateral) * oracle.getAssetPrice(address(quoteToken)) / 10**quoteToken.decimals());
      emit ClosedPosition(owner, msg.sender, tokenId, pnl);
    }
  }
  
  
  // @notice Remove a strike from OI list if OI of both puts and calls is 0
  function checkStrikeOi(uint strike) internal {
    if(strikeToOpenInterestCalls[strike] + strikeToOpenInterestPuts[strike] == 0){
      uint strikeId = openStrikeIds[strike];
      if(strikeId < openStrikes.length - 1){
        // if not last element, replace by last
        uint lastStrike = openStrikes[openStrikes.length - 1];
        openStrikes[strikeId] = lastStrike;
        openStrikeIds[lastStrike] = openStrikeIds[strike];
      }
      openStrikeIds[strike] = 0;
      openStrikes.pop();
    }
  }
  
  
  /// @notice Calculate fees accumulated by a position
  function getFeesAccumulated(uint tokenId) public view returns (uint feesAccumulated) {
    Position memory position = _positions[tokenId];
    uint collateralAmount = position.collateralAmount - FIXED_EXERCISE_FEE;
    if (position.optionType == IGoodEntryPositionManager.OptionType.StreamingOption){
      feesAccumulated = position.data * (block.timestamp - position.startDate) / 1e10;
      if (feesAccumulated > collateralAmount) feesAccumulated = collateralAmount;
    }
    else 
      feesAccumulated = collateralAmount;
  }


  /// @notice Calculate option debt due and user pnl
  function getValueAtStrike(bool isCall, uint price, uint strike, uint amount) public pure returns (uint vaultDue, uint pnl) {
    if(isCall  && price > strike) pnl = amount * (price - strike) / price;
    if(!isCall && price < strike) pnl = amount * (strike - price) / strike;
    vaultDue = amount - pnl;
    // By design, vaultDue + pnl = amount
  }
  
  
  /// @notice Get assets due to the vault: loop on open strikes to get value based on price and strikes
  function getAssetsDue() public view returns (uint baseAmount, uint quoteAmount) {
    if (openStrikes.length > 1){
      uint price = IGoodEntryVault(vault).getBasePrice();
      for(uint strike = 1; strike < openStrikes.length; strike++){
        (uint baseDue,) = getValueAtStrike(true, price, openStrikes[strike], strikeToOpenInterestCalls[openStrikes[strike]]);
        baseAmount += baseDue;
        (uint quoteDue,) = getValueAtStrike(false, price, openStrikes[strike], strikeToOpenInterestPuts[openStrikes[strike]]);
        quoteAmount += quoteDue;
      }
    }
  }
  
  
  /// @notice Get the option actual cost based on price, tokens, discounts, .
  function getOptionCost(bool isCall, uint strike, uint notionalAmount, uint timeToExpirySec) public view returns (uint optionCost){
    // Use internal function _getUtilizationRate to save on getReserves() which is very very expensive
    (uint baseBalance, uint quoteBalance) = IGoodEntryVault(vault).getAdjustedReserves();

    uint utilizationRate = _getUtilizationRate(baseBalance, quoteBalance, isCall, notionalAmount);
    require(utilizationRate <= MAX_UTILIZATION_RATE, "GEP: Max OI Reached");

    utilizationRate = _getUtilizationRate(baseBalance, quoteBalance, isCall, notionalAmount / 2);
    // unitary cost in quote tokens X8 (need to adjust for quote token decimals below)
    optionCost = oracle.getOptionPrice(isCall, address(baseToken), address(quoteToken), strike, timeToExpirySec, utilizationRate);

    // Referee discount is deduced from option price at open. Referrer  rebate is received from actual fees on close
    (,, uint16 discountReferee) = address(referrals) != address(0x0) ? referrals.getReferralParameters(msg.sender) : (address(0x0), 0, 0);
    if (discountReferee > 0) optionCost = optionCost * (10000 - discountReferee) / 10000;
    // total cost: multiply price by size in base token
    // for a put: eg: short ETH at strike 2000 with 4000 USDC -> size = 2
    if (isCall) optionCost = optionCost * notionalAmount * 10**quoteToken.decimals() / 10**baseToken.decimals() / 1e8;
    else optionCost = optionCost * notionalAmount / strike;
  }
  
    
  /// @notice Get the option price for a given strike, in quote tokens
  /// @dev Utilization rate with size/2 so that opening 1 large or 2 smaller positions have approx the same expected funding
  function getOptionPrice(bool isCall, uint strike, uint size, uint timeToExpirySec) public view returns (uint optionPrice) {
    optionPrice = oracle.getOptionPrice(isCall, address(baseToken), address(quoteToken), strike, timeToExpirySec, getUtilizationRate(isCall, size / 2));
  }
  
  
  /// @notice Get utilization rate at strike in percent
  /// @dev it could make sense to aggregate over a rolling window, eg oi(strikeAbove) + oi(strikeBelow) < 2 * maxOI
  function getUtilizationRate(bool isCall, uint addedAmount) public view returns (uint utilizationRate) {
    (uint baseBalance, uint quoteBalance) = IGoodEntryVault(vault).getAdjustedReserves();
    utilizationRate = _getUtilizationRate(baseBalance, quoteBalance, isCall, addedAmount);
  }
  
  
  /// @notice Calculate utilization rate based on token balances
  function _getUtilizationRate(uint baseBalance, uint quoteBalance, bool isCall, uint addedAmount) internal view returns (uint utilizationRate) {
    utilizationRate = 100;
    if (isCall && baseBalance > 0) utilizationRate = (openInterestCalls + addedAmount) * 100 / baseBalance;
    else if (!isCall && quoteBalance > 0) utilizationRate = (openInterestPuts + addedAmount) * 100 / quoteBalance;
  }
  
  
  /// @notice Get highest utilization of both sides
  function getUtilizationRateStatus() public view returns (uint utilizationRate, uint maxOI) {
    (uint baseBalance, uint quoteBalance, ) = IGoodEntryVault(vault).getReserves();
    uint utilizationRateCall = baseBalance > 0 ? openInterestCalls * 100 / baseBalance : 0;
    uint utilizationRatePut = quoteBalance > 0 ? openInterestPuts * 100 / quoteBalance : 0;
    utilizationRate = utilizationRateCall > utilizationRatePut ? utilizationRateCall : utilizationRatePut;
    maxOI = MAX_UTILIZATION_RATE;
  }
  
  
  ///@notice Is it an emergency? openStrikes getting too long? allow closing deepest OTM positions
  function _isEmergencyStrike(uint strike) internal view returns (bool isEmergency) {
    if (openStrikes.length < MAX_OPEN_STRIKES || openStrikes.length < 2) return false;
    // Skip 1st entry which is 0
    uint minStrike = openStrikes[1];
    uint maxStrike = minStrike;
    // loop on all strikes
    for (uint k = 1; k < openStrikes.length; k++){
      if (openStrikes[k] > maxStrike) maxStrike = openStrikes[k];
      if (openStrikes[k] < minStrike) minStrike = openStrikes[k];
    }
    isEmergency = strike == maxStrike || strike == minStrike;
  }
  
  
  /// @notice Helper that checks current allowance and approves if necessary
  /// @param token Target token
  /// @param spender Spender
  /// @param amount Amount below which we need to approve the token spending
  function checkSetApprove(address token, address spender, uint amount) internal {
    uint currentAllowance = ERC20(token).allowance(address(this), spender);
    if (currentAllowance < amount) ERC20(token).safeIncreaseAllowance(spender, UINT256MAX - currentAllowance);
  }
  
  /// @notice Get the name of this contract token
  function name() public view virtual override(ERC721, IERC721Metadata) returns (string memory) { 
    return string(abi.encodePacked("GoodEntry Positions ", baseToken.symbol(), "-", quoteToken.symbol()));
  }
  /// @notice Get the symbol of this contract token
  function symbol() public view virtual override(ERC721, IERC721Metadata) returns (string memory _symbol) {
    _symbol = "Good-Trade";
  }
}
