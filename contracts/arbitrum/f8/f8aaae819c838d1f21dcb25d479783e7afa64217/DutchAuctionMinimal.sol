pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

//----------------------------------------------------------------------------------
// I n s t a n t
//
// .:mmm. .:mmm:. .ii. .:SSSSSSSSSSSSS. .oOOOOOOOOOOOo.
// .mMM'':Mm. .:MM'':Mm:. .II: :SSs.......... .oOO'''''''''''OOo.
// .:Mm' ':Mm. .:Mm' 'MM:. .II: 'sSSSSSSSSSSSSS:. :OO. .OO:
// .'mMm' ':MM:.:MMm' ':MM:. .II: .:...........:SS. 'OOo:.........:oOO'
// 'mMm' ':MMmm' 'mMm: II: 'sSSSSSSSSSSSSS' 'oOOOOOOOOOOOO'
//
//----------------------------------------------------------------------------------
//
// Chef Gonpachi's Dutch Auction
//
// A declining price auction with fair price discovery.
//
// Inspired by DutchSwap's Dutch Auctions
// https://github.com/deepyr/DutchSwap
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// Made for Sushi.com
//
// Enjoy. (c) Chef Gonpachi, Kusatoshi, SSMikazu 2021
// <https://github.com/chefgonpachi/MISO/>
//
// ---------------------------------------------------------------------
// SPDX-License-Identifier: GPL-3.0
// ---------------------------------------------------------------------

import "./ReentrancyGuard.sol";
import "./MISOAccessControls.sol";
import "./SafeTransfer.sol";
import "./BoringMath.sol";
import "./BoringERC20.sol";

/// @notice Attribution to delta.financial
/// @notice Attribution to dutchswap.com

