// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./BaseToken.sol";

interface IBonusTracker {
  function stakeForAccount(address _fundingAccount, address _account, address _rewardTracker, uint _amount) external;

  function unstakeForAccount(address _account, uint _amount, address _receiver) external;

  function depositSources(address _account, address _sourceTracker) external view returns (uint _amount);

  function stakedAmounts(address _account) external view returns (uint _amount);

  function burntAmounts(address _account) external view returns (uint _amount);
}

contract BonusTracker is IBonusTracker, BaseToken, ReentrancyGuard {
  using SafeERC20 for IERC20;

  IERC20 immutable depositToken;
  mapping(address => mapping(address => uint)) public depositSources; // account => sourceTracker => amount
  mapping(address => uint) public burntAmounts;
  mapping(address => uint) public stakedAmounts;

  constructor(string memory _name, string memory _symbol, address _depositToken) BaseToken(_name, _symbol, true) {
    depositToken = IERC20(_depositToken);
  }

  /** HANDLER */
  function stakeForAccount(
    address _fundingAccount,
    address _account,
    address _rewardTracker,
    uint _amount
  ) external nonReentrant {
    _validateHandler();
    _stake(_fundingAccount, _account, _rewardTracker, _amount);
  }

  function unstakeForAccount(address _account, uint _amount, address _receiver) external nonReentrant {
    _validateHandler();
    _unstake(_account, _amount, _receiver);
  }

  /** PRIVATE */
  function _stake(address _fundingAccount, address _account, address _rewardTracker, uint _amount) private {
    if (_amount == 0) revert FAILED(string.concat(symbol(), ': ', 'invalid amount'));

    unchecked {
      stakedAmounts[_account] += _amount;
      depositSources[_account][_rewardTracker] += _amount;
    }

    _mint(_account, _amount);
    depositToken.safeTransferFrom(_fundingAccount, address(this), _amount);
  }

  function _unstake(address _account, uint _amount, address _receiver) private {
    if (_amount == 0) revert FAILED(string.concat(symbol(), ': ', 'invalid amount'));

    uint _stakedAmounts = stakedAmounts[_account];
    if (_amount > _stakedAmounts) revert FAILED(string.concat(symbol(), ': ', 'amount > stakedAmounts'));
    stakedAmounts[_account] -= _amount;
    burntAmounts[_account] += _amount;

    _burn(_account, _amount);
    depositToken.safeTransfer(_receiver, _amount);
  }
}

