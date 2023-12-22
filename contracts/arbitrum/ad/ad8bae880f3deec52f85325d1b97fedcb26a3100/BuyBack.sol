// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IMarket.sol";
import "./ILabs.sol";
import "./IBonds.sol";

import "./Math.sol";

contract BuyBack is Ownable , ReentrancyGuard{
  uint256 public  dayOfBuyBack;
  uint256 public immutable dayOfWithdraw;
  bytes32 private hashTimeInTheDay;
  address public market;
  IERC20BurnableMinter immutable usdc;
  IERC20BurnableMinter immutable labs;


  constructor(
    uint _dayOfWithdraw,
    uint256 interval,
    IERC20BurnableMinter _lab,
    IERC20BurnableMinter _usdc
  ) {
    dayOfWithdraw = _dayOfWithdraw;
    dayOfBuyBack = _dayOfWithdraw + interval;
    labs= _lab;
    usdc = _usdc;
  }

  function setMarket(address _market) external onlyOwner {
    market = _market;
  }
  /**
   * @dev Constructor.
   * @param _salt - to randomise  the hour of buyback , mixed with block.difficulty , which is surely impredictible
   * 
   */
  function mixTime(string calldata _salt) external {
    require(block.timestamp < dayOfBuyBack, "Too Late");
    hashTimeInTheDay = triHash(
      hashTimeInTheDay,
      keccak256(abi.encodePacked(_salt)),
      keccak256(abi.encodePacked(block.difficulty))
    );
  }
  function triHash(
    bytes32 a,
    bytes32 b,
    bytes32 c
  ) private pure returns (bytes32 value) {
    assembly {
      mstore(0x00, a)
      mstore(0x20, b)
      mstore(0x40, c)
      value := keccak256(0x00, 0x60)
    }
  }

  function _getNumber() internal view returns (uint256 dayTime) {
    uint16 value = uint16(bytes2(hashTimeInTheDay << 16)) / 9;

    dayTime = uint256(value);
  }

  function isOpenned() public view returns (bool isIt) {
    isIt = block.timestamp >= dayOfBuyBack + _getNumber();
  }
/**
 * @dev core function of the buyback
 * Simulate a pool 
 */
  function selllab(uint256 amountToSell) public nonReentrant{
    require(
      isOpenned(),
      "Not Now"
    );
    uint256 ammount0 = usdc.balanceOf(address(this));
    uint256 ammount1 = labs.balanceOf(address(this));
    uint k = ammount0 * ammount1;
    uint256 labAfter = ammount1 + amountToSell;
    uint256 stablesYouGet = ammount0 - (k / labAfter);
    labs.transferFrom(msg.sender, address(this), amountToSell);
    usdc.transfer(msg.sender, stablesYouGet);
  }

/**
 * @dev
 * @param ratiox100  set the y/x ratio , impact the slope of the buyback
 */
  function getStables(uint ratiox100) external onlyOwner {
    require(ratiox100< 100, "Too damn boring");
    require(dayOfWithdraw < block.timestamp , "Not now");
    IMarket(market).pause();
    uint256 stableBal = usdc.balanceOf(market);
    usdc.transferFrom(market, address(this), stableBal);
    ILabs(address(labs)).mintForBuyBack(stableBal * 1e10 * ratiox100);
  }

// in case of missing ratio
  function burnRest(uint amount) external onlyOwner {
    uint day = 3600 * 24; 
    require(dayOfBuyBack + day < block.timestamp, " Let people take the buyback");
      labs.burn(labs.balanceOf(address(this)) - amount);
      dayOfBuyBack += day;
}


}

