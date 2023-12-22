// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

import "./Verifier.sol";
import "./AirdropVerifier.sol";

contract Claim is Ownable, ReentrancyGuard, Verifier, AirdropVerifier {
    struct Holder {
        address owner;
        uint256 heldNfts;
        uint256 transferredTokens;
        bool claimed;
    }

    struct AirdropClaim {
        address owner;
        uint256 timeStamp;
        uint256 transferredTokens;
    }

    mapping(address => Holder) internal _holders;
    mapping(address => AirdropClaim) internal _claimedAirdrop;
    address public immutable tokenToClaimAddress;
    IERC20 public immutable tokenToClaim;
    uint256 public totalTokensClaimed;
    uint256 public airdropTotalTokensClaimed;
    uint256 public constant AIRDROP_AMOUNT = 17_700_000_000_000; // Same value as Tier 4
    uint256 public startedTimeStamp = 0;
    uint256 public withdrawTimeStamp = 0;

    event ClaimedTokens(address indexed to, uint256 transferAmount, uint256 snapshottedNftHoldings);

    error ContractBalanceIsZero();
    error WithdrawingNotAllowedYet();
    error ClaimingAlreadyStarted();
    error ClaimingHasNotStartedYet();
    error AddressCannotBeZero();
    error Bytes32CannotBeEmpty();
    error AlreadyClaimed();
    error NotHoldingPreviousNfts();

    constructor(
        address claimTokenAddress_,
        bytes32 root_,
        bytes32 airdropRoot_
    )
        Verifier(root_)
        AirdropVerifier(airdropRoot_)
    {
        _checkZeroAddress(claimTokenAddress_);
        _checkBytesAreNotEmpty(root_);
        _checkBytesAreNotEmpty(airdropRoot_);

        tokenToClaimAddress = claimTokenAddress_;
        tokenToClaim = IERC20(claimTokenAddress_);
    }

    function _verify(
        bytes32[] memory proof,
        address addr,
        uint256 amount
    )
        internal
        override
        view
    {
        super._verify(proof, addr, amount);

        if(_hasCallerClaimed(addr))
            revert AlreadyClaimed();
    }

    function _airdropVerify(
        bytes32[] memory proof,
        address addr
    )
        internal
        override
        view
    {
        super._airdropVerify(proof, addr);

        if(_claimedAirdrop[addr].owner != address(0))
            revert AlreadyClaimed();
    }

    function claimAirdrop(bytes32[] memory proof) external nonReentrant() {
        _hasClaimingStarted();
        address caller = msg.sender;

        // Verify the caller that he is able to claim with the amount of previous nft tokens
        _airdropVerify(proof, caller);

        uint256 transferAmount = AIRDROP_AMOUNT;

        // Set claimed to true
        _claimedAirdrop[caller] = AirdropClaim({
            owner: caller,
            transferredTokens: transferAmount,
            timeStamp: block.timestamp
        });

        // Transfer tokens
        require(tokenToClaim.transfer(caller, transferAmount));

        // Add tokens to claim to the totalTokensClaimed variable
        airdropTotalTokensClaimed += transferAmount;

        emit ClaimedTokens(caller, transferAmount, 0);
    }

    function claim(bytes32[] memory proof, uint256 amount) external nonReentrant() {
        _hasClaimingStarted();
        address caller = msg.sender;

        // Verify the caller that he is able to claim with the amount of previous nft tokens
        _verify(proof, caller, amount);

        uint256 transferAmount = _getTierAmount(amount);

        // Set claimed to true
        _holders[caller] = Holder({
            owner: caller,
            heldNfts: amount,
            transferredTokens: transferAmount,
            claimed: true
        });

        // Transfer tokens
        require(tokenToClaim.transfer(caller, transferAmount));

        // Add tokens to claim to the totalTokensClaimed variable
        totalTokensClaimed += transferAmount;

        emit ClaimedTokens(caller, transferAmount, amount);
    }

    // Can start only once
    function startClaiming() external onlyOwner() {
        if(startedTimeStamp != 0)
            revert ClaimingAlreadyStarted();

        uint256 timeStamp = block.timestamp;
        startedTimeStamp = timeStamp;
        withdrawTimeStamp = timeStamp + 30 days;
    }

    function withdrawRemainingTokensAfterClaimTime(address to) external onlyOwner() {
        _isOwnerAbleToWithdraw();

        uint256 contractTokenBalance = _isContractBalanceForClaimingTokensZero();
        tokenToClaim.transfer(to, contractTokenBalance);
    }

    function _hasCallerClaimed(address claimer_) internal view returns(bool) {
        return _holders[claimer_].claimed;
    }

    function _checkBytesAreNotEmpty(bytes32 bytes_) internal pure {
        if(bytes_ == bytes32(0))
            revert Bytes32CannotBeEmpty();
    }

    function _checkZeroAddress(address addressToCheck) internal pure {
        if(addressToCheck == address(0))
            revert AddressCannotBeZero();
    }
    function _isContractBalanceForClaimingTokensZero() internal view returns(uint256 contractTokenBalance) {
        contractTokenBalance = tokenToClaim.balanceOf(address(this));

        if(contractTokenBalance == 0)
            revert ContractBalanceIsZero();
    }
    function _isOwnerAbleToWithdraw() internal view {
        if(block.timestamp < withdrawTimeStamp)
            revert WithdrawingNotAllowedYet();
    }

    function _getTierAmount(uint256 heldNfts) internal pure returns(uint256 transferAmount) {
        if(heldNfts == 0)
            revert NotHoldingPreviousNfts();
        // Tier 1
        if(1 <= heldNfts && heldNfts <= 2)
            transferAmount = 840_750_000_000;
        // Tier 2
        else if(3 <= heldNfts && heldNfts <= 4)
            transferAmount = 3_375_000_000_000;
        // Tier 3
        else if(5 <= heldNfts && heldNfts <= 9)
            transferAmount = 7_750_000_000_000;
        // Tier 4
        else if(heldNfts >= 10)
            transferAmount = 17_700_000_000_000;
    }

    function _hasClaimingStarted() internal view {
        if(startedTimeStamp == 0)
            revert ClaimingHasNotStartedYet();
    }

    function getHolder(address owner_)
        public
        view
        returns(
            address ownerAddress,
            uint256 heldNfts,
            uint256 transferredTokens,
            bool claimed
        )
    {
        Holder memory holder = _holders[owner_];

        ownerAddress = holder.owner;
        heldNfts = holder.heldNfts;
        transferredTokens = holder.transferredTokens;
        claimed = holder.claimed;
    }

    function getAirdropHolder(address owner_)
        public
        view
        returns(
            address ownerAddress,
            uint256 timeStamp,
            uint256 transferredTokens
        )
    {
        AirdropClaim memory holder = _claimedAirdrop[owner_];

        ownerAddress = holder.owner;
        timeStamp = holder.timeStamp;
        transferredTokens = holder.transferredTokens;
    }

    function getTotalTokensClaimed()
        external
        view
        returns(uint256 totalClaimedTokens)
    {
        totalClaimedTokens = totalTokensClaimed + airdropTotalTokensClaimed;
    }
}
