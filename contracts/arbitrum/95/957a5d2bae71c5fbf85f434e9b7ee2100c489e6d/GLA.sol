// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./Context.sol";
import "./IMarket.sol";
import "./Math.sol";

contract GenesisLaunchAuction is Context, Ownable {
  using SafeERC20 for IERC20;

  // public offering phase start time
  // uint256 public publicOfferingEnabledAt; bool for testnet after
  uint public publicOfferingEnabledAt;
  // init phase start time
  // uint256 public initAt;
  uint public initAt;
  // unlock phase start time
  // uint256 public unlockAt;
  uint public unlockAt;
  // a flag to mark if it has been initialized
  bool public initialized = false;

  // public offering price(1e6)
  uint256 public publicOfferingPrice;
  // soft USD cap,
  // if the final USD cap does not reach softCap, the market will not start
  uint256 public softCap;
  // hard USD cap,
  // the final USD cap will not exceed hardCap
  uint256 public hardCap;

  // Lab token address
  IERC20 public Lab;
  // USDC token address
  IERC20 public USDC;
  // Market contract address
  IMarket public market;

  // the total number of public offering users raised
  uint256 public publicOfferingTotalShares;
  // shares of each public offering user
  mapping(address => uint256) public publicOfferingSharesOf;

  modifier beforePublic() {
    require(
     block.timestamp < publicOfferingEnabledAt,
      "GLA: before Public"
    );
    _;
  }

  modifier publicOfferingEnabled() {
    require(

        block.timestamp >= publicOfferingEnabledAt &&
        block.timestamp < initAt,

      "GLA: public offering not enabled"
    );
    _;
  }

  modifier initializeEnabled() {
    require(
     block.timestamp >= initAt && block.timestamp < unlockAt,
      "GLA: initialize not enabled"
    );
    _;
  }

  modifier isInitialized() {
    require(initialized, "GLA: is not initialized");
    _;
  }

  modifier isUnlocked() {
    require(
     block.timestamp >= unlockAt,
      "GLA: is not unlocked"
    );
    _;
  }

  constructor(
    IERC20 _Lab,
    IERC20 _USDC,
    IMarket _market,
    uint256 _publicOfferingEnabledAt,
    uint256 _publicOfferingInterval,
    uint256 _initInterval,
    uint256 _publicOfferingPrice,
    uint256 _softCap,
    uint256 _hardCap
  ) {
    require(
      IERC20Metadata(address(_USDC)).decimals() == 6 &&
      IERC20Metadata(address(_Lab)).decimals() == 18 &&
      _publicOfferingEnabledAt > 0 &&
        _publicOfferingInterval > 0 &&
        _initInterval > 0 &&
      _publicOfferingPrice > 0 && _softCap > 0 && _hardCap > _softCap,
      "GLA: invalid constructor args"
    );
    Lab = _Lab;
    USDC = _USDC;
    market = _market;
    publicOfferingEnabledAt = _publicOfferingEnabledAt;
    initAt = publicOfferingEnabledAt + _publicOfferingInterval; // Tochange
    unlockAt = initAt + _initInterval;
    publicOfferingPrice = _publicOfferingPrice;
    softCap = _softCap;
    hardCap = _hardCap;
  }

  /**
   * @dev Get public offering total supply.
   */
  function totalSupply() public view returns (uint256) {
    return (publicOfferingTotalShares * 1e6) / publicOfferingPrice;
  }

  /**
   * @dev Get total USD cap.
   */
  function totalCap() public view returns (uint256) {
    return publicOfferingTotalShares;
  }

  /**
   * @dev Get public offering price(1e18).
   */
  function getPublicOfferingPrice() external view returns (uint256) {
    return publicOfferingPrice * 1e12;
  }

  /**
   * @dev Get total supply(1e18).
   */
  function getTotalSupply() public view returns (uint256) {
    return totalSupply() * 1e12;
  }

  /**
   * @dev Get the current phase enumeration.
   */
  function getPhase() external view returns (uint8) {
    if (initialized) {
      // initialized
      return 3;
    } else {
      if (
        block.timestamp < publicOfferingEnabledAt

      ) {
        //not Started
        return 0;
      } else if (
       block.timestamp >= publicOfferingEnabledAt && block.timestamp < initAt
      ) {
        // public offering phase
        return 1;
      } else if (
        block.timestamp >= initAt && block.timestamp < unlockAt) {

        return 2;
      } else {
        // unlock phase
        return 4;
      }
    }
  }

  /**
   * @dev Public offering user buy Lab.
   * @param amount_ - The amount of USDC.
   */
  function publicOfferingBuy(uint256 amount_) external publicOfferingEnabled {
    uint256 amount = amount_;
    uint256 maxCap = hardCap - totalCap();
    if (amount > maxCap) {
      amount = maxCap;
    }
    require(amount > 0, "GLA: zero amount");
    USDC.safeTransferFrom(_msgSender(), address(this), amount);
    publicOfferingTotalShares += amount;
    publicOfferingSharesOf[_msgSender()] += amount;

    // reach the hard cap, directly start market
    if (totalCap() >= hardCap) {
      _startup();
    }
  }

  /**
   * @dev Initialize GLA.
   *      If totalSupply reaches softCap, it will start the market,
   *      otherwise it will the enter unlock phase.
   */
  function initialize()
    external
    initializeEnabled /*onlyOwner*/
  {
    if (totalCap() >= softCap) {
      _startup();
    } else {
      unlockAt = initAt + 1;
    }
  }

  /**
   * @dev Start the market.
   */
  function _startup() internal {
    uint256 _totalSupply = getTotalSupply();
    uint256 _totalCap = totalCap();
    USDC.approve(address(market), _totalCap);
    uint256 _USDCBalance1 = USDC.balanceOf(address(this));
    uint256 _LabBalance1 = Lab.balanceOf(address(this));
    market.startup(address(USDC), _totalCap, _totalSupply);
    uint256 _USDCBalance2 = USDC.balanceOf(address(this));
    uint256 _LabBalance2 = Lab.balanceOf(address(this));
    require(
      _USDCBalance1 - _USDCBalance2 == _totalCap &&
        _LabBalance2 - _LabBalance1 == _totalSupply,
      "GLA: startup failed"
    );
    initialized = true;
  }

  /**
   * @dev Estimate how much Lab user can claim.
   */
  function estimateClaim(address user) public view returns (uint256 lab) {
    lab += (publicOfferingSharesOf[user] * 1e6) / publicOfferingPrice;
    lab *= 1e12;
  }

  /**
   * @dev Claim lab.
   */
  function claim() external isInitialized {
    uint256 lab = estimateClaim(_msgSender());
    require(lab > 0, "GLA: zero lab");
    uint256 max = Lab.balanceOf(address(this));
    Lab.transfer(_msgSender(), max < lab ? max : lab);
    delete publicOfferingSharesOf[_msgSender()];
  }

  /**
   * @dev Estimate how much USDC user can withdraw.
   */
  function estimateWithdraw(address user) public view returns (uint256 shares) {
    shares += publicOfferingSharesOf[user];
  }

  /**
   * @dev Withdraw USDC.
   */
  function withdraw() external isUnlocked {
    uint256 shares = estimateWithdraw(_msgSender());
    delete publicOfferingSharesOf[_msgSender()];
    require(shares > 0, "GLA: zero shares");
    USDC.safeTransfer(_msgSender(), shares);
  }
}

