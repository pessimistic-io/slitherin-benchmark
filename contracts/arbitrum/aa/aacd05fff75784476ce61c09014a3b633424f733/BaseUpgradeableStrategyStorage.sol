  
pragma solidity 0.5.16;

import "./Initializable.sol";

contract BaseUpgradeableStrategyStorage {

    mapping(bytes32 => address) private addressStorage;
    mapping(bytes32 => uint256) private uint256Storage;
    mapping(bytes32 => bool) private boolStorage;

    function _setUnderlying(address _address) internal {
        _setAddress("underlying", _address);
    }

    function underlying() public view returns (address) {
        return _getAddress("underlying");
    }

    function _setRewardPool(address _address) internal {
        _setAddress("rewardPool", _address);
    }

    function rewardPool() public view returns (address) {
        return _getAddress("rewardPool");
    }

    function _setRewardToken(address _address) internal {
        _setAddress("rewardToken", _address);
    }

    function rewardToken() public view returns (address) {
        return _getAddress("rewardToken");
    }

    function _setVault(address _address) internal {
        _setAddress("vault", _address);
    }

    function vault() public view returns (address) {
        return _getAddress("vault");
    }

    // A flag for disabling selling for a simplified emergency exit
    function _setSell(bool _value) internal {
        _setBool("sell", _value);
    }

    function sell() public view returns (bool) {
        return _getBool("sell");
    }

    function _setPausedInvesting(bool _value) internal {
        _setBool("pausedInvesting", _value);
    }

    function pausedInvesting() public view returns (bool) {
        return _getBool("pausedInvesting");
    }

    function _setSellFloor(uint256 _value) internal {
        _setUint256("sellFloor", _value);
    }

    function sellFloor() public view returns (uint256) {
        return _getUint256("sellFloor");
    }

    // Upgradeability

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

    function _setUint256(string memory _key, uint256 _value) internal {
        uint256Storage[keccak256(abi.encodePacked(_key))] = _value;
    }

    function _setAddress(string memory _key, address _value) internal {
        addressStorage[keccak256(abi.encodePacked(_key))] = _value;
    }

    function _setBool(string memory _key, bool _value) internal {
        boolStorage[keccak256(abi.encodePacked(_key))] = _value;
    }

    function _getUint256(string memory _key) internal view returns (uint256) {
        return uint256Storage[keccak256(abi.encodePacked(_key))];
    }

    function _getAddress(string memory _key) internal view returns (address) {
        return addressStorage[keccak256(abi.encodePacked(_key))];
    }

    function _getBool(string memory _key) internal view returns (bool) {
        return boolStorage[keccak256(abi.encodePacked(_key))];
    }
}
