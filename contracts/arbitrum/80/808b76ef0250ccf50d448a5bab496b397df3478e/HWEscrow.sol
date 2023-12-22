// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IHWRegistry.sol";
import "./SigUtils.sol";

/// @title HonestWork Escrow Contract
/// @author @takez0_o, @ReddKidd
/// @notice Escrow contract for HonestWork
/// @dev Facilitates deals between creators and recruiters
contract HWEscrow is Ownable, SigUtils {
    enum Status {
        OfferInitiated,
        JobCompleted,
        JobCancelled
    }
    struct Deal {
        address recruiter;
        address creator;
        address paymentToken;
        uint256 totalPayment;
        uint256 hwProfit;
        uint256 claimedAmount;
        uint256 claimableAmount;
        uint256 jobId;
        Status status;
        uint128[] recruiterRating;
        uint128[] creatorRating;
    }

    uint128 immutable PRECISION = 1e2;
    uint128 immutable RATING_UPPER = 11;
    uint128 immutable RATING_LOWER = 0;

    IHWRegistry public registry;
    uint64 public extraPaymentLimit;
    uint128 public successFee;
    bool public nativePaymentAllowed;
    uint256 public profits;

    mapping(uint256 => uint256) public additionalPaymentLimit;
    Deal[] public deals;

    constructor(address _registry, uint128 _fee) Ownable() {
        successFee = _fee;
        registry = IHWRegistry(_registry);
    }

    //-----------------//
    //  admin methods  //
    //-----------------//

    /**
     * @dev value is expressed as a percentage.
     */
    function changeSuccessFee(uint128 _fee) external onlyOwner {
        require(_fee <= 10, "Fee cannot be more than 10%");
        successFee = _fee;
        emit FeeChanged(_fee);
    }

    function changeRegistry(IHWRegistry _registry) external onlyOwner {
        registry = _registry;
    }

    function claimProfit(uint256 _dealId, address _feeCollector)
        external
        onlyOwner
    {
        uint256 profit = deals[_dealId].hwProfit;

        IERC20(deals[_dealId].paymentToken).transfer(_feeCollector, profit);

        profits += profit;
        deals[_dealId].hwProfit = 0;
        emit FeeClaimed(_dealId, deals[_dealId].hwProfit);
    }

    function claimProfits(address _feeCollector) external onlyOwner {
        for (uint256 i = 0; i < deals.length; i++) {
            uint256 profit = deals[i].hwProfit;
            if (profit > 0) {
                IERC20(deals[i].paymentToken).transfer(_feeCollector, profit);
                deals[i].hwProfit = 0;
            }
        }
        emit TotalFeeClaimed(_feeCollector);
    }

    function changeExtraPaymentLimit(uint64 _limit) external onlyOwner {
        extraPaymentLimit = _limit;
        emit ExtraLimitChanged(_limit);
    }

    //--------------------//
    //  mutative methods  //
    //--------------------//

    function createDealSignature(
        address _recruiter,
        address _creator,
        address _paymentToken,
        uint256 _totalPayment,
        uint256 _downPayment,
        uint256 _recruiterNFTId,
        uint256 _jobId,
        bytes memory _signature
    ) external returns (uint256) {
        (bytes32 r, bytes32 s, uint8 v) = SigUtils.splitSignature(_signature);
        createDeal(
            _recruiter,
            _creator,
            _paymentToken,
            _totalPayment,
            _downPayment,
            _recruiterNFTId,
            _jobId,
            v,
            r,
            s
        );
    }

    function createDeal(
        address _recruiter,
        address _creator,
        address _paymentToken,
        uint256 _totalPayment,
        uint256 _downPayment,
        uint256 _recruiterNFTId,
        uint256 _jobId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (uint256) {
        require(_recruiter != address(0), "recruiter address cannot be 0");
        require(_creator != address(0), "creator address cannot be 0");
        require(_totalPayment > 0, "total payment cannot be 0");
        require(
            _downPayment <= _totalPayment,
            "down payment cannot be greater than total payment"
        );
        require(
            _creator != _recruiter,
            "creator and recruiter cannot be the same address"
        );
        require(
            registry.isAllowedAmount(_paymentToken, _totalPayment),
            "wrong amount for payment token"
        );

        bytes32 signedMessage = getEthSignedMessageHash(
            getMessageHash(
                _recruiter,
                _creator,
                _paymentToken,
                _totalPayment,
                _downPayment,
                _jobId
            )
        );
        require(
            recoverSigner(signedMessage, v, r, s) == _creator,
            "invalid signature, creator needs to sign the deal paramers first"
        );

        Deal memory deal = Deal(
            _recruiter,
            _creator,
            _paymentToken,
            _totalPayment,
            0,
            0,
            0,
            _jobId,
            Status.OfferInitiated,
            new uint128[](0),
            new uint128[](0)
        );
        deals.push(deal);
        IERC20(_paymentToken).transferFrom(
            msg.sender,
            address(this),
            (_totalPayment * (PRECISION + successFee)) / PRECISION
        );
        emit OfferCreated(
            _recruiter,
            _creator,
            _totalPayment,
            _paymentToken,
            _jobId
        );

        if (_downPayment != 0) {
            deals[deals.length - 1].claimableAmount += _downPayment;
            emit PaymentUnlocked(
                deals.length - 1,
                deals[deals.length - 1].recruiter,
                _downPayment
            );

            registry.setNFTGrossRevenue(_recruiterNFTId, _downPayment);
            emit GrossRevenueUpdated(_recruiterNFTId, _downPayment);
        }
        return deals.length - 1;
    }

    function unlockPayment(
        uint256 _dealId,
        uint256 _paymentAmount,
        uint128 _rating,
        uint256 _recruiterNFT
    ) public {
        Deal memory deal = deals[_dealId];
        require(
            deal.status == Status.OfferInitiated,
            "deal is either completed or cancelled"
        );
        require(
            _rating > RATING_LOWER && _rating < RATING_UPPER,
            "rating must be between 1 and 10"
        );
        require(
            deal.recruiter == msg.sender,
            "only recruiter can unlock payments"
        );
        require(
            deal.totalPayment >=
                deal.claimableAmount + deal.claimedAmount + _paymentAmount,
            "can not go above total payment, "
        );

        deals[_dealId].claimableAmount += _paymentAmount;
        emit PaymentUnlocked(_dealId, deal.recruiter, _paymentAmount);

        if (_rating != 0) {
            deals[_dealId].creatorRating.push(_rating * PRECISION);
        }
        registry.setNFTGrossRevenue(_recruiterNFT, _paymentAmount);
        emit GrossRevenueUpdated(_recruiterNFT, _paymentAmount);
    }

    function withdrawPayment(uint256 _dealId) external {
        Deal memory deal = deals[_dealId];
        require(deal.status == Status.OfferInitiated, "job should be active");
        require(
            deal.recruiter == msg.sender,
            "only recruiter can withdraw payments"
        );

        uint256 untouchables = deal.claimedAmount + deal.hwProfit;
        IERC20(deal.paymentToken).transfer(
            msg.sender,
            (((deal.totalPayment * (PRECISION + successFee)) / PRECISION) -
                untouchables)
        );
        deals[_dealId].status = Status.JobCancelled;
        emit PaymentWithdrawn(_dealId, deal.status);
    }

    function claimPayment(
        uint256 _dealId,
        uint256 _claimAmount,
        uint128 _rating,
        uint256 _creatorNFT
    ) external {
        Deal memory deal = deals[_dealId];
        require(
            deal.status == Status.OfferInitiated,
            "deal is either completed or cancelled"
        );
        require(
            _rating > RATING_LOWER && _rating < RATING_UPPER,
            "rating must be between 0 and 10"
        );
        require(
            deal.creator == msg.sender,
            "only creator can receive payments"
        );
        require(
            deal.claimableAmount >= _claimAmount,
            "desired payment is not available yet"
        );

        deal.claimedAmount += _claimAmount;
        deal.claimableAmount -= _claimAmount;
        deal.hwProfit += (_claimAmount * successFee) / PRECISION;

        IERC20(deal.paymentToken).transfer(
            msg.sender,
            ((_claimAmount * (PRECISION - successFee)) / PRECISION)
        );

        registry.setNFTGrossRevenue(_creatorNFT, _claimAmount);
        emit GrossRevenueUpdated(_creatorNFT, _claimAmount);

        if (deal.claimedAmount >= deal.totalPayment) {
            deal.status = Status.JobCompleted;
        }
        deals[_dealId] = deal;
        deals[_dealId].recruiterRating.push(_rating * PRECISION);
        emit PaymentClaimed(_dealId, deal.creator, _claimAmount);
    }

    //----------------//
    //  view methods  //
    //----------------//

    function getDeal(uint256 _dealId) public view returns (Deal memory) {
        return deals[_dealId];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAvgCreatorRating(uint256 _dealId)
        public
        view
        returns (uint256)
    {
        uint256 sum;
        for (uint256 i = 0; i < deals[_dealId].creatorRating.length; i++) {
            sum += deals[_dealId].creatorRating[i];
        }
        return (sum / deals[_dealId].creatorRating.length);
    }

    function getAvgRecruiterRating(uint256 _dealId)
        public
        view
        returns (uint256)
    {
        uint256 sum;
        for (uint256 i = 0; i < deals[_dealId].recruiterRating.length; i++) {
            sum += deals[_dealId].recruiterRating[i];
        }
        return (sum / deals[_dealId].recruiterRating.length);
    }

    function getAggregatedRating(address _address)
        public
        view
        returns (uint256)
    {
        uint256 gross_amount = 0;
        uint256 gross_rating = 0;
        uint256[] memory deal_ids = getDeals(_address);
        if (deal_ids.length > 0) {
            for (uint256 i = 0; i < deal_ids.length; i++) {
                Deal memory deal = getDeal(deal_ids[i]);
                if (
                    _address == deal.recruiter &&
                    deal.recruiterRating.length != 0
                ) {
                    gross_rating +=
                        getAvgRecruiterRating(deal_ids[i]) *
                        deal.claimedAmount;
                    gross_amount += deal.claimedAmount;
                } else if (
                    _address == deal.creator && deal.creatorRating.length != 0
                ) {
                    gross_rating +=
                        getAvgCreatorRating(deal_ids[i]) *
                        (deal.claimedAmount + deal.claimableAmount);
                    gross_amount += (deal.claimedAmount + deal.claimableAmount);
                }
            }
        }
        if (gross_amount == 0) {
            return 0;
        } else {
            return gross_rating / gross_amount;
        }
    }

    function getProfits() external view returns (uint256) {
        uint256 totalSuccessFee;
        for (uint256 i = 0; i < deals.length; i++) {
            totalSuccessFee += deals[i].hwProfit;
        }
        return totalSuccessFee;
    }

    function getDeals(address _address) public view returns (uint256[] memory) {
        uint256[] memory user_deals = new uint256[](countDeals(_address));
        uint256 c = 0;
        for (uint256 i = 0; i < deals.length; i++) {
            if (
                deals[i].creator == _address || deals[i].recruiter == _address
            ) {
                user_deals[c] = i;
                c++;
            }
        }
        return user_deals;
    }

    function getDeals() public view returns (Deal[] memory) {
        return deals;
    }

    function countDeals(address _address) internal view returns (uint256) {
        uint256 count;
        for (uint256 i = 0; i < deals.length; i++) {
            if (
                deals[i].creator == _address || deals[i].recruiter == _address
            ) {
                count++;
            }
        }
        return count;
    }

    event OfferCreated(
        address indexed _recruiter,
        address indexed _creator,
        uint256 indexed _totalPayment,
        address _paymentToken,
        uint256 _jobId
    );
    event PaymentUnlocked(
        uint256 _dealId,
        address indexed _recruiter,
        uint256 indexed _unlockedAmount
    );
    event PaymentClaimed(
        uint256 indexed _dealId,
        address indexed _creator,
        uint256 indexed _paymentReceived
    );
    event AdditionalPayment(
        uint256 indexed _dealId,
        address indexed _recruiter,
        uint256 indexed _payment
    );
    event PaymentWithdrawn(uint256 indexed _dealId, Status status);
    event FeeChanged(uint256 _newSuccessFee);
    event FeeClaimed(uint256 indexed _dealId, uint256 _amount);
    event ExtraLimitChanged(uint256 _newPaymentLimit);
    event TotalFeeClaimed(address _collector);
    event GrossRevenueUpdated(uint256 indexed _tokenId, uint256 _grossRevenue);
}

