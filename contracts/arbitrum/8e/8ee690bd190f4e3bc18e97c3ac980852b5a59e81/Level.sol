import "./IAttribute.sol";
import "./ERC20.sol";
import "./IERC20.sol";

// What are the tradeoffs of having many contracts (one level contract per player) vs 1 contract (one level contract period)
// The assumption is this is going to be much more fuel efficient on _access_ but less eficient on _creation_
// Where do we make compromises for creation time vs access time?
contract Level is IAttribute, ERC20 {
  // Not sure the URI is actually needed? What are we using this for?
  uint256 public uri = 10;

  // This needs to be exploded out into it's own ERC20
  uint256 public currentXP = 100;

  uint256 public currentLvl = 1;

  uint256 public lastTime = 0;

  uint256 public maxXPDaily = 10;

  uint256[] public requiredXp;
  uint256 private _dripRate;
  uint256 private _maxAmount;
  IERC20 private _requiredToken;

  uint256 private constant _BASE = 10000;

  mapping(address => bool) private _senderWhitelist;

  mapping(address => uint256) private _balances;

  // EXP calculations per level are handled off-chain, and updated
  constructor(
    uint256[] memory _requiredXp,
    IERC20 requiredToken_,
    uint256 maxAmount_,
    uint256 dripRate_
  ) ERC20("Level", "LVL") {
    _dripRate = dripRate_;
    lastTime = block.timestamp;
    requiredXp = _requiredXp;
    _maxAmount = maxAmount_;
    _requiredToken = requiredToken_;
  }

  function stake(uint256 amount) external {
    _accrueXP();
    require(
      _balances[msg.sender] + amount <= _maxAmount,
      "Sorry that exceeds the max staking amount"
    );
    _balances[msg.sender] += amount;
    _requiredToken.transferFrom(msg.sender, address(this), amount);
  }

  function unstake(uint256 amount) external {
    _accrueXP();
    _requiredToken.transferFrom(address(this), msg.sender, amount);
    _balances[msg.sender] -= amount;
  }

  function getURI() external view override returns (uint256) {
    return uri;
  }

  function attribute() external view override returns (uint256) {
    return currentLvl;
  }

  function adjustAttribute(uint256 newAttribute) external override {
    _accrueXP();
  }

  // Obviously needs permissions
  // Need to make it so that we can make this append only
  function setXPRequiremenets(uint256[] memory _requiredXp) external {
    requiredXp = _requiredXp;
  }

  function setSpecificLevel(uint256 newRequirement, uint256 index) external {
    requiredXp[index] = newRequirement;
  }

  function _accrueXP() internal {
    uint256 timePassed = block.timestamp - lastTime;
    // Make this calculation more precise; I think we're "shaving off" some of the XP so to speak; maybe that's just tought titties
    // (Balance of sender * total time passed sincce last accrual in blocks * drip rate) /
    currentXP +=
      (_balances[msg.sender] * (timePassed * _dripRate) * _BASE) /
      (_maxAmount * _BASE);
    // I think this accounts for the lost precision but double-check plz
    lastTime = block.timestamp;
  }

  // Need to tweak this; as this stands if we change XP requirements the level will be maintained
  // What's the desired result if we change the XP requirements? Should people be able to lose levels? Probably not, that sounds lame
  function level() public {
    _accrueXP();
    // Should revert if the player doesn't have sufficient XP
    currentXP -= requiredXp[currentLvl];
    currentLvl += 1;
  }

  function getLevel() public {}

  function _beforeTokenTransfer(
    address from,
    address,
    uint256
  ) internal view override {
    require(_senderWhitelist[from] == true, "Sender must be whitelisted");
  }
}

