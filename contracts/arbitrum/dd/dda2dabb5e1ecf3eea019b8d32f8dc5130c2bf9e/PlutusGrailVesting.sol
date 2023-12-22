// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";

contract PlutusGrailVesting is Initializable, OwnableUpgradeable, UUPSUpgradeable {
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

  function collect(IERC20[] calldata _tokens) external onlyHandler {
    for (uint i; i < _tokens.length; ++i) {
      _tokens[i].transfer(owner(), _tokens[i].balanceOf(address(this)));
    }
  }

  function execute(
    address _to,
    uint256 _value,
    bytes calldata _data
  ) external onlyHandler returns (bool, bytes memory) {
    if (isCallable[_to] == false) revert FAILED();

    (bool success, bytes memory result) = _to.call{ value: _value }(_data);

    if (!success) {
      revert FAILED();
    }

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

