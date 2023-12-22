// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";

import "./SafeERC20.sol";
import "./SafeMath.sol";

contract PrizePotGame is Ownable, Pausable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  struct PlayerInfo {
    string username;
    uint256 ticketBalance;
    uint256 totalTokensSpent;
    uint256 lastBuyTimestamp;
  }

  struct RoundInfo {
    uint256 prizePool;
    uint256 lastBuyTimestamp;
    uint256 ticketPrice;
    uint256 timeToWin;
    address winner;
  }

  // Token to buy tickets with
  IERC20 public currencyToken;

  // Current round id
  uint256 public currentRoundId;

  // Dev fee address
  address public devFeeAddress;
  uint256 public devFeeBps;

  uint256 public constant MAX_DEV_FEE_BPS = 2000;

  uint256 public constant MAX_USERNAME_LENGTH = 30;

  uint256 private _totalDevFee;

  // Info of each player
  mapping(address => PlayerInfo) public players;
  // Info of each round
  mapping(uint256 => RoundInfo) public rounds;

  event BuyTicket(uint256 roundId, address indexed player, uint256 ticketCount);
  event Win(uint256 roundId, address indexed player, uint256 winAmount);
  event SetUsername(address indexed player, string username);
  event NewRound(uint256 roundId, uint256 ticketPrice, uint256 timeToWin);
  event UpdateTicketPrice(uint256 roundId, uint256 ticketPrice);
  event UpdateTimeToWin(uint256 roundId, uint256 timeToWin);

  constructor(
    address _currencyToken,
    uint256 _ticketPrice,
    uint256 _timeToWin,
    address _devFeeAddress,
    uint256 _devFeeBps
  ) {
    require(_devFeeBps <= MAX_DEV_FEE_BPS, "devFeeBps must be less than or equal to MAX_DEV_FEE_BPS");
    currencyToken = IERC20(_currencyToken);
    devFeeAddress = _devFeeAddress;
    devFeeBps = _devFeeBps;
    rounds[currentRoundId] = RoundInfo({
      prizePool: 0,
      lastBuyTimestamp: blockTimestamp(),
      ticketPrice: _ticketPrice,
      timeToWin: _timeToWin,
      winner: address(0)
    });
    emit NewRound(currentRoundId, rounds[currentRoundId].ticketPrice, rounds[currentRoundId].timeToWin);
  }

  // An internal function to transfer tokens or ether based on the currency token
  function _transferCurrency(address _to, uint256 _amount) internal {
    require(_amount > 0, "Amount must be greater than 0");
    if (address(currencyToken) == address(0)) {
      payable(_to).transfer(_amount);
    } else {
      currencyToken.safeTransfer(_to, _amount);
    }
  }

  // An internal function to receive tokens or ether based on the currency token
  function _receiveCurrency(address _from, uint256 _amount) internal {
    require(_amount > 0, "Amount must be greater than 0");
    if (address(currencyToken) == address(0)) {
      require(msg.value == _amount, "Send correct amount of ether");
    } else {
      currencyToken.safeTransferFrom(_from, address(this), _amount);
    }
  }

  // An internal function to get the balance of the currency token
  function _currencyBalance(address _address) internal view returns (uint256) {
    if (address(currencyToken) == address(0)) {
      return _address.balance;
    } else {
      return currencyToken.balanceOf(_address);
    }
  }

  function _setUsername(address _player, string memory _username) internal {
    require(bytes(_username).length > 0, "Username must not be empty");
    require(
      bytes(_username).length <= MAX_USERNAME_LENGTH,
      "Username must be less than or equal to MAX_USERNAME_LENGTH"
    );
    PlayerInfo storage player = players[_player];
    player.username = _username;
    emit SetUsername(_player, _username);
  }

  function setPlayerUsername(string calldata _username) external {
    _setUsername(msg.sender, _username);
  }

  function buyAndSetUsername(string calldata _username, uint256 _ticketCount) external payable whenNotPaused {
    _setUsername(msg.sender, _username);
    _buyTicket(msg.sender, _ticketCount);
  }

  function buyTicket(uint256 _ticketCount) external payable whenNotPaused {
    _buyTicket(msg.sender, _ticketCount);
  }

  function _buyTicket(address _player, uint256 _ticketCount) internal {
    require(_ticketCount > 0, "Ticket count must be greater than 0");

    // Check if round is over
    _checkRoundOver();

    // Get player info
    PlayerInfo storage player = players[_player];
    // Get round info
    RoundInfo storage round = rounds[currentRoundId];
    // Calculate total cost of ticket purchase
    uint256 totalCost = round.ticketPrice.mul(_ticketCount);
    // Transfer tokens from player
    _receiveCurrency(_player, totalCost);

    uint256 devFee = totalCost.mul(devFeeBps).div(10000);
    _totalDevFee = _totalDevFee.add(devFee);

    // Update player info
    player.ticketBalance = player.ticketBalance.add(_ticketCount);
    player.totalTokensSpent = player.totalTokensSpent.add(totalCost);
    player.lastBuyTimestamp = blockTimestamp();

    // Update round info
    round.prizePool = round.prizePool.add(totalCost.sub(devFee));
    round.lastBuyTimestamp = blockTimestamp();
    round.winner = _player;

    // Emit event
    emit BuyTicket(currentRoundId, _player, _ticketCount);
  }

  function _checkRoundOver() internal {
    // Get round info
    RoundInfo storage round = rounds[currentRoundId];
    // Check if round is over and has a winner
    if (round.lastBuyTimestamp.add(round.timeToWin) < blockTimestamp()) {
      // Round is over
      if (round.winner != address(0)) {
        // Transfer tokens to winner
        _transferCurrency(round.winner, round.prizePool);
        // Emit event
        emit Win(currentRoundId, round.winner, round.prizePool);
      }

      // Increment round id
      currentRoundId = currentRoundId.add(1);
      // Create new round
      rounds[currentRoundId] = RoundInfo({
        prizePool: 0,
        lastBuyTimestamp: blockTimestamp(),
        ticketPrice: round.ticketPrice,
        timeToWin: round.timeToWin,
        winner: address(0)
      });
      // Emit event
      emit NewRound(currentRoundId, round.ticketPrice, round.timeToWin);
    }
  }

  // TODO: Update for arbitrum
  function blockTimestamp() public view returns (uint256) {
    return block.timestamp;
  }

  function setTimeToWin(uint256 _timeToWin) external onlyOwner {
    // Get round info
    RoundInfo storage round = rounds[currentRoundId];
    round.timeToWin = _timeToWin;
    emit UpdateTimeToWin(currentRoundId, _timeToWin);
  }

  function setTicketPrice(uint256 _ticketPrice) external onlyOwner {
    // Get round info
    RoundInfo storage round = rounds[currentRoundId];
    round.ticketPrice = _ticketPrice;
    emit UpdateTicketPrice(currentRoundId, _ticketPrice);
  }

  function setDevFeeAddress(address _devFeeAddress) external onlyOwner {
    devFeeAddress = _devFeeAddress;
  }

  function setDevFeeBps(uint256 _devFeeBps) external onlyOwner {
    require(_devFeeBps <= MAX_DEV_FEE_BPS, "Dev fee bps too high");
    devFeeBps = _devFeeBps;
  }

  function withdrawDevFee() external onlyOwner {
    require(_totalDevFee > 0, "No dev fee to withdraw");
    _transferCurrency(devFeeAddress, _totalDevFee);
    _totalDevFee = 0;
  }

  function recover(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
    require(_tokenAddress != address(currencyToken), "Cannot withdraw currency token");
    if (_tokenAddress == address(0)) payable(msg.sender).transfer(_tokenAmount);
    else IERC20(_tokenAddress).safeTransfer(msg.sender, _tokenAmount);
  }
}

