// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface ICore {
	event Initialized(address indexed initializer);
	event PriceUpdated(uint256 indexed price_);
	event Rebased(uint256 indexed rebaseDistributed_, uint256 indexed rebaseTotal_);
	event Logger(uint256 shortIndex, uint256 longIndex, uint256 indexed shortRebase_, uint256 indexed longRebased_);
	event Deposited(address indexed user_, uint256 indexed shortAmount_, uint256 indexed longAmount_);
	event Withdrawn(address indexed to_, uint256 indexed shortAmount_, uint256 indexed longAmount_);
	event Swaped(address indexed user_, bool indexed fromLongToShort_, uint256 indexed amount_);
	event Sponsored(address indexed user_, uint256 indexed amount_);
	event SponsorWithdrawn(address indexed user_, uint256 indexed amount_);

	event HedgeLog(uint256 epoch, bool isLong, uint256 rebaseTotalAmount);

	// soft-hedge data
	struct HedgeInfo {
		uint256 lastPrice;
		uint256 hedgeTokenPrice;
		uint256 rebaseTime;
		uint256 cnt; //
	}

	struct Log {
		bool isLev; // the win side
		uint256 atualRebasedAmount;
		uint256 totalRebasedAmount;
		uint256 timestampOccured;
		uint256 index; // ohm index
		uint256 tokenIdx; // idx of our HedgeToken
	}

	function deposit(uint256 shortAmount_, uint256 longAmount_) external;

	function depositFor(
		address user_,
		uint256 shortAmount_,
		uint256 longAmount_
	) external;

	function withdraw(uint256 shortAmount_, uint256 longAmount_) external;

	function withdrawTo(
		address recipent_,
		uint256 shortAmount_,
		uint256 longAmount_
	) external;

	function withdrawAllWhenPaused() external;

	function sponsorDeposit(uint256 amount_) external;

	function sponsorWithdraw(uint256 amount_) external;

	function swap(bool fromLongToShort_, uint256 amount_) external;

	function hedgeCoreStatus() external view returns (bool);

	function isSTokenRebased() external view returns (bool);

	function startNewHedge() external;

	function updatePriceBeforeRebase() external returns (uint256);
}

