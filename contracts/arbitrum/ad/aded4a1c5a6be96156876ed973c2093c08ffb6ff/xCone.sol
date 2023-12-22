// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

// website: https://concentric.fi
// twitter: https://twitter.com/ConcentricFi
// discord: https://discord.gg/ConcentricFi

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface token is IERC20 {
  function mint(address recipient, uint256 _amount) external;

  function burn(address _from, uint256 _amount) external;
}

interface staking {
  function allocateVestRP(
    uint256 _pid,
    uint256 _amount,
    address _user
  ) external;

  function deallocateVestRP(
    uint256 _pid,
    uint256 _amount,
    address _user
  ) external;
}

contract xCONE is ERC20("xCONE", "xCONE"), Ownable, ReentrancyGuard {
  token public CONE;
  staking public divContract;

  constructor(token _token) {
    CONE = _token;
    _mint(msg.sender, 295000e18);
  }

  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  struct vestPosition {
    uint256 totalVested;
    uint256 lastInteractionTime;
    uint256 VestPeriod;
  }

  mapping(address => vestPosition[]) public userInfo;
  mapping(address => uint256) public userPositions;

  uint256 public vestingPeriod = 200 days;
  uint256 public shortVestingPeriod = 20 days;

  function mint(address recipient, uint256 _amount) external onlyOwner {
    _mint(recipient, _amount);
  }

  function burn(uint256 _amount) external {
    _burn(msg.sender, _amount);
  }

  function remainTime(address _address, uint256 id)
    public
    view
    returns (uint256)
  {
    uint256 timePass =
      block.timestamp.sub(userInfo[_address][id].lastInteractionTime);
    uint256 remain;
    if (timePass >= userInfo[msg.sender][id].VestPeriod) {
      remain = 0;
    } else {
      remain = userInfo[msg.sender][id].VestPeriod - timePass;
    }
    return remain;
  }

  function vest(uint256 _amount) external nonReentrant {
    require(this.balanceOf(msg.sender) >= _amount, "xCONE balance too low");

    userInfo[msg.sender].push(
      vestPosition({
        totalVested: _amount,
        lastInteractionTime: block.timestamp,
        VestPeriod: vestingPeriod
      })
    );

    divContract.allocateVestRP(0, _amount.mul(100).div(200), msg.sender);
    userPositions[msg.sender] += 1;
    _burn(msg.sender, _amount);
  }

  function vestHalf(uint256 _amount) external nonReentrant {
    require(this.balanceOf(msg.sender) >= _amount, "xCONE balance too low");

    userInfo[msg.sender].push(
      vestPosition({
        totalVested: _amount.mul(100).div(200),
        lastInteractionTime: block.timestamp,
        VestPeriod: shortVestingPeriod
      })
    );

    divContract.allocateVestRP(0, _amount.mul(100).div(400), msg.sender);
    _burn(msg.sender, _amount);
  }

  function lock(uint256 _amount) external nonReentrant {
    require(CONE.balanceOf(msg.sender) >= _amount, "CONE balance too low");
    uint256 amountOut = _amount;
    _mint(msg.sender, amountOut);
    CONE.burn(msg.sender, _amount);
  }

  function claim(uint256 id) external nonReentrant {
    require(remainTime(msg.sender, id) == 0, "vesting not end");
    vestPosition storage position = userInfo[msg.sender][id];
    uint256 claimAmount = position.totalVested;
    position.totalVested = 0;
    divContract.deallocateVestRP(0, claimAmount.mul(100).div(200), msg.sender);
    CONE.mint(msg.sender, claimAmount);
  }

  function updateStakers(staking _div) external onlyOwner {
    divContract = _div;
  }
}

