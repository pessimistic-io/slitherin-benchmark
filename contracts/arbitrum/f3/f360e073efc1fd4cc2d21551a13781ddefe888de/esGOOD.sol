// SPDX-License-Identifier: none
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./ERC20Permit.sol";
import "./ERC20Votes.sol";
import "./AccessControlEnumerable.sol";
import "./ERC20PresetVestingExponential.sol";
import "./IRewardTracker.sol";
import "./GOOD.sol";

/*
  @dev The se a bug in brownie. 
  can be solved by expliciting the *:
    using ShortStrings for string;
    using ShortStrings for ShortString;
  or just not using ERC20Permit :s
*/
contract esGOOD is ERC20, ERC20Permit, ERC20Votes, AccessControlEnumerable, ERC20PresetVestingExponential {
  GOOD private immutable goodToken;
  IRewardTracker public rewardTracker;
  
  /// @notice Access role for reward contracts who are allowed to receive esGOOD 
  bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
  bytes32 public constant MINTER_ROLE   = keccak256("MINTER_ROLE");

  event UpdateRewardTracker(address rewardTracker);
  
  /**
   * @dev Sets {name}, {symbol}, {vestingDuration} as 10368000 ~= 4 month
   */
  constructor(address _goodToken)
    ERC20("GoodEntry Governance Token", "esGOOD")
    ERC20Permit("GoodEntry Governance Token")
    ERC20Vesting(10368000)
  {
    goodToken = GOOD(_goodToken);
    
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(MINTER_ROLE, _msgSender());
  }

  // The functions below are overrides required by Solidity.

  /// @notice Runs after a token transfer/mint/not burn: updates rewards balances. Burn case MUST be handled in withdraw
  /// @dev update the user's balance of esGOOD in the reward contract. Doing it here avoids having to approve+transfer esGOOD
  /// @dev and potentially keep receiving rewards when vesting
  function _afterTokenTransfer(address from, address to, uint256 amount)
    internal
    override(ERC20, ERC20Votes)
  {
    if(to != address(0)){
      // rewards.depositTo(to, )
    }
    super._afterTokenTransfer(from, to, amount);
  }

  function _mint(address to, uint256 amount)
    internal
    override(ERC20, ERC20Votes)
  {
    super._mint(to, amount);
  }

  function _burn(address account, uint256 amount)
    internal
    override(ERC20, ERC20Votes)
  {
    super._burn(account, amount);
  }
  
    // Transfer of vested tokens is forbidden by default
  function transfer(address to, uint256 value) public override (ERC20, ERC20Vesting) returns (bool) {
    return super.transfer(to, value);
  }
  // Transfer of vested tokens is forbidden by default
  function transferFrom(address from, address to, uint256 value) public override (ERC20, ERC20Vesting) returns (bool) {
    return super.transfer(to, value);
  }

  
  /// @notice Change vesting duration
  function updateVestingDuration(uint64 _vestingDuration) onlyRole(DEFAULT_ADMIN_ROLE) public
  {  
    _updateVestingDuration(_vestingDuration); 
  }
  
  
  /// @notice updateRewardTracker
  function updateRewardTracker(address rewardTracker_) onlyRole(DEFAULT_ADMIN_ROLE) public 
  {
    require(rewardTracker_!=address(0), "esGOOD: Invalid RewardTracker address");
    rewardTracker = IRewardTracker(rewardTracker_);
  }
  
  
  
  /// @notice Burn rewards
  function burn(address from, uint256 amount) public onlyRole(MINTER_ROLE) {
    _burn(from, amount);
  }
  
  /// @notice Mint rewards
  function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
    _mint(to, amount);
    require(goodToken.totalSupply() + totalSupply() <= goodToken.cap(), "esGOOD: Mint excess GOOD");
  }
  
  
  /// @notice Restrict transfer and keep track of balance changes in the rewardTracker
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    // Update staking balances
    if(address(rewardTracker)!=address(0)) {
      if(from != address(0)) rewardTracker.unstake(from, amount);
      if(  to != address(0)) rewardTracker.stake(to, amount);
    }
  
    // check only regular transfers, from/to 0x0 are burn/mint and are unavailable/restricted
    if(from!=address(0) && to!=address(0)) _checkRole(TRANSFER_ROLE);
  }
  
  
  /// @notice User can withdraw GOOD tokens once vesting is over
  /// @param account Owner of the vesting structure
  /// @param userVestingId Id of the vesting structure since each user can have several
  function withdraw(address account, uint256 userVestingId) public returns (uint256 received, uint256 penalty){
    require(msg.sender == account || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "esGOOD: Unauthorized Withdrawal");
    (received, penalty) = _withdraw(account, userVestingId);
    _burn(account, received + penalty);
    goodToken.mint(account, received);
  }
  
  /**
   * @dev Allow a user to deposit underlying tokens and mint the corresponding number of wrapped tokens.
   */
  function depositFor(address account, uint256 amount) public returns (bool) {
    require(account != address(this) && account != address(0), "esGOOD: Invalid deposit address");
    goodToken.burn(msg.sender, amount);
    _mint(account, amount);
    return true;
  }
}
