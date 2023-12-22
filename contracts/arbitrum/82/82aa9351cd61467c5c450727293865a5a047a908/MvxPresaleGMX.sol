// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./IERC20.sol";

// @author 0xR
// @contact 0xr@metavault.org

contract MvxPresaleGMX is Ownable, ReentrancyGuard {
  using SafeMath for uint256;

  bool public isInitialized;
  bool public isPresaleActive = true;
  bool public isLiquidityAdded = false;

  address public usdc;
  address public wallet;

  uint256 public mvxPresalePrice;
  uint256 public mvxListingPrice;

  uint256 public usdcSlotCap;
  uint256 public usdcHardCap;

  uint256 public usdcBasisPoints;
  uint256 public unlockTime;

  uint256 public usdcReceived;

  address public gov;

  mapping(address => uint256) public presaleAmounts;
  mapping(address => uint256) public slotAmounts;
  mapping(address => uint256) public mvxAmounts;
  mapping(address => bool) public presaleWhitelist;

  modifier onlyGov() {
    require(msg.sender == gov, "Presale: forbidden");
    _;
  }

  constructor() {
    gov = msg.sender;
  }

  function initialize(address[] memory _addresses, uint256[] memory _values) external onlyGov {
    require(!isInitialized, "Presale: already initialized");
    isInitialized = true;

    usdc = _addresses[0];
    wallet = _addresses[1];

    mvxPresalePrice = _values[0];
    mvxListingPrice = _values[1];
    usdcSlotCap = _values[2];
    usdcHardCap = _values[3];
    unlockTime = _values[4];
  }

  function setGov(address _gov) external onlyGov nonReentrant {
    gov = _gov;
  }

  function setWallet(address _wallet) external onlyGov nonReentrant {
    wallet = _wallet;
  }

  function extendUnlockTime(uint256 _unlockTime) external onlyGov nonReentrant {
    require(_unlockTime > unlockTime, "Presale: invalid _unlockTime");
    unlockTime = _unlockTime;
  }

  function addWhitelists(address[] memory _accounts) external onlyGov nonReentrant {
    for (uint256 i = 0; i < _accounts.length; i++) {
      address account = _accounts[i];
      presaleWhitelist[account] = true;
    }
  }

  function removeWhitelists(address[] memory _accounts) external onlyGov nonReentrant {
    for (uint256 i = 0; i < _accounts.length; i++) {
      address account = _accounts[i];
      presaleWhitelist[account] = false;
    }
  }

  function addSlotList(address[] memory _accounts, uint256[] memory _slots) external onlyGov nonReentrant {
    for (uint256 i = 0; i < _accounts.length; i++) {
      address account = _accounts[i];
      slotAmounts[account] = _slots[i];
    }
  }

  function removeSlotList(address[] memory _accounts, uint256[] memory _slots) external onlyGov nonReentrant {
    for (uint256 i = 0; i < _accounts.length; i++) {
      address account = _accounts[i];
      slotAmounts[account] = _slots[i];
    }
  }

  function updateWhitelist(address prevAccount, address nextAccount) external onlyGov nonReentrant {
    require(presaleWhitelist[prevAccount], "Presale: invalid prevAccount");
    presaleWhitelist[prevAccount] = false;
    presaleWhitelist[nextAccount] = true;
  }

  function presale(uint256 _usdcAmount) external nonReentrant {
    address account = msg.sender;
    require(presaleWhitelist[account], "Presale: forbidden");
    require(isPresaleActive, "Presale: presale is no longer active");
    require(_usdcAmount > 0, "Presale: invalid _usdcAmount");

    usdcReceived = usdcReceived.add(_usdcAmount);
    require(usdcReceived <= usdcHardCap, "Presale: usdcHardCap exceeded");

    presaleAmounts[account] = presaleAmounts[account].add(_usdcAmount);
    uint256 slotCap = slotAmounts[account].mul(usdcSlotCap);

    require(presaleAmounts[account] <= slotCap, "Presale: usdcSlotCap exceeded");

    // receive USDC
    uint256 usdcBefore = IERC20(usdc).balanceOf(address(this));
    IERC20(usdc).transferFrom(account, address(this), _usdcAmount);
    uint256 usdcAfter = IERC20(usdc).balanceOf(address(this));
    require(usdcAfter.sub(usdcBefore) == _usdcAmount, "Presale: invalid transfer");

    // save MVX amount for airdrop
    uint256 mvxAmount = _usdcAmount.mul(10**18).div(mvxPresalePrice);

    mvxAmounts[account] = mvxAmounts[account].add(mvxAmount);
  }

  function transferLiquidity() external onlyGov nonReentrant {
    require(block.timestamp > unlockTime, "Presale: unlockTime not yet passed");

    uint256 fundAmount = usdcReceived;
    IERC20(usdc).transfer(wallet, fundAmount);
  }

  function withdrawToken(
    address _token,
    address _account,
    uint256 _amount
  ) external onlyGov nonReentrant {
    require(block.timestamp > unlockTime, "Presale: unlockTime not yet passed");
    IERC20(_token).transfer(_account, _amount);
  }

  function endPresale() external onlyGov nonReentrant {
    isPresaleActive = false;
  }
}

