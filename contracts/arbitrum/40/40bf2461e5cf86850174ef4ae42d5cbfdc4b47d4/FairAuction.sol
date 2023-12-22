// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./IWETH.sol";


contract FairAuction is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using Address for address;

  struct UserInfo {
    uint256 allocation; // amount taken into account to obtain TOKEN (amount spent + discount)
    uint256 contribution; // amount spent to buy TOKEN

    bool whitelisted;
    uint256 whitelistCap;

    uint256 discount; // discount % for this user
    uint256 discountEligibleAmount; // max contribution amount eligible for a discount

    bool hasClaimed; // has already claimed its allocation
  }

  IERC20 public immutable PROJECT_TOKEN; // Project token contract
  IERC20 public immutable PROJECT_TOKEN_2; // Project token contract (eg. vested tokens)
  IERC20 public immutable SALE_TOKEN; // token used to participate
  IERC20 public immutable LP_TOKEN; // Project LP address

  uint256 public immutable START_TIME; // sale start time
  uint256 public immutable END_TIME; // sale end time

  mapping(address => UserInfo) public userInfo; // buyers info
  uint256 public totalRaised; // raised amount
  uint256 public totalAllocation; // takes into account discounts

  uint256 public immutable MAX_PROJECT_TOKENS_TO_DISTRIBUTE; // max PROJECT_TOKEN amount to distribute during the sale
  uint256 public immutable MAX_PROJECT_TOKENS_2_TO_DISTRIBUTE; // max PROJECT_TOKEN_2 amount to distribute during the sale
  uint256 public immutable MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN; // amount to reach to distribute max PROJECT_TOKEN amount

  uint256 public immutable MAX_RAISE_AMOUNT;
  uint256 public immutable CAP_PER_WALLET;

  address public immutable treasury; // treasury multisig, will receive raised amount

  bool public whitelistOnly;
  bool public unsoldTokensWithdrew;

  bool public forceClaimable; // safety measure to ensure that we can force claimable to true in case awaited LP token address plan change during the sale

  address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;


  constructor(
    IERC20 projectToken, IERC20 projectToken2, IERC20 saleToken, IERC20 lpToken,
    uint256 startTime, uint256 endTime, address treasury_,
    uint256 maxToDistribute, uint256 maxToDistribute2, uint256 minToRaise, uint256 maxToRaise, uint256 capPerWallet
  ) {
    require(startTime < endTime, "invalid dates");
    require(treasury_ != address(0), "invalid treasury");

    PROJECT_TOKEN = projectToken;
    PROJECT_TOKEN_2 = projectToken2;
    SALE_TOKEN = saleToken;
    LP_TOKEN = lpToken;
    START_TIME = startTime;
    END_TIME = endTime;
    treasury = treasury_;
    MAX_PROJECT_TOKENS_TO_DISTRIBUTE = maxToDistribute;
    MAX_PROJECT_TOKENS_2_TO_DISTRIBUTE = maxToDistribute2;
    MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN = minToRaise;
    if(maxToRaise == 0) {
      maxToRaise = type(uint256).max;
    }
    MAX_RAISE_AMOUNT = maxToRaise;
    if(capPerWallet == 0) {
      capPerWallet = type(uint256).max;
    }
    CAP_PER_WALLET = capPerWallet;
  }

  /********************************************/
  /****************** EVENTS ******************/
  /********************************************/

  event Buy(address indexed user, uint256 amount);
  event Claim(address indexed user, uint256 amount, uint256 amount2);
  event DiscountUpdated();
  event WhitelistUpdated();
  event EmergencyWithdraw(address token, uint256 amount);
  event SetWhitelistOnly(bool status);

  /***********************************************/
  /****************** MODIFIERS ******************/
  /***********************************************/

  /**
   * @dev Check whether the sale is currently active
   *
   * Will be marked as inactive if PROJECT_TOKEN has not been deposited into the contract
   */
  modifier isSaleActive() {
    require(hasStarted() && !hasEnded(), "isActive: sale is not active");
    require(PROJECT_TOKEN.balanceOf(address(this)) >= MAX_PROJECT_TOKENS_TO_DISTRIBUTE, "isActive: sale not filled");
    if(address(PROJECT_TOKEN_2) != address(0)) {
        require(PROJECT_TOKEN_2.balanceOf(address(this)) >= MAX_PROJECT_TOKENS_2_TO_DISTRIBUTE, "isActive: sale not filled 2");
    }
    _;
  }

  /**
   * @dev Check whether users can claim their purchased PROJECT_TOKEN
   *
   * Sale must have ended, and LP tokens must have been formed
   */
  modifier isClaimable(){
    require(hasEnded(), "isClaimable: sale has not ended");
    require(forceClaimable || LP_TOKEN.totalSupply() > 0, "isClaimable: no LP tokens");
    _;
  }

  /**************************************************/
  /****************** PUBLIC VIEWS ******************/
  /**************************************************/

  /**
  * @dev Get remaining duration before the end of the sale
  */
  function getRemainingTime() external view returns (uint256){
    if (hasEnded()) return 0;
    return END_TIME.sub(_currentBlockTimestamp());
  }

  /**
  * @dev Returns whether the sale has already started
  */
  function hasStarted() public view returns (bool) {
    return _currentBlockTimestamp() >= START_TIME;
  }

  /**
  * @dev Returns whether the sale has already ended
  */
  function hasEnded() public view returns (bool){
    return END_TIME <= _currentBlockTimestamp();
  }

  /**
  * @dev Returns the amount of PROJECT_TOKEN to be distributed based on the current total raised
  */
  function projectTokensToDistribute() public view returns (uint256){
    if (MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN > totalRaised) {
      return MAX_PROJECT_TOKENS_TO_DISTRIBUTE.mul(totalRaised).div(MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN);
    }
    return MAX_PROJECT_TOKENS_TO_DISTRIBUTE;
  }

  /**
  * @dev Returns the amount of PROJECT_TOKEN_2 to be distributed based on the current total raised
  */
  function projectTokens2ToDistribute() public view returns (uint256){
    if(address(PROJECT_TOKEN_2) == address(0)) {
      return 0;
    }
    if (MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN > totalRaised) {
      return MAX_PROJECT_TOKENS_2_TO_DISTRIBUTE.mul(totalRaised).div(MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN);
    }
    return MAX_PROJECT_TOKENS_2_TO_DISTRIBUTE;
  }

  /**
  * @dev Returns the amount of PROJECT_TOKEN + PROJECT_TOKEN_2 to be distributed based on the current total raised
  */
  function tokensToDistribute() public view returns (uint256){
    return projectTokensToDistribute().add(projectTokens2ToDistribute());
  }

  /**
  * @dev Get user tokens amount to claim
    */
  function getExpectedClaimAmount(address account) public view returns (uint256 projectTokenAmount, uint256 projectToken2Amount) {
    if(totalAllocation == 0) return (0, 0);

    UserInfo memory user = userInfo[account];
    projectTokenAmount = user.allocation.mul(projectTokensToDistribute()).div(totalAllocation);
    projectToken2Amount = user.allocation.mul(projectTokens2ToDistribute()).div(totalAllocation);
  }

  /****************************************************************/
  /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
  /****************************************************************/

  function buyETH() external isSaleActive nonReentrant payable {
    require(address(SALE_TOKEN) == weth, "non ETH sale");
    uint256 amount = msg.value;
    IWETH(weth).deposit{value: amount}();
    _buy(amount);
  }

