pragma solidity 0.5.16;

import "./Initializable.sol";

contract VaultStorage is Initializable {
  
  mapping(bytes32 => uint256) private uint256Storage;
  mapping(bytes32 => address) private addressStorage;

  function initialize(
    address _underlying,
    uint256 _toInvestNumerator,
    uint256 _toInvestDenominator,
    uint256 _underlyingUnit,
    uint256 _implementationChangeDelay,
    uint256 _strategyChangeDelay
  ) public initializer {
    _setUnderlying(_underlying);
    _setVaultFractionToInvestNumerator(_toInvestNumerator);
    _setVaultFractionToInvestDenominator(_toInvestDenominator);
    _setUnderlyingUnit(_underlyingUnit);
    _setNextImplementationDelay(_implementationChangeDelay);
    _setStrategyTimeLock(_strategyChangeDelay);
    _setStrategyUpdateTime(0);
    _setFutureStrategy(address(0));
  }

  function _setStrategy(address _address) internal {
    _setAddress("strategy", _address);
  }

  function strategy() public view returns (address) {
    return _getAddress("strategy");
  }

  function _setUnderlying(address _address) internal {
    _setAddress("underlying", _address);
  }

  function underlying() public view returns (address) {
    return _getAddress("underlying");
  }

  function _setUnderlyingUnit(uint256 _value) internal {
    _setUint256("underlyingUnit", _value);
  }

  function underlyingUnit() public view returns (uint256) {
    return _getUint256("underlyingUnit");
  }

  function _setVaultFractionToInvestNumerator(uint256 _value) internal {
    _setUint256("vaultFractionToInvestNumerator", _value);
  }

  function vaultFractionToInvestNumerator() public view returns (uint256) {
    return _getUint256("vaultFractionToInvestNumerator");
  }

  function _setVaultFractionToInvestDenominator(uint256 _value) internal {
    _setUint256("vaultFractionToInvestDenominator", _value);
  }

  function vaultFractionToInvestDenominator() public view returns (uint256) {
    return _getUint256("vaultFractionToInvestDenominator");
  }

  function _setNextImplementation(address _address) internal {
    _setAddress("nextImplementation", _address);
  }

  function nextImplementation() public view returns (address) {
    return _getAddress("nextImplementation");
  }

  function _setNextImplementationTimestamp(uint256 _value) internal {
    _setUint256("nextImplementationTimestamp", _value);
  }

  function nextImplementationTimestamp() public view returns (uint256) {
    return _getUint256("nextImplementationTimestamp");
  }

  function _setNextImplementationDelay(uint256 _value) internal {
    _setUint256("nextImplementationDelay", _value);
  }

  function nextImplementationDelay() public view returns (uint256) {
    return _getUint256("nextImplementationDelay");
  }

  function _setStrategyTimeLock(uint256 _value) internal {
    _setUint256("strategyTimeLock", _value);
  }

  function strategyTimeLock() public view returns (uint256) {
    return _getUint256("strategyTimeLock");
  }

  function _setFutureStrategy(address _value) internal {
    _setAddress("futureStrategy", _value);
  }

  function futureStrategy() public view returns (address) {
    return _getAddress("futureStrategy");
  }

  function _setStrategyUpdateTime(uint256 _value) internal {
    _setUint256("strategyUpdateTime", _value);
  }

  function strategyUpdateTime() public view returns (uint256) {
    return _getUint256("strategyUpdateTime");
  }

  function _setUint256(string memory _key, uint256 _value) private {
    uint256Storage[keccak256(abi.encodePacked(_key))] = _value;
  }

  function _setAddress(string memory _key, address _value) private {
    addressStorage[keccak256(abi.encodePacked(_key))] = _value;
  }

  function _getUint256(string memory _key) private view returns (uint256) {
    return uint256Storage[keccak256(abi.encodePacked(_key))];
  }

  function _getAddress(string memory _key) private view returns (address) {
    return addressStorage[keccak256(abi.encodePacked(_key))];
  }

  uint256[50] private ______gap;
}
