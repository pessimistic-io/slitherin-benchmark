// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./VotesUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import { ICheckpointer } from "./Checkpointer.sol";

interface IBestPlutusToken {
  function getCheckpointers() external view returns (address[] memory);

  function totalSupply() external view returns (uint256 _totalSupply);

  function totalSupplyAtTimepoint(uint48 timepoint) external view returns (uint256 _totalSupply);

  function balanceOf(address account) external view returns (uint256 _balance);

  function balanceOfAtTimepoint(address account, uint48 timepoint) external view returns (uint256 _balance);

  error FAILED(string reason);
}

contract BestPlutusToken is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IBestPlutusToken {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
  string public constant name = 'Best Plutus Token';
  string public constant symbol = 'bPLS';
  uint256 public constant decimals = 18;

  EnumerableSetUpgradeable.AddressSet private _checkpointers;
  mapping(address => bool) public isHandler;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
  }

  function getCheckpointers() public view returns (address[] memory) {
    return _checkpointers.values();
  }

  function totalSupply() public view returns (uint256 _totalSupply) {
    uint256 len = _checkpointers.length();

    for (uint256 i; i < len; ) {
      _totalSupply += ICheckpointer(_checkpointers.at(i)).getTotalSupplyWithMultiplier();

      unchecked {
        ++i;
      }
    }
  }

  function totalSupplyAtTimepoint(uint48 timepoint) public view returns (uint256 _totalSupply) {
    uint256 len = _checkpointers.length();

    for (uint256 i; i < len; ) {
      _totalSupply += ICheckpointer(_checkpointers.at(i)).getPastTotalSupplyWithMultiplier(timepoint);

      unchecked {
        ++i;
      }
    }
  }

  function balanceOf(address account) public view returns (uint256 _balance) {
    uint256 len = _checkpointers.length();

    for (uint256 i; i < len; ) {
      _balance += ICheckpointer(_checkpointers.at(i)).getVotesWithMultiplier(account);

      unchecked {
        ++i;
      }
    }
  }

  function balanceOfAtTimepoint(address account, uint48 timepoint) public view returns (uint256 _balance) {
    uint256 len = _checkpointers.length();

    for (uint256 i; i < len; ) {
      _balance += ICheckpointer(_checkpointers.at(i)).getPastVotesWithMultiplier(account, timepoint);

      unchecked {
        ++i;
      }
    }
  }

  /** OWNER */
  function addCheckpointer(address _checkpointer) external onlyOwner {
    bool success = _checkpointers.add(_checkpointer);
    if (!success) revert FAILED('bPLS: Checkpointer exists');
  }

  function removeCheckpointer(address _checkpointer) external onlyOwner {
    bool success = _checkpointers.remove(_checkpointer);
    if (!success) revert FAILED('bPLS: Checkpointer does not exist');
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

