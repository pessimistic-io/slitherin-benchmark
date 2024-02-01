// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ERC20_IERC20.sol";

contract ERC20Disperser is Ownable {
  /// @notice The address of the MAJR ERC20 token
  address public immutable majrErc20Token;

  /// @notice The total amount of tokens that has been rewarded since the start of the MAJR flights
  uint256 public totalTokensRewarded;

  /// @notice The amount of tokens that's left to be claimed by the current contest winners
  uint256 public leftToBeClaimed;

  /// @notice Mapping from address to amount of tokens they can claim
  mapping(address => uint256) public balances;

  /// @notice An event emitted when tokens get deposited to the contract
  event Deposit(address indexed sender, uint256 amount);

  /// @notice An event emitted when the balance for a particular address is updated
  event SetBalance(address indexed target, uint256 balance);

  /// @notice An event emitted when a particular address claims their token rewards
  event Claim(address indexed target, uint256 amount);

  /**
   * @notice Constructor
   * @param _majrErc20Token address
   */
  constructor(address _majrErc20Token) {
    majrErc20Token = _majrErc20Token;
  }

  /**
   * @notice Sets the claimable token balances of the contest winners and makes sure that the contract has enough tokens to support all the claims by the contest winners
   * @param _targets address[] calldata
   * @param _amounts uint256[] calldata
   * @dev Only owner can call it
   */
  function addBalances(
    address[] calldata _targets,
    uint256[] calldata _amounts
  ) external onlyOwner {
    require(
      _targets.length == _amounts.length,
      "ERC20Disperser: Targets and amounts must be of the same length."
    );
    require(_targets.length > 0, "ERC20Disperser: Targets must be non-empty.");

    address _owner = owner();
    uint256 _totalTokenAmount = _getTotalTokenAmount(_amounts);
    require(
      IERC20(majrErc20Token).balanceOf(_owner) >= _totalTokenAmount,
      "ERC20Disperser: Not enough token balance for the contest winners to be claimed."
    );

    totalTokensRewarded += _totalTokenAmount;
    leftToBeClaimed += _totalTokenAmount;

    bool sent = IERC20(majrErc20Token).transferFrom(
      _owner,
      address(this),
      _totalTokenAmount
    );
    require(
      sent,
      "ERC20Disperser: Failed to transfer tokens from the owner to the disperser contract."
    );

    emit Deposit(_owner, _totalTokenAmount);

    for (uint256 i = 0; i < _targets.length; i++) {
      balances[_targets[i]] += _amounts[i];
      emit SetBalance(_targets[i], balances[_targets[i]]);
    }
  }

  /**
   * @notice Sets the claimable balances of the addresses added by mistake to 0 and returns their respective claimable token balances back to the owner
   * @param _targets address[] calldata
   * @dev Only owner can call it
   */
  function removeBalances(address[] calldata _targets) external onlyOwner {
    require(_targets.length > 0, "ERC20Disperser: Targets must be non-empty.");

    address _owner = owner();

    for (uint256 i = 0; i < _targets.length; i++) {
      uint256 _balance = balances[_targets[i]];

      totalTokensRewarded -= _balance;
      leftToBeClaimed -= _balance;

      bool sent = IERC20(majrErc20Token).transfer(_owner, _balance);
      require(sent, "ERC20Disperser: Couldn't send tokens to you.");

      balances[_targets[i]] = 0;
      emit SetBalance(_targets[i], 0);
    }
  }

  /**
   * @notice Allows users to claim their token rewards
   * @dev Only users that won rewards can claim them and only when the token is transferable
   */
  function claim() external {
    uint256 _userBalance = balances[msg.sender];
    require(_userBalance > 0, "ERC20Disperser: You have no tokens to claim.");

    balances[msg.sender] = 0;
    leftToBeClaimed -= _userBalance;

    bool sent = IERC20(majrErc20Token).transfer(msg.sender, _userBalance);
    require(sent, "ERC20Disperser: Couldn't send tokens to you.");

    emit Claim(msg.sender, _userBalance);
  }

  /**
   * @notice Added to support recovering the excess tokens trapped in the contract (i.e. tokens that were not awarded to any contest winner or were transferred to the contract by mistake)
   * @dev Only owner can call it
   */
  function recoverTokens() external onlyOwner {
    uint256 _amount = IERC20(majrErc20Token).balanceOf(address(this)) -
      leftToBeClaimed;
    require(_amount > 0, "ERC20Disperser: No tokens to be recovered.");

    bool sent = IERC20(majrErc20Token).transfer(owner(), _amount);
    require(sent, "ERC20Disperser: Couldn't send tokens to you.");
  }

  /**
   * @notice Gets the total amount from the array of different amounts
   * @param _amounts uint256[] calldata
   * @return uint256
   * @dev Internal utility function used in the addBalances method
   */
  function _getTotalTokenAmount(
    uint256[] calldata _amounts
  ) internal pure returns (uint256) {
    uint256 total;

    for (uint256 i = 0; i < _amounts.length; i++) {
      total += _amounts[i];
    }

    return total;
  }
}

