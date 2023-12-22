// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./Ownable.sol";
import "./Address.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract TradeOwner is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address internal commissionAddress;
  uint256 public defaultFee;
  uint256 public maxAcceptedTokens;
  uint256 public referFee;
  bool internal referEnabled;
  bool internal contractEnabled;
  uint256 constant feeDivider = 10000;

  struct Pair {
    bool isExist;
    uint256 fee;
  }

  mapping(string=>Pair) internal pairs;

  event ChangedCommissionAddress(address commissionAddress);
  event ChangedDefaultFee(uint256 defaultFee);
  event ChangedReferFee(uint256 referFee);
  event ChangedReferEnabled(bool referEnabled);
  event ChangedMaxAcceptedTokens(uint256 maxAcceptedTokens);
  event ChangedContractDisabled(bool contractEnabled);
  event ChangedPairFee(address token0, address token1, uint256 fee);
  event RescueETH(address rescueAddress, uint256 amount);
  event RescueTokens(address token, address rescueAddress, uint256 amount);

  constructor() {
    defaultFee = 50;
    contractEnabled = true;
    maxAcceptedTokens = 3;
    referFee = 2000;
    referEnabled = true;
  }

  function setCommissionAddress(address _commissionAddress) external onlyOwner {
    require(_commissionAddress != address(0));
    commissionAddress = _commissionAddress;
    emit ChangedCommissionAddress(commissionAddress);
  }

  function setDefaultFee(uint256 _fee) external onlyOwner {
    defaultFee = _fee;
    emit ChangedDefaultFee(defaultFee);
  }

  function setReferFee(uint256 _fee) external onlyOwner {
    referFee = _fee;
    emit ChangedReferFee(_fee);
  }

  function setMaxAcceptedTokens(uint256 _max) external onlyOwner {
    require(_max > 0);
    maxAcceptedTokens = _max;
    emit ChangedMaxAcceptedTokens(_max);
  }

  function setContractEnabled(bool _contractEnabled) external onlyOwner {
    contractEnabled = _contractEnabled;
    emit ChangedContractDisabled(contractEnabled);
  }

  function setReferEnabled(bool _referEnabled) external onlyOwner {
    referEnabled = _referEnabled;
    emit ChangedReferEnabled(referEnabled);
  }

  function rescueETH(address rescueAddress, uint256 amount) external onlyOwner payable {
    payable(rescueAddress).transfer(amount);
    emit RescueETH(rescueAddress, amount);
  }

  function rescueTokens(address token, address rescueAddress, uint256 amount) external onlyOwner payable {
    IERC20(token).safeTransfer(rescueAddress, amount);
    emit RescueTokens(token, rescueAddress, amount);
  }

  function setPairFee(address token0, address token1, uint256 fee) external onlyOwner {
    require(fee > 0);
    require(token0 != token1);

    Pair memory newPair;
    newPair.isExist = true;
    newPair.fee = fee;

    string memory pairOne = _appendAddresses(token0, token1);
    string memory pairTwo = _appendAddresses(token1, token0);

    pairs[pairOne] = newPair;
    pairs[pairTwo] = newPair;

    emit ChangedPairFee(token0, token1, fee);
  }

  function _appendAddresses(address token0, address token1) internal pure returns (string memory) {
    return string(abi.encodePacked(token0, '||', token1));
  }

  function getPairFee(address token0, address token1) public view returns (Pair memory pair) {
    string memory str = _appendAddresses(token0, token1);
    return pairs[str];
  }

  function renounceOwnership() public view override onlyOwner {
    revert("cannot renounce ownership");
  }
}

