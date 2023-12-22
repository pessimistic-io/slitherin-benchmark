// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
pragma abicoder v2;

import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract Presale is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  struct UserInfo {
    uint256 allocation; // amount taken into account to obtain LIBRA (amount spent + discount)
    uint256 contribution; // amount spent to buy LIBRA

    uint256 discount; // discount % for this user
    uint256 discountEligibleAmount; // max contribution amount eligible for a discount

    address ref; // referral for this account
    uint256 refEarnings; // referral earnings made by this account
    uint256 claimedRefEarnings; // amount of claimed referral earnings
    bool hasClaimed; // has already claimed its allocation
  }

  IERC20 public immutable LIBRA; // LIBRA token contract
  IERC20 public immutable SALE_TOKEN; // token used to participate
  IERC20 public immutable LP_TOKEN; // LIBRA LP address

  uint256 public immutable START_TIME; // sale start time
  uint256 public immutable END_TIME; // sale end time

  uint256 public constant REFERRAL_SHARE = 3; // 3%

  mapping(address => UserInfo) public userInfo; // buyers and referrers info
  uint256 public totalRaised; // raised amount, does not take into account referral shares
  uint256 public totalAllocation; // takes into account discounts

  uint256 public constant MAX_LIBRA_TO_DISTRIBUTE = 60000000 ether; // max LIBRA amount to distribute during the sale

  // (=300,000 USDC, with USDC having 6 decimals ) amount to reach to distribute max LIBRA amount
  uint256 public constant MIN_TOTAL_RAISED_FOR_MAX_LIBRA = 300000000000;
  uint256 public constant MAX_TOTAL_RAISED_FOR_MAX_LIBRA = 6600000000000;

  address public immutable treasury; // treasury multisig, will receive raised amount

  bool public unsoldTokensBurnt;


  constructor(IERC20 libraToken, IERC20 saleToken, IERC20 lpToken, uint256 startTime, uint256 endTime, address treasury_) {
    require(startTime < endTime, "invalid dates");
    require(treasury_ != address(0), "invalid treasury");

    LIBRA = libraToken;
    SALE_TOKEN = saleToken;
    LP_TOKEN = lpToken;
    START_TIME = startTime;
    END_TIME = endTime;
    treasury = treasury_;
  }

  /********************************************/
  /****************** EVENTS ******************/
  /********************************************/

  event Buy(address indexed user, uint256 amount);
  event ClaimRefEarnings(address indexed user, uint256 amount);
  event Claim(address indexed user, uint256 libraAmount);
  event NewRefEarning(address referrer, uint256 amount);
  event DiscountUpdated();

  event EmergencyWithdraw(address token, uint256 amount);

  /***********************************************/
  /****************** MODIFIERS ******************/
  /***********************************************/

    /**
   * @dev Check whether the sale is currently active
   *
   * Will be marked as inactive if LIBRA has not been deposited into the contract
   */
  modifier isSaleActive() {
    require(hasStarted() && !hasEnded() && LIBRA.balanceOf(address(this)) >= MAX_LIBRA_TO_DISTRIBUTE, "isActive: sale is not active");
    _;
  }

  /**
   * @dev Check whether users can claim their purchased LIBRA
   *
   * Sale must have ended, and LP tokens must have been formed
   */
  modifier isClaimable(){
    require(hasEnded(), "isClaimable: sale has not ended");
    require(LP_TOKEN.totalSupply() > 0, "isClaimable: no LP tokens");
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
    return END_TIME-(_currentBlockTimestamp());
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
  * @dev Returns the amount of LIBRA to be distributed based on the current total raised
  */
  function libraToDistribute() public view returns (uint256){
    if (MIN_TOTAL_RAISED_FOR_MAX_LIBRA > totalRaised) {
      return MAX_LIBRA_TO_DISTRIBUTE*(totalRaised)/(MIN_TOTAL_RAISED_FOR_MAX_LIBRA);
    }
    return MAX_LIBRA_TO_DISTRIBUTE;
  }

  /**
  * @dev Get user share times 1e5
    */
  function getExpectedClaimAmounts(address account) public view returns (uint256 libraAmount) {
    if(totalAllocation == 0) return (0);

    UserInfo memory user = userInfo[account];
    uint256 totalLibraAmount = user.allocation*(libraToDistribute())/(totalAllocation);

    libraAmount = totalLibraAmount;
  }

  /****************************************************************/
  /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
  /****************************************************************/

  /**
   * @dev Purchase an allocation for the sale for a value of "amount" SALE_TOKEN, referred by "referralAddress"
   */
  function buy(uint256 amount, address referralAddress) external isSaleActive nonReentrant {
    require(amount > 0, "buy: zero amount");
    require(totalRaised+amount <= MAX_TOTAL_RAISED_FOR_MAX_LIBRA, "isBelowHardCap: exceeded hardcap");
    uint256 participationAmount = amount;
    UserInfo storage user = userInfo[msg.sender];

    // handle user's referral
    if (user.allocation == 0 && user.ref == address(0) && referralAddress != address(0) && referralAddress != msg.sender) {
      // If first buy, and does not have any ref already set
      user.ref = referralAddress;
    }
    referralAddress = user.ref;

    if (referralAddress != address(0)) {
      UserInfo storage referrer = userInfo[referralAddress];

      // compute and send referrer share
      uint256 refShareAmount = REFERRAL_SHARE*(amount)/(100);
      SALE_TOKEN.safeTransferFrom(msg.sender, address(this), refShareAmount);

      referrer.refEarnings = referrer.refEarnings+(refShareAmount);
      participationAmount = participationAmount-(refShareAmount);

      emit NewRefEarning(referralAddress, refShareAmount);
    }

    uint256 allocation = amount;
    if (user.discount > 0 && user.contribution < user.discountEligibleAmount) {

      // Get eligible amount for the active user's discount
      uint256 discountEligibleAmount = user.discountEligibleAmount-(user.contribution);
      if (discountEligibleAmount > amount) {
        discountEligibleAmount = amount;
      }
      // Readjust user new allocation
      allocation = allocation+(discountEligibleAmount*(user.discount)/(100));
    }

    // update raised amounts
    user.contribution = user.contribution+(amount);
    totalRaised = totalRaised+(amount);

    // update allocations
    user.allocation = user.allocation+(allocation);
    totalAllocation = totalAllocation+(allocation);

    emit Buy(msg.sender, amount);
    // transfer contribution to treasury
    SALE_TOKEN.safeTransferFrom(msg.sender, treasury, participationAmount);
  }

  /**
   * @dev Claim referral earnings
   */
  function claimRefEarnings() public {
    UserInfo storage user = userInfo[msg.sender];
    uint256 toClaim = user.refEarnings-(user.claimedRefEarnings);

    if(toClaim > 0){
      user.claimedRefEarnings = user.claimedRefEarnings+(toClaim);

      emit ClaimRefEarnings(msg.sender, toClaim);
      SALE_TOKEN.safeTransfer(msg.sender, toClaim);
    }
  }

  /**
   * @dev Claim purchased LIBRA during the sale
   */
  function claim() external isClaimable {
    UserInfo storage user = userInfo[msg.sender];

    require(totalAllocation > 0 && user.allocation > 0, "claim: zero allocation");
    require(!user.hasClaimed, "claim: already claimed");
    user.hasClaimed = true;

    (uint256 libraAmount) = getExpectedClaimAmounts(msg.sender);

    emit Claim(msg.sender, libraAmount);

    _safeClaimTransfer(msg.sender, libraAmount);
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

  /**
   * @dev Burn unsold LIBRA tokens if MIN_TOTAL_RAISED_FOR_MAX_LIBRA has not been reached
   *
   * Must only be called by the owner
   */
  function burnUnsoldTokens() external onlyOwner {
    require(hasEnded(), "burnUnsoldTokens: presale has not ended");
    require(!unsoldTokensBurnt, "burnUnsoldTokens: already burnt");

    uint256 totalSold = libraToDistribute();
    require(totalSold < MAX_LIBRA_TO_DISTRIBUTE, "burnUnsoldTokens: no token to burn");

    unsoldTokensBurnt = true;
    LIBRA.safeTransfer(0x000000000000000000000000000000000000dEaD, MAX_LIBRA_TO_DISTRIBUTE-(totalSold));
  }

  /********************************************************/
  /****************** INTERNAL FUNCTIONS ******************/
  /********************************************************/

  /**
   * @dev Safe token transfer function, in case rounding error causes contract to not have enough tokens
   */
  function _safeClaimTransfer(address to, uint256 amount) internal {
    uint256 libraBalance = LIBRA.balanceOf(address(this));
    bool transferSuccess = false;

    if (amount > libraBalance) {
      transferSuccess = LIBRA.transfer(to, libraBalance);
    } else {
      transferSuccess = LIBRA.transfer(to, amount);
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
