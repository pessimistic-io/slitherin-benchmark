// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "./Ownable.sol";
import "./Context.sol";

import "./Pausable.sol";
import "./IERC20BurnableMinter.sol";

import "./IMarket.sol";
import "./IBank.sol";
import "./IStakePool.sol";

contract Bank is Context, Ownable, Pausable {
  bool marketAndHelperSet = false;
  // DSD token address
  IERC20BurnableMinter public immutable DSD;
  // DSD token address
  IERC20BurnableMinter public immutable USDC;
  // Market contract address
  IMarket public market;
  // StakePool contract address
  IStakePool public pool;
  // helper contract address
  address public helper;

  // user debt
  mapping(address => uint256) public debt;

  // developer address
  address public dev;
  // fee for borrowing DSD
  uint32 public borrowFee;

  event OptionsChanged(address dev, uint32 borrowFee);

  event Borrow(address user, uint256 amount, uint256 fee);

  event Repay(address user, uint256 amount);
  event RepayWithUsdc(address user, uint256 amount);

  modifier onlyHelper() {
    require(_msgSender() == helper, "Bank: only helper");
    _;
  }

  /**
   * @dev Constructor.
   * NOTE This function can only called through delegatecall.
   * @param _DSD - DSD token address.
   * @param _pool - StakePool contract address.
   */
  constructor(
    IERC20BurnableMinter _DSD,
    IERC20BurnableMinter _USDC,
    IStakePool _pool
  ) {
    DSD = _DSD;
    USDC = _USDC;
    pool = _pool;
  }

  function setMarketAndHelper(IMarket _market, address _helper)
    external
    onlyOwner
  {
    require(!marketAndHelperSet);
    market = _market;
    helper = _helper;
    marketAndHelperSet = true;
  }

  /**
   * @dev Set bank options.
   *      The caller must be owner.
   * @param _dev - Developer address
   * @param _borrowFee - Fee for borrowing DSD
   */
  function setOptions(address _dev, uint32 _borrowFee) public onlyOwner {
    require(_dev != address(0), "Bank: zero dev address");
    require(_borrowFee <= 10000, "Bank: invalid borrowFee");
    dev = _dev;
    borrowFee = _borrowFee;
    emit OptionsChanged(_dev, _borrowFee);
  }

  /**
   * @dev Calculate the amount of Lab that can be withdrawn.
   * @param user - User address
   */
  function withdrawable(address user) external view returns (uint256) {
    uint256 userDebt = debt[user];
    (uint256 amountLab, ) = pool.userInfo(0, user);
    uint256 floorPrice = market.f();
    if (amountLab * floorPrice <= userDebt * 1e18) {
      return 0;
    }
    return (amountLab * floorPrice - userDebt * 1e18) / floorPrice;
  }

  /**
   * @dev Calculate the amount of Lab that can be withdrawn.
   * @param user - User address
   * @param amountLab - User staked Lab amount
   */
  function withdrawable(address user, uint256 amountLab)
    external
    view
    returns (uint256)
  {
    uint256 userDebt = debt[user];
    uint256 floorPrice = market.f();
    if (amountLab * floorPrice <= userDebt * 1e18) {
      return 0;
    }
    return (amountLab * floorPrice - userDebt * 1e18) / floorPrice;
  }

  /**
   * @dev Calculate the amount of DSD that can be borrowed.
   * @param user - User address
   */
  function available(address user) public view returns (uint256) {
    uint256 userDebt = debt[user];
    (uint256 amountLab, ) = pool.userInfo(0, user);
    uint256 floorPrice = market.f();
    if (amountLab * floorPrice <= userDebt * 1e18) {
      return 0;
    }
    return (amountLab * floorPrice - userDebt * 1e18) / 1e18;
  }

  /**
   * @dev Borrow DSD.
   * @param amount - The amount of DSD
   * @return borrowed - Borrowed DSD
   * @return fee - Borrow fee
   */
  function borrow(uint256 amount)
    external
    whenNotPaused
    returns (uint256 borrowed, uint256 fee)
  {
    return _borrowFrom(_msgSender(), amount);
  }

  /**
   * @dev Borrow DSD from user and directly mint to msg.sender.
   *      The caller must be helper contract.
   * @param user - User address
   * @param amount - The amount of DSD
   * @return borrowed - Borrowed DSD
   * @return fee - Borrow fee
   */
  function borrowFrom(address user, uint256 amount)
    external
    onlyHelper
    whenNotPaused
    returns (uint256 borrowed, uint256 fee)
  {
    return _borrowFrom(user, amount);
  }

  /**
   * @dev Borrow DSD from user and directly mint to msg.sender.
   */
  function _borrowFrom(address user, uint256 amount)
    internal
    returns (uint256 borrowed, uint256 fee)
  {
    require(amount > 0, "Bank: amount is zero");
    uint256 userDebt = debt[user];
    (uint256 amountLab, ) = pool.userInfo(0, user);
    require(
      userDebt + amount <= (amountLab * market.f()) / 1e18,
      "Bank: exceeds available"
    );
    fee = (amount * borrowFee) / 10000;
    borrowed = amount - fee;
    DSD.mint(_msgSender(), borrowed);
    DSD.mint(dev, fee);
    debt[user] = userDebt + amount;
    emit Borrow(user, borrowed, fee);
  }

  /**
   * @dev Repay DSD.
   * @param amount - The amount of DSD
   */
  function repay(uint256 amount) external whenNotPaused {
    require(amount > 0, "Bank: amount is zero");
    uint256 userDebt = debt[_msgSender()];
    require(userDebt >= amount, "Bank: exceeds debt");
    DSD.burnFrom(_msgSender(), amount);
    unchecked {
      debt[_msgSender()] = userDebt - amount;
    }
    emit Repay(_msgSender(), amount);
  }

  /**
   * @dev Repay USDC.
   * @param amount - The amount of USDC
   */
  function repayWithUsdc(uint256 amount) external whenNotPaused {
    require(amount > 0, "Bank: amount is zero");
    uint256 worth1e18 = amount * 1e12;
    require(
      worth1e18 <= debt[msg.sender] - DSD.balanceOf(msg.sender),
      "Can't repay with Usdc "
    );
    uint256 userDebt = debt[_msgSender()];
    require(userDebt >= worth1e18, "Bank: exceeds debt");
    USDC.transferFrom(_msgSender(), address(market), amount);
    DSD.burnFrom(address(market), worth1e18);
    unchecked {
      debt[_msgSender()] = userDebt - worth1e18;
    }
    emit RepayWithUsdc(_msgSender(), amount);
  }

  /**
   * @dev Triggers stopped state.
   *      The caller must be owner.
   */
  function pause() external onlyOwner {
    _pause();
  }

  /**
   * @dev Returns to normal state.
   *      The caller must be owner.
   */
  function unpause() external onlyOwner {
    _unpause();
  }
}

