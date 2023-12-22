// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC721Receiver.sol";

import "./IEquilibreVoter.sol";
import "./IVeVARA.sol";
import "./DyVARAManager.sol";
import "./console.sol";

interface IEquilibreBoostedStrategy {
  function want() external view returns (IERC20Upgradeable);

  function gauge() external view returns (address);
}


interface IGauge {
  function getReward(address user, address[] calldata tokens) external;

  function getReward(uint256 id, address[] calldata tokens) external;

  function deposit(uint256 amount, uint256 tokenId) external;

  function withdraw(uint256 amount) external;

  function balanceOf(address user) external view returns (uint256);
}

interface IMintChecker {
  function shouldMint() external view returns (bool);

  function swap(address, bytes calldata, uint256) external;
}

contract ChronosStaker is DyVARAManager, ReentrancyGuardUpgradeable, ERC20Upgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  uint256 public constant MAX_LOCK = 2 * 365 * 86400;

  // Addresses used
  IEquilibreVoter public solidVoter;
  IVeVARA public veToken;
  uint256 public veTokenId;
  IERC20Upgradeable public want;
  address public treasury;

  // Strategy mapping
  mapping(address => address) public whitelistedStrategy;
  mapping(address => address) public replacementStrategy;

  event SetTreasury(address treasury);
  event DepositWant(uint256 tvl);
  event Withdraw(uint256 amount);
  event CreateLock(address indexed user, uint256 veTokenId, uint256 amount, uint256 unlockTime);
  event IncreaseTime(address indexed user, uint256 veTokenId, uint256 unlockTime);
  event ClaimVeEmissions(address indexed user, uint256 veTokenId, uint256 amount);
  event ClaimRewards(address indexed user, address gauges, address[] tokens);
  event TransferVeToken(address indexed user, address to, uint256 veTokenId);
  event RecoverTokens(address token, uint256 amount);
  event Release(address indexed user, uint256 veTokenId, uint256 amount);

  address public mintChecker;

  function __ChronosStaker_init(
    address _solidVoter,
    address _treasury,
    address _keeper,
    address _voter,
    string memory _name,
    string memory _symbol,
    address _want
  ) public initializer {
    __DyVARAManager_init(_keeper, _voter);
    __Ownable_init();
    __ReentrancyGuard_init();
    solidVoter = IEquilibreVoter(_solidVoter);
    veToken = IVeVARA(solidVoter._ve());
    treasury = _treasury;
    want = IERC20Upgradeable(_want);
    __ERC20_init_unchained(_name, _symbol);
    _giveAllowances();
  }

  //  --- Pass Through Contract Functions Below ---

  /**
   * @notice  Deposits all of want from user into the contract
   * @dev     Simsala
   */
  function depositAll() external {
    _deposit(want.balanceOf(msg.sender));
  }

  /**
   * @notice  Deposits specific quantity of want for user
   * @dev     Simsala
   * @param   _amount  quantity to be deposited
   */
  function deposit(uint256 _amount) external {
    _deposit(_amount);
  }

  /**
   * @notice  Deposits $VARA for $spTETU and sends depositor minted token
   * @dev     Simsala
   * @param   _amount  amount to be deposited
   */
  function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
    console.log("deposit", _amount);
    require(canMint(), "!canMint");
    uint256 _pool = balanceOfVara();
    want.safeTransferFrom(msg.sender, address(this), _amount);
    uint256 _after = balanceOfVara();
    _amount = _after - (_pool);

    uint tax = (_amount * 98) / 100;
    console.log("tax", tax);
    console.log("amount", _amount);
    veToken.increase_amount(veTokenId, tax);

    tax = _amount - tax;
    console.log("tax 2", tax);
    console.log("locked");
    console.log("own balance", want.balanceOf(address(this)));
    want.safeTransfer(treasury, tax);
    console.log("transferred to treasury");

    (, , bool shouldIncreaseLock) = lockInfo();
    if (shouldIncreaseLock) {
      veToken.increase_unlock_time(veTokenId, MAX_LOCK);
    }
    // Additional check for deflationary tokens

    if (tax > 0) {

      _mint(msg.sender, _amount - tax);
      emit DepositWant(totalVara());
    }
  }


  function depositViaChecker(address _oneInchRouter, bytes memory _data, uint256 _amount) external nonReentrant {
    require(!canMint(), "canMint");
    want.safeTransferFrom(msg.sender, address(this), _amount);
    IERC20Upgradeable(want).safeApprove(mintChecker, _amount);
    IMintChecker(mintChecker).swap(_oneInchRouter, _data, _amount);
  }

  /**
   * @notice  Calculates how much of the $VARA is locked
   * @dev     Simsala
   * @return  vara  returns the quantity of $VARA in VE
   */
  function balanceOfVaraInVe() public view returns (uint256 vara) {
    return veToken.balanceOfNFT(veTokenId);
  }

  /**
   * @notice  dictates balance of want in contract
   * @return  uint256  quantity of $VARA in Contract
   */
  function balanceOfVara() public view returns (uint256) {
    return IERC20Upgradeable(want).balanceOf(address(this));
  }

  /**
   * @dev Returns information about the lock status of a token.
   * @return endTime The time at which the token will be unlocked.
   * @return secondsRemaining The number of seconds until the token is unlocked.
   * @return shouldIncreaseLock Whether the lock period should be increased.
   */
  function lockInfo() public view returns (uint256 endTime, uint256 secondsRemaining, bool shouldIncreaseLock) {
    endTime = veToken.locked__end(veTokenId);
    uint256 unlockTime = ((block.timestamp + MAX_LOCK) / 1 weeks) * 1 weeks;
    secondsRemaining = endTime > block.timestamp ? endTime - block.timestamp : 0;
    shouldIncreaseLock = unlockTime > endTime ? true : false;
  }

  function canMint() public view returns (bool) {
    if (mintChecker == address(0)) return true;
    return IMintChecker(mintChecker).shouldMint();
  }

  /**
   * @notice  calculates all $VARA in all contracts
   * @dev     Simsala
   * @return  uint256  returns the $VARA in all contracts
   */
  function totalVara() public view returns (uint256) {
    return balanceOfVara() + (balanceOfVaraInVe());
  }

  // --- Vote Related Functions ---



  // vote for emission weights
  function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external onlyVoter {
    solidVoter.vote(veTokenId, _tokenVote, _weights);
  }

  // reset current votes
  function resetVote() external onlyVoter {
    solidVoter.reset(veTokenId);
  }

  function claimMultipleOwnerRewards(address[] calldata _gauges, address[][] calldata _tokens) external onlyManager {
    for (uint256 i; i < _gauges.length; ) {
      claimOwnerRewards(_gauges[i], _tokens[i]);
      unchecked {
        ++i;
      }
    }
  }

  // claim owner rewards such as trading fees and bribes from gauges, transferred to treasury
  function claimOwnerRewards(address _gauge, address[] memory _tokens) public onlyManager {
    IGauge(_gauge).getReward(veTokenId, _tokens);
    for (uint256 i; i < _tokens.length; ) {
      address _reward = _tokens[i];
      uint256 _rewardBal = IERC20Upgradeable(_reward).balanceOf(address(this));

      if (_rewardBal > 0) {
        IERC20Upgradeable(_reward).safeTransfer(treasury, _rewardBal);
      }
      unchecked {
        ++i;
      }
    }

    emit ClaimRewards(msg.sender, _gauge, _tokens);
  }

  // --- Token Management ---

  // create a new veToken if none is assigned to this address
  function createLock(uint256 _amount, uint256 _lock_duration, bool init) external onlyManager {
    require(veTokenId == 0, "veToken > 0");

    if (init) {
      veTokenId = veToken.tokenOfOwnerByIndex(msg.sender, 0);
      veToken.safeTransferFrom(msg.sender, address(this), veTokenId);
    } else {
      require(_amount > 0, "amount == 0");
      want.safeTransferFrom(address(msg.sender), address(this), _amount);
      veTokenId = veToken.create_lock(_amount, _lock_duration);

      emit CreateLock(msg.sender, veTokenId, _amount, _lock_duration);
    }
  }

  /**
   * @dev Merges two veTokens into one. The second token is burned and its balance is added to the first token.
   * @param _fromId The ID of the token to merge into the first token.
   */
  function merge(uint256 _fromId) external {
    require(_fromId != veTokenId, "cannot burn main veTokenId");
    veToken.safeTransferFrom(msg.sender, address(this), _fromId);
    veToken.merge(_fromId, veTokenId);
  }

  // extend lock time for veToken to increase voting power
  function increaseUnlockTime(uint256 _lock_duration) external onlyManager {
    veToken.increase_unlock_time(veTokenId, _lock_duration);
    emit IncreaseTime(msg.sender, veTokenId, _lock_duration);
  }

  function increaseAmount() public {
    uint256 bal = IERC20Upgradeable(address(want)).balanceOf(address(this));
    require(bal > 0, "no balance");
    veToken.increase_amount(veTokenId, bal);
  }

  // transfer veToken to another address, must be detached from all gauges first
  function transferVeToken(address _to) external onlyOwner {
    uint256 transferId = veTokenId;
    veTokenId = 0;
    veToken.safeTransferFrom(address(this), _to, transferId);

    emit TransferVeToken(msg.sender, _to, transferId);
  }

  function setTreasury(address _treasury) external onlyOwner {
    treasury = _treasury;
  }

  // confirmation required for receiving veToken to smart contract
  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) external view returns (bytes4) {
    operator;
    from;
    tokenId;
    data;
    require(msg.sender == address(veToken), "!veToken");
    return bytes4(keccak256("onERC721Received(address,address,uint,bytes)"));
  }

  /**
   * @notice  Gives approval for all necessary tokens to all necessary contracts
   */
  function _giveAllowances() internal {
    IERC20Upgradeable(want).safeApprove(address(veToken), type(uint256).max);
  }

  /**
   * @notice  Removes approval for all necessary tokens to all necessary contracts
   */
  function _removeAllowances() internal {
    IERC20Upgradeable(want).safeApprove(address(veToken), 0);
  }

  function setMintChecker(address _mintChecker) external onlyManager {
    mintChecker = _mintChecker;
  }
}

