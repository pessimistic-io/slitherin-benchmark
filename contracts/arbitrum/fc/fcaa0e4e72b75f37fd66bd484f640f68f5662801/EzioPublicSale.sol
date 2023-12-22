// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./EZIO.sol";
import "./xEZIO.sol";
//import "hardhat/console.sol";

contract EzioPublicSale is ReentrancyGuard,Ownable,Pausable {
  using SafeERC20 for IERC20;
  using SafeERC20Upgradeable for EZIOV1;
  using SafeERC20Upgradeable for xEZIOV1;
  struct Contribution {
    uint256 amount;
    bool hasWithdrawn;
  }
  //Error message constant
  string internal constant SALE_NOT_OPEN = "EzioPublicSale: not open";
  string internal constant SALE_NOT_CLOSE = "EzioPublicSale: not close";
  string internal constant WRONG_AMOUNT = "EzioPublicSale: Wrong Amount";
  uint256 public constant RAISE_USDC_THRESHOLD = 1e6 * 1e6;
  uint256 public constant RAISE_USDC_CAP = 2 * 1e6 * 1e6;
  uint256 public constant PUBLIC_SALE_AMOUNT = 1e8 * 1e18;
  uint8 public constant EZIO_RATE = 65;
  uint8 public constant XEZIO_RATE = 35;

  IERC20 private usdc;
  EZIOV1 private ezio;
  xEZIOV1 private xezio;
  //administrator's wallet address
  address public wallet;
  //total raised USDC
  uint256 totalRaisedAmount;
  //contribution of address
  mapping(address => Contribution) private contributions;

  uint256 public openingTime;
  uint256 public closingTime;
  bool public executeFlag;
  //buy event
  event Buy(address indexed account_, uint256 indexed amount_);
  //withdraw event
  event Withdraw(address indexed account_, uint256 indexed amount_);

  modifier onlyWhileOpen {
    require(isOpen(), SALE_NOT_OPEN);
    _;
  }
  modifier onlyWhileClose {
    require(hasClosed(), SALE_NOT_CLOSE);
    _;
  }

  constructor(IERC20 usdc_, EZIOV1 ezio_, xEZIOV1 xezio_,address wallet_, uint256 openingTime_, uint256 closingTime_) {
    require(address(usdc_) != address(0), "EzioPublicSale: USDC is the zero address");
    require(address(ezio_) != address(0), "EzioPublicSale: EZIO is the zero address");
    require(address(xezio_) != address(0), "EzioPublicSale: xEZIO is the zero address");
    require(openingTime_ >= block.timestamp, "EzioPublicSale: opening time is before current time");
    require(closingTime_ > openingTime_, "EzioPublicSale: opening time is not before closing time");
    usdc = usdc_;
    ezio = ezio_;
    xezio = xezio_;
    wallet = wallet_;
    openingTime = openingTime_;
    closingTime = closingTime_;
  }

  /**
  * @notice              buy EZIO and xEZIO during public sale
  * @param usdcAmount    USDC amount for buy EZIO and xEZIO
  */
  function buy(uint256 usdcAmount) external nonReentrant onlyWhileOpen whenNotPaused{
    require(usdcAmount != 0, "EzioPublicSale: usdcAmount is 0");
    usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
    contributions[msg.sender].amount += usdcAmount;
    totalRaisedAmount += usdcAmount;
    require(usdc.balanceOf(address(this))>=totalRaisedAmount,WRONG_AMOUNT);
    emit Buy(msg.sender, usdcAmount);
  }

  /**
  * @notice           contribution of account
  * @param account    address of contributor
  * @return uint256
  */
  function balanceOf(address account) external view returns (uint256) {
    return contributions[account].amount;
  }

  /**
  * @notice    withdraw EZIO and xEZIO after public sale
  */
  function withdraw() external nonReentrant onlyWhileClose whenNotPaused {
    require(!contributions[msg.sender].hasWithdrawn,"EzioPublicSale: has withdrawn");
    uint256 ezioAmount;
    uint256 xezioAmount;
    if(totalRaisedAmount<=RAISE_USDC_THRESHOLD){
      ezioAmount = contributions[msg.sender].amount * PUBLIC_SALE_AMOUNT * EZIO_RATE / (RAISE_USDC_THRESHOLD * 100);
      xezioAmount = contributions[msg.sender].amount * PUBLIC_SALE_AMOUNT * XEZIO_RATE / (RAISE_USDC_THRESHOLD * 100);
    }else if(totalRaisedAmount>RAISE_USDC_THRESHOLD && totalRaisedAmount<= RAISE_USDC_CAP){
      ezioAmount = contributions[msg.sender].amount * PUBLIC_SALE_AMOUNT * EZIO_RATE / (totalRaisedAmount * 100);
      xezioAmount = contributions[msg.sender].amount * PUBLIC_SALE_AMOUNT * XEZIO_RATE / (totalRaisedAmount * 100);
    }else if(totalRaisedAmount>RAISE_USDC_CAP){
      ezioAmount = contributions[msg.sender].amount * PUBLIC_SALE_AMOUNT * EZIO_RATE / (totalRaisedAmount * 100);
      xezioAmount = contributions[msg.sender].amount * PUBLIC_SALE_AMOUNT * XEZIO_RATE / (totalRaisedAmount * 100);
      uint256 returnUSDCAmount = contributions[msg.sender].amount - contributions[msg.sender].amount * RAISE_USDC_CAP / totalRaisedAmount;
      //console.log("returnUSDCAmount=",returnUSDCAmount);
      if(usdc.balanceOf(address(this))==returnUSDCAmount-1){
        usdc.safeTransfer(msg.sender,returnUSDCAmount-1);
      }else{
        usdc.safeTransfer(msg.sender,returnUSDCAmount);
      }
    }
    contributions[msg.sender].hasWithdrawn = true;
    emit Withdraw(msg.sender, ezioAmount);
    ezio.safeTransfer(msg.sender,ezioAmount);
    xezio.safeTransfer(msg.sender,xezioAmount);
  }

  /**
  * @notice    the action of administrator after public sale
  */
  function afterPublicSaleExecute() external onlyOwner onlyWhileClose {
    require(!executeFlag,"EzioPublicSale: Executed already");
    executeFlag = true;
    uint256 finalAmount;
    if(totalRaisedAmount<=RAISE_USDC_THRESHOLD){
      //Destroy unsold tokens
      uint256 ezioBurnAmount = (RAISE_USDC_THRESHOLD - totalRaisedAmount) * PUBLIC_SALE_AMOUNT * EZIO_RATE / (RAISE_USDC_THRESHOLD * 100);
      uint256 xezioBurnAmount = (RAISE_USDC_THRESHOLD - totalRaisedAmount) * PUBLIC_SALE_AMOUNT * XEZIO_RATE / (RAISE_USDC_THRESHOLD * 100);
      if(ezio.balanceOf(address(this))==ezioBurnAmount-1){
        ezio.burn(ezioBurnAmount-1);
      }else{
        ezio.burn(ezioBurnAmount);
      }
      if(xezio.balanceOf(address(this))==xezioBurnAmount-1){
        xezio.burn(xezioBurnAmount-1);
      }else{
        xezio.burn(xezioBurnAmount);
      }
      finalAmount = totalRaisedAmount;
    }else if(totalRaisedAmount>RAISE_USDC_THRESHOLD && totalRaisedAmount<= RAISE_USDC_CAP){
      finalAmount = totalRaisedAmount;
    }else if(totalRaisedAmount>RAISE_USDC_CAP){
      finalAmount = RAISE_USDC_CAP;
    }
    usdc.safeTransfer(wallet,finalAmount);
  }

  /**
  * @return true if the public sale is open, false otherwise.
  */
  function isOpen() public view returns (bool) {
    return block.timestamp >= openingTime && block.timestamp <= closingTime;
  }

  /**
  * @dev Checks whether the period in which the public sale is open has already elapsed.
  * @return Whether public sale period has elapsed
  */
  function hasClosed() public view returns (bool) {
    return block.timestamp > closingTime;
  }

  /**
  * @notice     Pause the contract
  */
  function pause() external onlyOwner nonReentrant{
    _pause();
  }

  /**
  * @notice     Unpause the contract
  */
  function unpause() external onlyOwner nonReentrant{
    _unpause();
  }

}