/**
 * @dev Purchase an allocation for the sale for a value of "amount" SALE_TOKEN
   */
  function buy(uint256 amount) external isSaleActive nonReentrant {
    SALE_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    _buy(amount);
  }

  function _buy(uint256 amount) internal {
    require(amount > 0, "buy: zero amount");
    require(totalRaised.add(amount) <= MAX_RAISE_AMOUNT, "buy: hardcap reached");
    require(!address(msg.sender).isContract() && !address(tx.origin).isContract(), "FORBIDDEN");

    UserInfo storage user = userInfo[msg.sender];

    if(whitelistOnly) {
      require(user.whitelisted, "buy: not whitelisted");
      require(user.contribution.add(amount) <= user.whitelistCap, "buy: whitelist wallet cap reached");
    }
    else{
      uint256 userWalletCap = CAP_PER_WALLET > user.whitelistCap ? CAP_PER_WALLET : user.whitelistCap;
      require(user.contribution.add(amount) <= userWalletCap, "buy: wallet cap reached");
    }

    uint256 allocation = amount;

    if (user.discount > 0 && user.contribution < user.discountEligibleAmount) {

      // Get eligible amount for the active user's discount
      uint256 discountEligibleAmount = user.discountEligibleAmount.sub(user.contribution);
      if (discountEligibleAmount > amount) {
        discountEligibleAmount = amount;
      }
      // Readjust user new allocation
      allocation = allocation.add(discountEligibleAmount.mul(user.discount).div(100));
    }

    // update raised amounts
    user.contribution = user.contribution.add(amount);
    totalRaised = totalRaised.add(amount);

    // update allocations
    user.allocation = user.allocation.add(allocation);
    totalAllocation = totalAllocation.add(allocation);

    emit Buy(msg.sender, amount);
    // transfer contribution to treasury
    SALE_TOKEN.safeTransfer(treasury, amount);
  }

  /**
   * @dev Claim purchased PROJECT_TOKEN during the sale
   */
  function claim() external isClaimable {
    UserInfo storage user = userInfo[msg.sender];

    require(totalAllocation > 0 && user.allocation > 0, "claim: zero allocation");
    require(!user.hasClaimed, "claim: already claimed");
    user.hasClaimed = true;

    (uint256 token1Amount, uint256 token2Amount) = getExpectedClaimAmount(msg.sender);

    emit Claim(msg.sender, token1Amount, token2Amount);

    if(token1Amount > 0) {
      // send PROJECT_TOKEN allocation
      _safeClaimTransfer(PROJECT_TOKEN, msg.sender, token1Amount);
    }
    if(token2Amount > 0) {
      // send PROJECT_TOKEN allocation
      _safeClaimTransfer(PROJECT_TOKEN_2, msg.sender, token2Amount);
    }
  }

  /****************************************************************/
  /********************** OWNABLE FUNCTIONS  **********************/
  /****************************************************************/

  struct DiscountSettings {
    address account;
    uint256 discount;
    uint256 eligibleAmount;
  }

  /**
   * @dev Assign custom discounts, used for v1 users
   *
   * Based on saved v1 tokens amounts in our snapshot
   */
  function setUsersDiscount(DiscountSettings[] calldata users) public onlyOwner {
    for (uint256 i = 0; i < users.length; ++i) {
      DiscountSettings memory userDiscount = users[i];
      UserInfo storage user = userInfo[userDiscount.account];
      require(userDiscount.discount <= 35, "discount too high");
      user.discount = userDiscount.discount;
      user.discountEligibleAmount = userDiscount.eligibleAmount;
    }

    emit DiscountUpdated();
  }

  struct WhitelistSettings {
    address account;
    bool whitelisted;
    uint256 whitelistCap;
  }

  /**
   * @dev Assign whitelist status and cap for users
   */
  function setUsersWhitelist(WhitelistSettings[] calldata users) public onlyOwner {
    for (uint256 i = 0; i < users.length; ++i) {
      WhitelistSettings memory userWhitelist = users[i];
      UserInfo storage user = userInfo[userWhitelist.account];
      user.whitelisted = userWhitelist.whitelisted;
      user.whitelistCap = userWhitelist.whitelistCap;
    }

    emit WhitelistUpdated();
  }

  function setWhitelistOnly(bool value) external onlyOwner {
    whitelistOnly = value;
    emit SetWhitelistOnly(value);
  }

  /**
   * @dev Withdraw unsold PROJECT_TOKEN + PROJECT_TOKEN_2 if MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN has not been reached
   *
   * Must only be called by the owner
   */
  function withdrawUnsoldTokens() external onlyOwner {
    require(hasEnded(), "withdrawUnsoldTokens: presale has not ended");
    require(!unsoldTokensWithdrew, "withdrawUnsoldTokens: already burnt");

    uint256 totalTokenSold = projectTokensToDistribute();
    uint256 totalToken2Sold = projectTokens2ToDistribute();

    unsoldTokensWithdrew = true;
    if(totalTokenSold > 0) PROJECT_TOKEN.transfer(msg.sender, MAX_PROJECT_TOKENS_TO_DISTRIBUTE.sub(totalTokenSold));
    if(totalToken2Sold > 0) PROJECT_TOKEN_2.transfer(msg.sender, MAX_PROJECT_TOKENS_2_TO_DISTRIBUTE.sub(totalToken2Sold));
  }


  /********************************************************/
  /****************** /!\ EMERGENCY ONLY ******************/
  /********************************************************/

  /**
   * @dev Failsafe
   */
  function emergencyWithdrawFunds(address token, uint256 amount) external onlyOwner {
    IERC20(token).safeTransfer(msg.sender, amount);

    emit EmergencyWithdraw(token, amount);
  }

  function setForceClaimable() external onlyOwner {
    forceClaimable = true;
  }

  /********************************************************/
  /****************** INTERNAL FUNCTIONS ******************/
  /********************************************************/

  /**
   * @dev Safe token transfer function, in case rounding error causes contract to not have enough tokens
   */
  function _safeClaimTransfer(IERC20 token, address to, uint256 amount) internal {
    uint256 balance = token.balanceOf(address(this));
    bool transferSuccess = false;

    if (amount > balance) {
      transferSuccess = token.transfer(to, balance);
    } else {
      transferSuccess = token.transfer(to, amount);
    }

    require(transferSuccess, "safeClaimTransfer: Transfer failed");
  }

  /**
   * @dev Utility function to get the current block timestamp
   */
  function _currentBlockTimestamp() internal view virtual returns (uint256) {
    return block.timestamp;
  }
}

