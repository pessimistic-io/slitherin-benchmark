// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IFactory.sol";
import "./BurgerPair.sol";

contract BurgerFactory is IFactory {

  bool public override isPaused;
  address public pauser;
  address public pendingPauser;

  uint256 public stableFee;
  uint256 public volatileFee;
  uint256 public constant MAX_FEE = 30; // 0.3%
  address public feeManager;
  address public pendingFeeManager;

  mapping(address => mapping(address => mapping(bool => address))) public override getPair;
  address[] public allPairs;
  /// @dev Simplified check if its a pair, given that `stable` flag might not be available in peripherals
  mapping(address => bool) public override isPair;

  address internal _temp0;
  address internal _temp1;
  bool internal _temp;

  event PairCreated(
    address indexed token0,
    address indexed token1,
    bool stable,
    address pair,
    uint allPairsLength
  );

  constructor() {
    pauser = msg.sender;
    isPaused = false;
    feeManager = msg.sender;
    stableFee = 2; // 0.02%
    volatileFee = 20; // 0.2%
  }

  function allPairsLength() external view returns (uint) {
    return allPairs.length;
  }

  function setPauser(address _pauser) external {
    require(msg.sender == pauser, "BurgerFactory: Not pauser");
    pendingPauser = _pauser;
  }

  function acceptPauser() external {
    require(msg.sender == pendingPauser, "BurgerFactory: Not pending pauser");
    pauser = pendingPauser;
  }

  function setPause(bool _state) external {
    require(msg.sender == pauser, "BurgerFactory: Not pauser");
    isPaused = _state;
  }

  function setFeeManager(address _feeManager) external {
        require(msg.sender == feeManager, "not fee manager");
        pendingFeeManager = _feeManager;
    }

  function acceptFeeManager() external {
      require(msg.sender == pendingFeeManager, "not pending fee manager");
      feeManager = pendingFeeManager;
  }

  function setFee(bool _stable, uint256 _fee) external {
      require(msg.sender == feeManager, "not fee manager");
      require(_fee <= MAX_FEE, "fee too high");
      require(_fee != 0, "fee must be nonzero");
      if (_stable) {
          stableFee = _fee;
      } else {
          volatileFee = _fee;
      }
  }

  function getFee(bool _stable) public view returns(uint256) {
      return _stable ? stableFee : volatileFee;
  }

  function pairCodeHash() external pure override returns (bytes32) {
    return keccak256(type(BurgerPair).creationCode);
  }

  function getInitializable() external view override returns (address, address, bool) {
    return (_temp0, _temp1, _temp);
  }

  function createPair(address tokenA, address tokenB, bool stable)
  external override returns (address pair) {
    require(tokenA != tokenB, 'BurgerFactory: IDENTICAL_ADDRESSES');
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0), 'BurgerFactory: ZERO_ADDRESS');
    require(getPair[token0][token1][stable] == address(0), 'BurgerFactory: PAIR_EXISTS');
    // notice salt includes stable as well, 3 parameters
    bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable));
    (_temp0, _temp1, _temp) = (token0, token1, stable);
    pair = address(new BurgerPair{salt : salt}());
    getPair[token0][token1][stable] = pair;
    // populate mapping in the reverse direction
    getPair[token1][token0][stable] = pair;
    allPairs.push(pair);
    isPair[pair] = true;
    emit PairCreated(token0, token1, stable, pair, allPairs.length);
  }
}

