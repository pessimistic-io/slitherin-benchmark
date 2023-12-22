// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IComtesFactory.sol";
import "./ComtesPair.sol";

contract ComtesFactory is IComtesFactory {
  string internal constant DEFAULT_TOKEN_NAME = "ERC20";
  bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(ComtesPair).creationCode));

  address public feeTo;
  address public feeToSetter;
  mapping(address => mapping(address => address)) public getPair;
  address[] public allPairs;

  constructor(address _feeToSetter, address _feeTo) {
    feeToSetter = _feeToSetter;
    feeTo = _feeTo;
  }

  function allPairsLength() external view returns (uint256) {
    return allPairs.length;
  }

  function createPair(address tokenA, address tokenB) external returns (address pair) {
    require(tokenA != tokenB, "ComtesFactory: identical_addresses");
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0), "ComtesFactory: zero_address");
    require(getPair[token0][token1] == address(0), "ComtesFactory: pair_exists"); // single check is sufficient
    bytes memory bytecode = type(ComtesPair).creationCode;
    bytes32 salt = keccak256(abi.encodePacked(token0, token1));
    assembly {
      pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
    }
    string memory symbol = _getTokenSymbolPair(tokenA, tokenB);
    string memory name = string(abi.encodePacked(_getTokenSymbolPair(tokenA, tokenB), " Pair"));
    IComtesPair(pair).initialize(token0, token1, name, symbol);
    getPair[token0][token1] = pair;
    getPair[token1][token0] = pair; // populate mapping in the reverse direction
    allPairs.push(pair);
    emit PairCreated(token0, token1, pair, allPairs.length);
  }

  function _getTokenName(address token) internal returns (string memory) {
    (bool success, bytes memory ret) = token.call(abi.encodeWithSignature("symbol()"));
    if (!success) {
      return DEFAULT_TOKEN_NAME;
    }
    return abi.decode(ret, (string));
  }

  function _getTokenSymbolPair(address tokenA, address tokenB) internal returns (string memory) {
    return string(abi.encodePacked(_getTokenName(tokenA), "-", _getTokenName(tokenB)));
  }

  function setFeeTo(address _feeTo) external {
    require(msg.sender == feeToSetter, "ComtesFactory: forbidden");
    feeTo = _feeTo;
  }

  function setFeeToSetter(address _feeToSetter) external {
    require(msg.sender == feeToSetter, "ComtesFactory: forbidden");
    feeToSetter = _feeToSetter;
  }
}


