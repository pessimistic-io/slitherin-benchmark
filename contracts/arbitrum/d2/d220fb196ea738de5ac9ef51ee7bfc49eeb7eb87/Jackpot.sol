// SPDX-License-Identifier: MIT LICENSE
pragma solidity 0.8.15;

import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./ERC20.sol";
import "./SafeMath.sol";
import "./ISwapRouter.sol";
import "./ISwapTools.sol";
import "./IArbSys.sol";
import "./ECDSA.sol";

contract Jackpot is Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeMath for uint256;
  using ECDSA for bytes32;

  struct Round {
    uint256 startTickIndex;
    uint256 endTickIndex;
    uint256 bonus;
    uint256 timestamp;
    uint256 commitment;
  }

  event Winner(address indexed winner, uint256 tickIndex, uint256 bonus, uint timestamp);
  event NewTick(address indexed user, uint256 indexed probability, uint256 tickIndexFrom, uint256 amount, uint256 amountUSD, uint timestamp);

  EnumerableSet.AddressSet private _callers;
  IERC20 public bonusToken;
  ISwapRouter public swapRouter;
  IArbSys public constant arb = IArbSys(0x0000000000000000000000000000000000000064);

  address[] public ticks;
  Round[] public rounds;
  uint256 public roundIndex;
  uint256 public minBonus;
  uint256 public maxBonus = 1000000 ether;
  uint256 public tokenPrice = 1e12;
  uint256 public totalBonus;
  uint256 public totalBonusClaimed;

  mapping(address => uint256) winners;

  uint256 public tokenPriceTradeAmount = 1e6;
  address[] public tokenPriceTradePath; // USDT => ETH => CHEESE

  constructor(IERC20 bonusToken_, ISwapRouter swapRouter_, address[] memory tokenPriceTradePath_) {
    bonusToken = bonusToken_;
    swapRouter = swapRouter_;
    tokenPriceTradePath = tokenPriceTradePath_;
  }

  function genCommitment() public onlyCaller {
    uint256 bal = bonusToken.balanceOf(address(this)) - (totalBonus - totalBonusClaimed);
    require(bal >= minBonus, 'Jackpot: not enough bonus');

    require(rounds.length == roundIndex, 'Jackpot: commitment already exists');
    Round memory lastRound = rounds[roundIndex];

    require(lastRound.endTickIndex < ticks.length, 'Jackpot: no new tick');

    uint256 bkn = arb.arbBlockNumber();
    rounds.push(
      Round({
        startTickIndex: lastRound.endTickIndex,
        endTickIndex: ticks.length,
        bonus: bal > maxBonus ? maxBonus : bal,
        timestamp: block.timestamp,
        commitment: uint256(keccak256(abi.encodePacked(bkn, arb.arbBlockHash(bkn - 1))))
      })
    );
  }

  function lottery(bytes calldata signature) public onlyCaller {
    require(rounds.length > roundIndex, 'Jackpot: no commitment');
    Round memory pendingRound = rounds[roundIndex];
    roundIndex = rounds.length;

    bytes32 message = keccak256(abi.encodePacked(address(this), 'lottery', pendingRound.commitment));
    require(message.toEthSignedMessageHash().recover(signature) == msg.sender, 'Jackpot: bad signature');

    uint256 winnerIndex = uint256(keccak256(abi.encodePacked(signature))) % (pendingRound.endTickIndex - pendingRound.startTickIndex);
    winnerIndex += pendingRound.startTickIndex;
    address winner = ticks[winnerIndex];

    winners[winner] += pendingRound.bonus;
    totalBonus += pendingRound.bonus;
    emit Winner(winner, winnerIndex, pendingRound.bonus, block.timestamp);
  }

  function claimBonus() public {
    uint256 bonus = winners[msg.sender];
    require(bonus > 0, 'Jackpot: no bonus');
    winners[msg.sender] = 0;
    totalBonusClaimed += bonus;
    bonusToken.transfer(msg.sender, bonus);
  }

  function _addTick(address user, uint256 amount) internal {
    (uint tick, uint256 amountUSD) = getTickTypeWithTradeAmount(amount);
    uint256 from = ticks.length;
    for (uint256 i = 0; i < tick; i++) {
      ticks.push(user);
    }
    emit NewTick(user, tick, from, amount, amountUSD, block.timestamp);
  }

  function _calcPrice() internal {
    uint256 tradeAmount_ = tokenPriceTradeAmount;
    if (tradeAmount_ == 0) return;
    uint256[] memory prices = swapRouter.getAmountsOut(tradeAmount_, tokenPriceTradePath);
    tokenPrice = prices[prices.length - 1];
  }

  function tradeEvent(address, uint256 amount) public onlyCaller {
    _addTick(tx.origin, amount);
    _calcPrice();
  }

  function getTickTypeWithTradeAmount(uint256 amount) public view returns (uint tp, uint256 amountUSD) {
    uint256 value = amount.div(tokenPrice);
    return (getTickTypeWithTradeUsdAmount(value), value);
  }

  function getTickTypeWithTradeUsdAmount(uint256 amount) public pure returns (uint256) {
    if (amount > 1000) {
      return 10;
    }
    return amount / 100;
  }

  function setMinBouns(uint256 val) public onlyOwner {
    require(val < maxBonus, 'bad val');
    minBonus = val;
  }

  function setMaxBouns(uint256 val) public onlyOwner {
    require(val > minBonus, 'bad val');
    maxBonus = val;
  }

  function setTokenPrice(uint256 price) public onlyOwner {
    require(price > 0, 'bad price');
    tokenPrice = price;
  }

  function setSwapRouter(ISwapRouter swapRouter_) public onlyOwner {
    swapRouter = swapRouter_;
  }

  function setTokenPriceTrade(uint256 amount, address[] memory tokenPriceTradePath_) public onlyOwner {
    tokenPriceTradePath = tokenPriceTradePath_;
    tokenPriceTradeAmount = amount;
  }

  function addCaller(address val) public onlyOwner {
    require(val != address(0), 'Jackpot: val is the zero address');
    _callers.add(val);
  }

  function delCaller(address caller) public onlyOwner returns (bool) {
    require(caller != address(0), 'Jackpot: caller is the zero address');
    return _callers.remove(caller);
  }

  function withdraw(IERC20 token, address to, uint256 amount) external onlyOwner {
    if (address(token) == address(0)) {
      payable(to).transfer(amount);
    } else {
      token.transfer(to, amount);
    }
  }

  function getCallers() public view returns (address[] memory ret) {
    return _callers.values();
  }

  function getTicks() public view returns (address[] memory) {
    return ticks;
  }

  function getRounds() public view returns (Round[] memory) {
    return rounds;
  }

  function getTicksLength() public view returns (uint256) {
    return ticks.length;
  }

  function getRoundsLength() public view returns (uint256) {
    return rounds.length;
  }

  function getTicksFrom(uint256 from, uint256 to) public view returns (address[] memory list) {
    uint256 len = ticks.length;
    to = to > len ? len : to;
    from = from > to ? to : from;
    list = new address[](to - from);
    for (uint256 i = from; i < to; i++) {
      list[i - from] = ticks[i];
    }
    return list;
  }

  function getRoundsFrom(uint256 from, uint256 to) public view returns (Round[] memory list) {
    uint256 len = rounds.length;
    to = to > len ? len : to;
    from = from > to ? to : from;
    list = new Round[](to - from);
    for (uint256 i = from; i < to; i++) {
      list[i - from] = rounds[i];
    }
    return list;
  }

  function getLastTicks(uint256 num) public view returns (address[] memory list) {
    uint256 to = ticks.length;
    uint256 from = to > num ? to - num : 0;
    list = new address[](to - from);
    for (uint256 i = from; i < to; i++) {
      list[i - from] = ticks[i];
    }
    return list;
  }

  function getLastRounds(uint256 num) public view returns (Round[] memory list) {
    uint256 to = rounds.length;
    uint256 from = to > num ? to - num : 0;
    list = new Round[](to - from);
    for (uint256 i = from; i < to; i++) {
      list[i - from] = rounds[i];
    }
    return list;
  }

  modifier onlyCaller() {
    require(_callers.contains(_msgSender()), 'onlyCaller');
    _;
  }

  receive() external payable {}
}

