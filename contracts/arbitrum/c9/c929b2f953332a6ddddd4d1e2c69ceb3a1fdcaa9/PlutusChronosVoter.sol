// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";

interface IVoter_V2 {
  function vote(uint _tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external;

  function reset(uint _tokenId) external;

  function usedWeights(uint id) external view returns (uint);

  function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint _tokenId) external;

  function claimFees(address[] memory _fees, address[][] memory _tokens, uint _tokenId) external;
}

interface IVeCHR {
  function increase_unlock_time(uint _tokenId, uint _lock_duration) external;
}

contract PlutusChronosVoter is Initializable, OwnableUpgradeable, UUPSUpgradeable {
  mapping(address => bool) public isHandler;
  mapping(address => bool) public isCallable;
  uint256 private constant MAXTIME = 2 * 365 * 86400;
  uint256 private constant TID = 5410;
  IVoter_V2 private constant VOTER_V2 = IVoter_V2(0xC72b5C6D2C33063E89a50B2F77C99193aE6cEe6c);
  IVeCHR private constant veCHR = IVeCHR(0x9A01857f33aa382b1d5bb96C3180347862432B0d);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
    updateHandler(msg.sender, true);
  }

  function voteMax(address[] calldata _poolVote, uint256[] calldata _weights) external onlyHandler {
    veCHR.increase_unlock_time(TID, MAXTIME);
    VOTER_V2.vote(TID, _poolVote, _weights);
  }

  function reset() external onlyHandler {
    VOTER_V2.reset(TID);
  }

  function vote(address[] calldata _poolVote, uint256[] calldata _weights) external onlyHandler {
    VOTER_V2.vote(TID, _poolVote, _weights);
  }

  function approve(address _token, address _spender) external onlyHandler {
    IERC20(_token).approve(_spender, type(uint256).max);
  }

  function claimBribes(address[] memory _bribes, address[][] memory _tokens) external onlyHandler {
    VOTER_V2.claimBribes(_bribes, _tokens, TID);
  }

  function claimFees(address[] memory _fees, address[][] memory _tokens) external onlyHandler {
    VOTER_V2.claimFees(_fees, _tokens, TID);
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