contract DutchAuctionMinimal is
    MISOAccessControls,
    SafeTransfer,
    ReentrancyGuard
{
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    using BoringERC20 for IERC20;

    /// @dev The placeholder ETH address.
    address private constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Main market variables.
    struct MarketInfo {
        uint64 startTime;
        uint64 endTime;
        uint128 totalTokens;
    }
    MarketInfo public marketInfo;

    /// @notice Market price variables.
    struct MarketPrice {
        uint128 startPrice;
        uint128 minimumPrice;
    }
    MarketPrice public marketPrice;

    /// @notice Market dynamic variables.
    struct MarketStatus {
        uint128 commitmentsTotal;
        bool finalized;
        bool usePointList;
    }

    MarketStatus public marketStatus;

    /// @notice The token being sold.
    address public auctionToken;
    /// @notice The currency the auction accepts for payment. Can be ETH or token address.
    address public paymentCurrency;
    /// @notice Where the auction funds will get paid.
    address payable public wallet;

    /// @notice The committed amount of accounts.
    mapping(address => uint256) public commitments;
    /// @notice Amount of tokens to claim per address.
    mapping(address => uint256) public claimed;

    /// @notice Event for all auction data. Emmited on deployment.
    event AuctionDeployed(
        address funder,
        address token,
        uint256 totalTokens,
        address paymentCurrency,
        address admin,
        address wallet
    );

    /// @notice Event for updating auction times. Needs to be before auction starts.
    event AuctionTimeUpdated(uint256 startTime, uint256 endTime);
    /// @notice Event for updating auction prices. Needs to be before auction starts.
    event AuctionPriceUpdated(uint256 startPrice, uint256 minimumPrice);
    /// @notice Event for updating auction wallet. Needs to be before auction starts.
    event AuctionWalletUpdated(address wallet);
    /// @notice Event for updating the point list.
    event AuctionPointListUpdated(address pointList, bool enabled);

    /// @notice Event for adding a commitment.
    event AddedCommitment(address addr, uint256 commitment);
    /// @notice Event for token withdrawals.
    event TokensWithdrawn(address token, address to, uint256 amount);

    /// @notice Event for finalization of the auction.
    event AuctionFinalized();
    /// @notice Event for cancellation of the auction.
    event AuctionCancelled();

    constructor() public {
        initAccessControls(msg.sender);
    }

    /**
     * @notice Initializes main contract variables and transfers funds for the auction.
     * @dev Init function.
     * @param _funder The address that funds the token for DutchAuction.
     * @param _token Address of the token being sold.
     * @param _totalTokens The total number of tokens to sell in auction.
     * @param _startTime Auction start time.
     * @param _endTime Auction end time.
     * @param _startPrice Starting price of the auction.
     * @param _minimumPrice The minimum auction price.
     * @param _admin Address that can finalize auction.
     * @param _wallet Address where collected funds will be forwarded to.
     */
    function initAuction(
        address _funder,
        address _token,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _startPrice,
        uint256 _minimumPrice,
        address _admin,
        address payable _wallet
    ) public {
        require(hasAdminRole(msg.sender));
        require(
            _endTime < 10000000000,
            "enter an unix timestamp in seconds, not miliseconds"
        );
        require(
            _startTime >= block.timestamp,
            "start time is before current time"
        );
        require(
            _endTime > _startTime,
            "end time must be older than start price"
        );
        require(_totalTokens > 0, "total tokens must be greater than zero");
        require(
            _startPrice > _minimumPrice,
            "start price must be higher than minimum price"
        );
        require(_minimumPrice > 0, "minimum price must be greater than 0");
        require(_admin != address(0), "admin is the zero address");
        require(_wallet != address(0), "wallet is the zero address");
        require(
            IERC20(_token).decimals() == 18,
            "Token does not have 18 decimals"
        );

        marketInfo.startTime = BoringMath.to64(_startTime);
        marketInfo.endTime = BoringMath.to64(_endTime);
        marketInfo.totalTokens = BoringMath.to128(_totalTokens);

        marketPrice.startPrice = BoringMath.to128(_startPrice);
        marketPrice.minimumPrice = BoringMath.to128(_minimumPrice);

        auctionToken = _token;
        paymentCurrency = ETH_ADDRESS;
        wallet = _wallet;

        _safeTransferFrom(_token, _funder, _totalTokens);

        emit AuctionDeployed(
            _funder,
            _token,
            _totalTokens,
            ETH_ADDRESS,
            _admin,
            _wallet
        );
        emit AuctionTimeUpdated(_startTime, _endTime);
        emit AuctionPriceUpdated(_startPrice, _minimumPrice);
    }

    /**
 Dutch Auction Price Function
 ============================

 Start Price -----
 \
 \
 \
 \ ------------ Clearing Price
 / \ = AmountRaised/TokenSupply
 Token Price -- \
 / \
 -- ----------- Minimum Price
 Amount raised / End Time
 */

    /**
     * @notice Calculates the average price of each token from all commitments.
     * @return Average token price.
     */
    function tokenPrice() public view returns (uint256) {
        return
            uint256(marketStatus.commitmentsTotal).mul(1e18).div(
                uint256(marketInfo.totalTokens)
            );
    }

    /**
     * @notice Returns auction price in any time.
     * @return Fixed start price or minimum price if outside of auction time, otherwise calculated current price.
     */
    function priceFunction() public view returns (uint256) {
        /// @dev Return Auction Price
        if (block.timestamp <= uint256(marketInfo.startTime)) {
            return uint256(marketPrice.startPrice);
        }
        if (block.timestamp >= uint256(marketInfo.endTime)) {
            return uint256(marketPrice.minimumPrice);
        }

        return _currentPrice();
    }

    /**
     * @notice The current clearing price of the Dutch auction.
     * @return The bigger from tokenPrice and priceFunction.
     */
    function clearingPrice() public view returns (uint256) {
        /// @dev If auction successful, return tokenPrice
        uint256 _tokenPrice = tokenPrice();
        uint256 _currentPrice = priceFunction();
        return _tokenPrice > _currentPrice ? _tokenPrice : _currentPrice;
    }

    ///--------------------------------------------------------
    /// Commit to buying tokens!
    ///--------------------------------------------------------

    receive() external payable {
        revertBecauseUserDidNotProvideAgreement();
    }

    /**
     * @dev Attribution to the awesome delta.financial contracts
     */
    function marketParticipationAgreement()
        public
        pure
        returns (string memory)
    {
        return
            "I understand that I'm interacting with a smart contract. I understand that tokens committed are subject to the token issuer and local laws where applicable. I reviewed code of the smart contract and understand it fully. I agree to not hold developers or other people associated with the project liable for any losses or misunderstandings. I have read and agree to the terms and conditions outlined during the sale (hosted on IPFS with CID bafybeige4fkqsgxkhxpdz53aq6lo567w2zoysotnbhvdqkidf4xdapr5bu).";
    }

    /**
     * @dev Not using modifiers is a purposeful choice for code readability.
     */
    function revertBecauseUserDidNotProvideAgreement() internal pure {
        revert(
            "No agreement provided, please review the smart contract before interacting with it"
        );
    }

    event Committed(
        address indexed account,
        uint256 commitment,
        uint256 totalCommitments,
        string referralCodeUsed
    );

    /**
     * @notice Checks the amount of ETH to commit and adds the commitment. Refunds the buyer if commit is too high.
     * @param _beneficiary Auction participant ETH address.
     */
    function commitEth(
        address payable _beneficiary,
        bool readAndAgreedToMarketParticipationAgreement,
        string calldata _referralCode
    ) public payable {
        require(
            paymentCurrency == ETH_ADDRESS,
            "payment currency is not ETH address"
        );
        require(_beneficiary == msg.sender, "can only purchase for yourself");
        if (readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        // Get ETH able to be committed
        uint256 ethToTransfer = calculateCommitment(msg.value);

        /// @notice Accept ETH Payments.
        uint256 ethToRefund = msg.value.sub(ethToTransfer);
        if (ethToTransfer > 0) {
            _addCommitment(_beneficiary, ethToTransfer);
        }
        /// @notice Return any ETH to be refunded.
        if (ethToRefund > 0) {
            _beneficiary.transfer(ethToRefund);
        }

        /// @notice Revert if commitmentsTotal exceeds the balance
        require(
            marketStatus.commitmentsTotal <= address(this).balance,
            "The committed ETH exceeds the balance"
        );

        emit Committed(
            _beneficiary,
            ethToTransfer,
            marketStatus.commitmentsTotal,
            _referralCode
        );
    }

    /**
     * @notice Calculates the pricedrop factor.
     * @return Value calculated from auction start and end price difference divided the auction duration.
     */
    function priceDrop() public view returns (uint256) {
        MarketInfo memory _marketInfo = marketInfo;
        MarketPrice memory _marketPrice = marketPrice;

        uint256 numerator = uint256(
            _marketPrice.startPrice.sub(_marketPrice.minimumPrice)
        );
        uint256 denominator = uint256(
            _marketInfo.endTime.sub(_marketInfo.startTime)
        );
        return numerator / denominator;
    }

    /**
     * @notice How many tokens the user is able to claim.
     * @param _user Auction participant address.
     * @return claimerCommitment User commitments reduced by already claimed tokens.
     */
    function tokensClaimable(
        address _user
    ) public view returns (uint256 claimerCommitment) {
        if (commitments[_user] == 0) return 0;
        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));

        claimerCommitment = commitments[_user]
            .mul(uint256(marketInfo.totalTokens))
            .div(uint256(marketStatus.commitmentsTotal));
        claimerCommitment = claimerCommitment.sub(claimed[_user]);

        if (claimerCommitment > unclaimedTokens) {
            claimerCommitment = unclaimedTokens;
        }
    }

    /**
     * @notice Calculates total amount of tokens committed at current auction price.
     * @return Number of tokens committed.
     */
    function totalTokensCommitted() public view returns (uint256) {
        return
            uint256(marketStatus.commitmentsTotal).mul(1e18).div(
                clearingPrice()
            );
    }

    /**
     * @notice Calculates the amount able to be committed during an auction.
     * @param _commitment Commitment user would like to make.
     * @return committed Amount allowed to commit.
     */
    function calculateCommitment(
        uint256 _commitment
    ) public view returns (uint256 committed) {
        uint256 maxCommitment = uint256(marketInfo.totalTokens)
            .mul(clearingPrice())
            .div(1e18);
        if (
            uint256(marketStatus.commitmentsTotal).add(_commitment) >
            maxCommitment
        ) {
            return maxCommitment.sub(uint256(marketStatus.commitmentsTotal));
        }
        return _commitment;
    }

    /**
     * @notice Checks if the auction is open.
     * @return True if current time is greater than startTime and less than endTime.
     */
    function isOpen() public view returns (bool) {
        return
            block.timestamp >= uint256(marketInfo.startTime) &&
            block.timestamp <= uint256(marketInfo.endTime);
    }

    /**
     * @notice Successful if tokens sold equals totalTokens.
     * @return True if tokenPrice is bigger or equal clearingPrice.
     */
    function auctionSuccessful() public view returns (bool) {
        return tokenPrice() >= clearingPrice();
    }

    /**
     * @notice Checks if the auction has ended.
     * @return True if auction is successful or time has ended.
     */
    function auctionEnded() public view returns (bool) {
        return
            auctionSuccessful() ||
            block.timestamp > uint256(marketInfo.endTime);
    }

    /**
     * @return Returns true if market has been finalized
     */
    function finalized() public view returns (bool) {
        return marketStatus.finalized;
    }

    /**
     * @return Returns true if 7 days have passed since the end of the auction
     */
    function finalizeTimeExpired() public view returns (bool) {
        return uint256(marketInfo.endTime) + 7 days < block.timestamp;
    }

    /**
     * @notice Calculates price during the auction.
     * @return Current auction price.
     */
    function _currentPrice() private view returns (uint256) {
        MarketInfo memory _marketInfo = marketInfo;
        MarketPrice memory _marketPrice = marketPrice;
        uint256 priceDiff = block
            .timestamp
            .sub(uint256(_marketInfo.startTime))
            .mul(
                uint256(_marketPrice.startPrice.sub(_marketPrice.minimumPrice))
            ) / uint256(_marketInfo.endTime.sub(_marketInfo.startTime));
        return uint256(_marketPrice.startPrice).sub(priceDiff);
    }

    /**
     * @notice Updates commitment for this address and total commitment of the auction.
     * @param _addr Bidders address.
     * @param _commitment The amount to commit.
     */
    function _addCommitment(address _addr, uint256 _commitment) internal {
        require(
            block.timestamp >= uint256(marketInfo.startTime) &&
                block.timestamp <= uint256(marketInfo.endTime),
            "outside auction hours"
        );
        MarketStatus storage status = marketStatus;

        uint256 newCommitment = commitments[_addr].add(_commitment);

        commitments[_addr] = newCommitment;
        status.commitmentsTotal = BoringMath.to128(
            uint256(status.commitmentsTotal).add(_commitment)
        );
        emit AddedCommitment(_addr, _commitment);
    }

    //--------------------------------------------------------
    // Finalize Auction
    //--------------------------------------------------------

    /**
     * @notice Cancel Auction
     * @dev Admin can cancel the auction before it starts
     */
    function cancelAuction() public nonReentrant {
        require(hasAdminRole(msg.sender));
        MarketStatus storage status = marketStatus;
        require(!status.finalized, "auction already finalized");
        require(
            uint256(status.commitmentsTotal) == 0,
            "auction already committed"
        );
        _safeTokenPayment(
            auctionToken,
            wallet,
            uint256(marketInfo.totalTokens)
        );
        status.finalized = true;

        emit AuctionCancelled();
    }

    /**
     * @notice Auction finishes successfully above the reserve.
     * @dev Transfer contract funds to initialized wallet.
     */
    function finalize() public nonReentrant {
        require(
            hasAdminRole(msg.sender) ||
                wallet == msg.sender ||
                finalizeTimeExpired(),
            "sender must be an admin"
        );

        require(marketInfo.totalTokens > 0, "Not initialized");

        MarketStatus storage status = marketStatus;

        require(!status.finalized, "auction already finalized");

        status.finalized = true;

        emit AuctionFinalized();
    }

    /// @notice admin can claim proceeds of successful auction to seed liquidity
    function adminClaim() public nonReentrant {
        require(
            hasAdminRole(msg.sender) ||
                wallet == msg.sender ||
                finalizeTimeExpired(),
            "sender must be an admin"
        );

        MarketStatus storage status = marketStatus;

        if (auctionSuccessful()) {
            /// @dev Successful auction
            /// @dev Transfer contributed tokens to wallet.
            _safeTokenPayment(
                paymentCurrency,
                wallet,
                uint256(status.commitmentsTotal)
            );
        } else {
            /// @dev Failed auction
            /// @dev Return auction tokens back to wallet.
            require(
                block.timestamp > uint256(marketInfo.endTime),
                "auction has not finished yet"
            );
            _safeTokenPayment(
                auctionToken,
                wallet,
                uint256(marketInfo.totalTokens)
            );
        }
    }

    /// @notice Withdraws bought tokens, or returns commitment if the sale is unsuccessful.
    function withdraw() public {
        _withdrawTokens(msg.sender);
    }

    function withdrawFor(address payable beneficiary) public {
        _withdrawTokens(beneficiary);
    }

    /**
     * @notice Withdraws bought tokens, or returns commitment if the sale is unsuccessful.
     * @dev Withdraw tokens only after auction ends.
     * @param beneficiary Whose tokens will be withdrawn.
     */
    function _withdrawTokens(
        address payable beneficiary
    ) internal nonReentrant {
        if (auctionSuccessful()) {
            require(marketStatus.finalized, "not finalized");
            /// @dev Successful auction! Transfer claimed tokens.
            uint256 tokensToClaim = tokensClaimable(beneficiary);
            require(tokensToClaim > 0, "No tokens to claim");
            claimed[beneficiary] = claimed[beneficiary].add(tokensToClaim);
            _safeTokenPayment(auctionToken, beneficiary, tokensToClaim);
        } else {
            /// @dev Auction did not meet reserve price.
            /// @dev Return committed funds back to user.
            require(
                block.timestamp > uint256(marketInfo.endTime),
                "auction has not finished yet"
            );
            uint256 fundsCommitted = commitments[beneficiary];
            commitments[beneficiary] = 0; // Stop multiple withdrawals and free some gas
            _safeTokenPayment(paymentCurrency, beneficiary, fundsCommitted);
        }
    }

    function getTotalTokens() external view returns (uint256) {
        return uint256(marketInfo.totalTokens);
    }
}

