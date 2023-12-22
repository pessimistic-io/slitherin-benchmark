// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.6.12;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IReferral.sol";

contract Referral is IReferral, Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /**
   * @dev The struct of account information.
   * @param referrer The referrer addresss.
   * @param reward Total pending reward of an address.
   * @param accumReward Total claimed reward of an address.
   * @param referredCount The total referral amount of an address.
   * @param activeTime The active timestamp of an address.
   */
  struct Account {
    address referrer;
    uint256 reward;
    uint256 accumReward;
    uint256 referredCount;
    uint256 activeTime;
  }

  event Activate(address referee, address referrer);
  event ClaimReward(address accountAddress, uint256 reward);
  event UpdateReferralReward(address referee, address referrer, uint256 reward);
  event UpdateMasterChef(address masterChef);

  // MasterChef address.
  address public masterChef;
  // OREO token.
  IERC20 public token;
  // Info of each account
  mapping(address => Account) public accounts;
  // Total rewards distributed
  uint256 public totalReward;
  // Total rewards transferred to this contract
  uint256 public totalRewardTransferred;

  bytes32 public DOMAIN_SEPARATOR;
  // keccak256("Activate(address referee,address referrer)")
  bytes32 public constant ACTIVATE_TYPEHASH = 0x4b1fc20d2fd2102f86b90df2c22a6641f5ef4f7fd96d33e36ab9bd6fbad1cf30;

  constructor(address _tokenAddress) public {
    require(
      _tokenAddress != address(0) && _tokenAddress != address(1),
      "Referral::constructor::_tokenAddress must not be address(0) or address(1)"
    );

    token = IERC20(_tokenAddress);

    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256("Referral"),
        keccak256("1"),
        chainId,
        address(this)
      )
    );
  }

  // Only MasterChef can continue the execution
  modifier onlyMasterChef() {
    require(msg.sender == masterChef, "only masterChef");
    _;
  }

  // Update MasterChef address
  function setMasterChef(address _masterChef) public override onlyOwner {
    require(_masterChef != address(0), "invalid _masterChef");

    masterChef = _masterChef;
    emit UpdateMasterChef(_masterChef);
  }

  // Activates sender
  function activate(address referrer) external override {
    _activate(msg.sender, referrer);
  }

  // Delegates activates from signatory to `referee`
  function activateBySign(
    address referee,
    address referrer,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external override {
    bytes32 digest = keccak256(
      abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(ACTIVATE_TYPEHASH, referee, referrer)))
    );
    address signer = ecrecover(digest, v, r, s);
    require(signer == referee, "invalid signature");

    _activate(referee, referrer);
  }

  // Internal function to activate `referee`
  function _activate(address referee, address referrer) internal {
    require(referee != address(0), "invalid referee");
    require(referee != referrer, "referee = referrer");
    require(accounts[referee].activeTime == 0, "referee account have been activated");
    if (referrer != address(0)) {
      require(accounts[referrer].activeTime > 0, "referrer account is not activated");
    }

    accounts[referee].referrer = referrer;
    accounts[referee].activeTime = block.timestamp;
    if (referrer != address(0)) {
      accounts[referrer].referredCount = accounts[referrer].referredCount.add(1);
    }

    emit Activate(referee, referrer);
  }

  // Function for check whether an address has activated
  function isActivated(address _address) public view override returns (bool) {
    return accounts[_address].activeTime > 0;
  }

  // Function for letting some observer call when some conditions met
  // Currently, the caller will MasterChef after transferring the OREO reward
  function updateReferralReward(address accountAddress, uint256 reward) external override onlyMasterChef {
    totalRewardTransferred = totalRewardTransferred.add(reward);
    if (accounts[accountAddress].referrer != address(0)) {
      Account storage referrerAccount = accounts[accounts[accountAddress].referrer];
      referrerAccount.reward = referrerAccount.reward.add(reward);
      totalReward = totalReward.add(reward);

      emit UpdateReferralReward(accountAddress, accounts[accountAddress].referrer, reward);
    }
  }

  // Claim OREO earned
  function claimReward() external override nonReentrant {
    require(accounts[msg.sender].activeTime > 0, "account is not activated");
    require(accounts[msg.sender].reward > 0, "reward amount = 0");

    Account storage account = accounts[msg.sender];
    uint256 pendingReward = account.reward;
    account.reward = account.reward.sub(pendingReward);
    account.accumReward = account.accumReward.add(pendingReward);
    token.safeTransfer(address(msg.sender), pendingReward);

    emit ClaimReward(msg.sender, pendingReward);
  }
}

