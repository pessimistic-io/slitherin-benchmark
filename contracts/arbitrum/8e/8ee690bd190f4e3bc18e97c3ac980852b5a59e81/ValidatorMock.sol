// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

// Mocked endpoint for all of the basic distro flows
// In production this will be three seperate contracts, so build accordingly.
// This contract is simply meant to provide a clean mocked version of the primary endpointss
// needed for the basic distribution apps. Some functions _may_ change slightly, but generally
// integrating based on these mocks should allow us to integrate the completed contracts with little to no friction
// and provide a more stable, modular and accesible testing option for front-end testing.

contract ValidatorMock {
  // RAFFLE VARIABLES
  address public depositor = address(0x0);
  uint256 public deposit = 0;
  // Min = .08 ETH
  uint256 public depositMin = 80000000000000000;
  bool public raffleClaimed = false;

  // EXCHANGE VARIABLES
  bool public exchangeClaimed = false;

  // AUCTION VARIABLES
  bool public auctionClaimed = false;
  uint256 deadline = 0;
  address bidder = address(0x0);
  uint256 bid = 0;
  // This will be nested in the drop struct in prod, and will be set when drop is set
  uint256 dropSize = 20000;

  // *********************************************************************************************************
  // RAFFLE
  // *********************************************************************************************************

  /// @notice This function takes a message value greater than the minimum deposit for the raffle.
  /// @dev    We give the user 1 "ticket" for each valid deposit of depositMin. For example, if deposit min is 1
  ///         submitting a deposit of 2 would yield 2 "tickets" to the raffle. Losing tickets can remove their deposit.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @param recipient Whichever account you want to be _credited_ with the deposit is the recipient, generally msg.sender.
  function addDeposit(uint256 _dropID, address recipient) external payable {
    require(msg.value >= depositMin, " Insufficient Deposit");
    depositor = recipient;
    deposit = msg.value;
    raffleClaimed = false;
  }

  /// @notice This function takes a message value greater than the minimum deposit for the raffle.
  /// @dev    We give the user 1 "ticket" for each valid deposit of depositMin. For example, if deposit min is 1
  ///         submitting a deposit of 2 would yield 2 "tickets" to the raffle. Losing tickets can remove their deposit.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  function addDeposit(uint256 _dropID) external payable {
    require(msg.value >= depositMin, " Insufficient Deposit");
    depositor = msg.sender;
    deposit = msg.value;
    raffleClaimed = false;
  }

  /// @notice Returns the deposit you currently have to the recipient of this function.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @param recipient Whichever account you want the deposit returned tois the recipient, generally msg.sender.
  function removeDeposit(uint256 _dropID, address payable recipient) external {
    depositor = address(0x0);
    deposit = 0;
  }

  /// @notice Sends the raffle winnings to the recipient address.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @param recipient Whichever account you want the winnings sent to is the recipient, generally msg.sender.
  function claimRaffle(uint256 _dropID, address recipient) external {
    raffleClaimed = true;
  }

  /// @notice Returns the deposit that's currently held by the recipient of this function.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @param recipient Whichever account you want to check the deposit of.
  /// @return Current deposit that the supplied recipient has saved for the raffle indicated in _dropID.
  function getDeposit(uint256 _dropID, address recipient)
    external
    view
    returns (uint256)
  {
    return deposit;
  }

  /// @notice Returns the deposit that's currently held by the sender of this function.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @return Current deposit that the supplied recipient has saved for the raffle indicated in _dropID.
  function getDeposit(uint256 _dropID) external view returns (uint256) {
    return deposit;
  }

  /// @notice Returns the minimum deposit required to receive a raffle ticket.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @return Current deposit minimum that must be supplied to secure a rafle ticket.
  function getDepositMin(uint256 _dropID) external view returns (uint256) {
    return deposit;
  }

  /// @notice Get the total number of tokens that will be released in a given drop.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @return Current deposit that the supplied recipient has saved for the raffle indicated in _dropID.
  function getDropSize(uint256 _dropID) external view returns (uint256) {
    return dropSize;
  }

  /// @notice Returns the current number of raffle tickets held by a given raffle partipant.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @param participant Account to check raffle tickets holdings of.
  /// @return Current deposit minimum that must be supplied to secure a rafle ticket.
  function getTicketsCount(uint256 _dropID, address participant)
    external
    view
    returns (uint256)
  {
    // Lazy precision... Good enough for mock but not _accurate_
    return deposit / depositMin;
  }

  /// @notice Returns the total number of raffle tickets purchased by all participants.
  /// @param _dropID This is an entrenal identifier that represents a specific raffle, or "drop".
  /// @return Total of all raffle tickets purchased.
  function getTotalTicketsCount(uint256 _dropID)
    external
    view
    returns (uint256)
  {
    // Lazy precision... Good enough for mock but not _accurate_
    return deposit / depositMin;
  }

  // *********************************************************************************************************
  // TOKEN EXCHANGE
  // *********************************************************************************************************

  /// @notice Allows somebody holding a specific token to receive another token based on holding that token.
  /// @param _dropID This is an entrenal identifier that represents a specific exchange, or "drop". This holds information
  ///                relevant to _which_ token is being exchanged _for which_ token.
  /// @param recipient Whichever account you want the new token sent to is the recipient, generally msg.sender.
  function claimExchange(uint256 _dropID, address recipient) external {}

  /// @notice Informs us whether a specific account has claimed their token for a specific drop.
  /// @param _dropID This is an entrenal identifier that represents a specific exchange, or "drop". This holds information
  ///                relevant to _which_ token is being exchanged _for which_ token.
  /// @param recipient Account we're checking the claim status on.
  function hasClaimed(uint256 _dropID, address recipient)
    external
    view
    returns (bool)
  {
    return exchangeClaimed;
  }

  // *********************************************************************************************************
  // AUCTION
  // *********************************************************************************************************

  /// @notice Take a message value and adds it to the bidders current bid.
  /// @dev    This is strictly additive, the msg.value is _always_ compounded with this function.
  /// @param _dropID This is an entrenal identifier that represents a specific auction, or "drop".
  /// @param bidder Whichever account you want to be _credited_ with the bid is the bidder, generally msg.sender.
  function addBid(uint256 _dropID, address bidder) external payable {
    bidder = bidder;
    bid = msg.value;
  }

  /// @notice Take a message value and adds it to the bidders current bid.
  /// @dev    This is strictly additive, the msg.value is _always_ compounded with this function.
  /// @param _dropID This is an entrenal identifier that represents a specific auction, or "drop".
  function addBid(uint256 _dropID) external payable {
    bidder = msg.sender;
    bid = msg.value;
  }

  /// @notice Returns the bid sender currently has to the recipient of this function.
  /// @param _dropID This is an entrenal identifier that represents a specific auction, or "drop".
  /// @param recipient Whichever account you want the bid returned to is the recipient, generally msg.sender.
  function removeBid(uint256 _dropID, address recipient) external {
    bidder = address(0x0);
    bid = 0;
  }

  /// @notice Sends the auction winnings to the recipient address.
  /// @param _dropID This is an entrenal identifier that represents a specific auction, or "drop".
  /// @param recipient Whichever account you want the winnings sent to is the recipient, generally msg.sender.
  function claimAuction(uint256 _dropID, address recipient) external {
    auctionClaimed = true;
  }

  /// @notice Sends the auction winnings to the senders address.
  /// @param _dropID This is an entrenal identifier that represents a specific auction, or "drop".
  function claimAuction(uint256 _dropID) external {
    auctionClaimed = true;
  }

  /// @notice Get the time remaining for the given drop.
  /// @param _dropID This is an entrenal identifier that represents a specific auction, or "drop".
  /// @return Current time remaining in the selected auction.
  function timeRemaining(uint256 _dropID) external view returns (uint256) {
    return deadline - block.timestamp;
  }

  /// @notice Get the current bid of the requested bidder.
  /// @param _dropID This is an entrenal identifier that represents a specific auction, or "drop".
  /// @param bidder Whichever account you want to check the bid of.
  /// @return Current bid of the requested bidder.
  function getBid(uint256 _dropID, address bidder)
    external
    view
    returns (uint256)
  {
    return bid;
  }

  /// @notice Set a new deadline for a given auction.
  /// @dev In prod this will be protected - leaving it open for development just to make things easier.
  /// @param _dropID This is an entrenal identifier that represents a specific auction, or "drop".
  /// @param _deadline Auction deadline supplied in _seconds since epoch_
  function setDeadline(uint256 _dropID, uint256 _deadline) external {
    deadline = _deadline;
  }
}

