// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";

contract FeeCollectorV3 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
  mapping(address => bool) public isHandler;
  mapping(address => bool) public isCallable;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
    updateHandler(msg.sender, true);
  }

  function approve(address _token, address _spender) external onlyHandler {
    IERC20(_token).approve(_spender, type(uint256).max);
  }

  function collect(IERC20 _token, uint256 _amount) external onlyHandler {
    if (address(this).balance != 0) {
      payable(owner()).transfer(address(this).balance);
    }

    if (_amount == 0) {
      _amount = _token.balanceOf(address(this));
    }

    _token.transfer(owner(), _amount);
  }

  function execute(
    address _to,
    uint256 _value,
    bytes calldata _data
  ) external onlyHandler returns (bool, bytes memory) {
    if (isCallable[_to] == false) revert FAILED();

    (bool success, bytes memory result) = _to.call{ value: _value }(_data);
    return (success, result);
  }

  modifier onlyHandler() {
    if (isHandler[msg.sender] == false) revert UNAUTHORIZED();
    _;
  }

  function updateHandler(address _handler, bool _isActive) public onlyOwner {
    isHandler[_handler] = _isActive;
  }

  function updateCallable(address _callable, bool _isActive) public onlyOwner {
    isCallable[_callable] = _isActive;
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  error UNAUTHORIZED();
  error FAILED();
}

