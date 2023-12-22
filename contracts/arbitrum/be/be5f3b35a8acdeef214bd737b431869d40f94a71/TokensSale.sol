// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AccessControlEnumerable.sol";
import "./EnumerableSet.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IERC20WithMetadata.sol";
import "./ITokensVesting.sol";

contract TokensSale is ReentrancyGuard, AccessControlEnumerable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct BatchSaleInfo {
        address recipent;
        address paymentToken;
        uint256 price; // wei per token
        uint256 minAmount; // payment token in wei
        uint256 hardCap; // wei
        uint256 start;
        uint256 end;
        uint256 releaseTimestamp;
        uint256 tgeCliff;
        uint256 totalPaymentAmount; // wei
    }

    enum BatchStatus {
        INACTIVE,
        ACTIVE,
        COMPLETED
    }

    struct VestingPlan {
        uint256 percentageDecimals;
        uint256 tgePercentage;
        uint256 basis;
        uint256 cliff;
        uint256 duration;
        ITokensVesting.Participant participant;
    }

    struct UserInfo {
        uint256 paymentAmount;
        bool harvested;
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    ITokensVesting public tokensVesting;
    EnumerableSet.UintSet private _batches;
    mapping(uint256 => BatchSaleInfo) public batchSaleInfos;
    mapping(uint256 => VestingPlan) public vestingPlans;
    mapping(uint256 => BatchStatus) public batchStatus;
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;

    mapping(uint256 => EnumerableSet.AddressSet) private _users;
    mapping(uint256 => EnumerableSet.AddressSet) private _whitelistAddresses;
    EnumerableSet.UintSet private _supportedParticipants;

    event BatchSaleUpdated(
        uint256 indexed batchNumber,
        address recipient,
        address paymentToken,
        uint256 price,
        uint256 minAmount,
        uint256 hardCap,
        uint256 start,
        uint256 end,
        uint256 releaseTimestamp,
        uint256 tgeCliff
    );
    event BatchStatusUpdated(uint256 indexed batchNumber, uint8 status);
    event VestingPlanUpdated(
        uint256 indexed batchNumber,
        uint256 percentageDecimals,
        uint256 tgePercentage,
        uint256 basis,
        uint256 cliff,
        uint256 duration,
        ITokensVesting.Participant participant
    );
    event WhitelistAddressAdded(
        uint256 indexed batchNumber,
        address indexed buyer
    );
    event WhitelistAddressRemoved(
        uint256 indexed batchNumber,
        address indexed buyer
    );
    event TokensPurchased(
        address indexed buyer,
        uint256 paymentAmount,
        uint256 totalReceivedAmount
    );
    event TokensVestingUpdated(address tokensVesting);
    event Deposit(address user, uint256 amount);

    modifier batchExisted(uint256 batchNumber_) {
        require(
            _batches.contains(batchNumber_),
            "TokensSale: batchNumber_ does not exist"
        );
        _;
    }

    modifier onlySupportedParticipant(ITokensVesting.Participant participant_) {
        require(
            _supportedParticipants.contains(uint256(participant_)),
            "TokensSale: unsupported participant"
        );
        _;
    }

    modifier batchNotCompleted(uint256 batchNumber_) {
        require(
            batchStatus[batchNumber_] != BatchStatus.COMPLETED,
            "TokensSale: Batch completed"
        );
        _;
    }

    modifier whenHarvestable(uint256 batchNumber_) {
        require(harvestable(batchNumber_, msg.sender));
        _;
    }

    constructor(address tokenVestingAddress_) {
        _updateTokensVesting(tokenVestingAddress_);
        _supportedParticipants.add(
            uint256(ITokensVesting.Participant.PublicSale)
        );

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    function updateTokensVesting(
        address tokensVestingAddress_
    ) external onlyRole(OPERATOR_ROLE) {
        _updateTokensVesting(tokensVestingAddress_);
    }

    function addBatchSale(
        uint256 batchNumber_,
        address recipient_,
        address paymentToken_,
        uint256 price_,
        uint256 minAmount_,
        uint256 hardCap_,
        uint256 start_,
        uint256 end_,
        uint256 releaseTimestamp_,
        uint256 tgeCliff_
    ) external onlyRole(OPERATOR_ROLE) {
        require(batchNumber_ > 0, "TokensSale: batchNumber_ is 0");
        require(
            recipient_ != address(0),
            "TokensSale: recipient_ is zero address"
        );
        require(
            paymentToken_ != address(0),
            "TokensSale: paymentToken_ is zero address"
        );
        require(price_ > 0, "TokensSale: price_ is 0");
        require(
            _batches.add(batchNumber_),
            "TokensSale: batchNumber_ already existed"
        );

        _updateBatchSaleInfo(
            batchNumber_,
            recipient_,
            paymentToken_,
            price_,
            minAmount_,
            hardCap_,
            start_,
            end_,
            releaseTimestamp_,
            tgeCliff_
        );
    }

    function updateBatchSaleInfo(
        uint256 batchNumber_,
        address recipient_,
        address paymentToken_,
        uint256 price_,
        uint256 minAmount_,
        uint256 hardCap_,
        uint256 start_,
        uint256 end_,
        uint256 releaseTimestamp_,
        uint256 tgeCliff_
    )
        external
        onlyRole(OPERATOR_ROLE)
        batchExisted(batchNumber_)
        batchNotCompleted(batchNumber_)
    {
        require(
            recipient_ != address(0),
            "TokensSale: recipient_ is zero address"
        );
        require(
            paymentToken_ != address(0),
            "TokensSale: paymentToken_ is zero address"
        );
        require(price_ > 0, "TokensSale: price_ is 0");

        _updateBatchSaleInfo(
            batchNumber_,
            recipient_,
            paymentToken_,
            price_,
            minAmount_,
            hardCap_,
            start_,
            end_,
            releaseTimestamp_,
            tgeCliff_
        );
    }

    function updateVestingPlan(
        uint256 batchNumber_,
        uint256 percentageDecimals_,
        uint256 tgePercentage_,
        uint256 basis_,
        uint256 cliff_,
        uint256 duration_,
        ITokensVesting.Participant participant_
    )
        external
        onlyRole(OPERATOR_ROLE)
        batchExisted(batchNumber_)
        batchNotCompleted(batchNumber_)
        onlySupportedParticipant(participant_)
    {
        require(
            tgePercentage_ <= 100 * 10 ** percentageDecimals_,
            "TokensSale: bad args"
        );
        VestingPlan storage _plan = vestingPlans[batchNumber_];
        _plan.percentageDecimals = percentageDecimals_;
        _plan.tgePercentage = tgePercentage_;
        _plan.basis = basis_;
        _plan.cliff = cliff_;
        _plan.duration = duration_;
        _plan.participant = participant_;

        emit VestingPlanUpdated(
            batchNumber_,
            percentageDecimals_,
            tgePercentage_,
            basis_,
            cliff_,
            duration_,
            participant_
        );
    }

    function updateBatchStatus(
        uint256 batchNumber_,
        uint8 status_
    )
        external
        onlyRole(OPERATOR_ROLE)
        batchExisted(batchNumber_)
        batchNotCompleted(batchNumber_)
    {
        require(
            BatchStatus(status_) != BatchStatus.COMPLETED,
            "TokensSale: cannot change batch to completed"
        );
        if (batchStatus[batchNumber_] != BatchStatus(status_)) {
            batchStatus[batchNumber_] = BatchStatus(status_);
            emit BatchStatusUpdated(batchNumber_, status_);
        } else {
            revert("TokensSale: status_ is same as before");
        }
    }

    function addWhitelistAddressToBatch(
        uint256 batchNumber_,
        address whitelistAddress_
    ) external onlyRole(OPERATOR_ROLE) batchExisted(batchNumber_) {
        require(
            _whitelistAddresses[batchNumber_].add(whitelistAddress_),
            "TokensSale: address is already in whitelist"
        );
    }

    function addWhitelistAddressesToBatch(
        uint256 batchNumber_,
        address[] calldata whitelistAddresses_
    ) external onlyRole(OPERATOR_ROLE) batchExisted(batchNumber_) {
        require(
            whitelistAddresses_.length > 0,
            "TokensSale: whitelistAddresses_ is empty"
        );
        for (
            uint256 _index = 0;
            _index < whitelistAddresses_.length;
            _index++
        ) {
            require(
                _whitelistAddresses[batchNumber_].add(
                    whitelistAddresses_[_index]
                ),
                "TokensSale: address is already in whitelist"
            );
            emit WhitelistAddressAdded(
                batchNumber_,
                whitelistAddresses_[_index]
            );
        }
    }

    function removeWhitelistAddressOutBatch(
        uint256 batchNumber_,
        address whitelistAddress_
    ) external onlyRole(OPERATOR_ROLE) batchExisted(batchNumber_) {
        require(
            _whitelistAddresses[batchNumber_].remove(whitelistAddress_),
            "TokensSale: address is not in whitelist"
        );
    }

    function removeWhitelistAddressesOutBatch(
        uint256 batchNumber_,
        address[] calldata whitelistAddresses_
    ) external onlyRole(OPERATOR_ROLE) batchExisted(batchNumber_) {
        require(
            whitelistAddresses_.length > 0,
            "TokensSale: whitelistAddresses_ is empty"
        );
        for (uint256 index = 0; index < whitelistAddresses_.length; index++) {
            require(
                _whitelistAddresses[batchNumber_].remove(
                    whitelistAddresses_[index]
                ),
                "TokensSale: address is not in whitelist or already removed"
            );
            emit WhitelistAddressRemoved(
                batchNumber_,
                whitelistAddresses_[index]
            );
        }
    }

    function whitelistAddresses(
        uint256 batchNumber_
    ) public view returns (address[] memory) {
        return _whitelistAddresses[batchNumber_].values();
    }

    function addParticipant(
        ITokensVesting.Participant participant_
    ) external onlyRole(OPERATOR_ROLE) {
        require(
            _supportedParticipants.add(uint256(participant_)),
            "TokensSale: already supported"
        );
    }

    function removeParticipant(
        ITokensVesting.Participant participant_
    ) external onlyRole(OPERATOR_ROLE) {
        require(
            _supportedParticipants.remove(uint256(participant_)),
            "TokensSale: participant is not supported or already removed"
        );
    }

    function supportedParticipants() public view returns (uint256[] memory) {
        return _supportedParticipants.values();
    }

    function batches() public view returns (uint256[] memory) {
        return _batches.values();
    }

    function deposit(
        uint256 batchNumber_,
        uint256 paymentAmount_
    ) external batchExisted(batchNumber_) {
        if (_whitelistAddresses[batchNumber_].length() > 0) {
            require(
                _whitelistAddresses[batchNumber_].contains(msg.sender),
                "TokensSale: sender is not in whitelist"
            );
        }
        require(
            batchStatus[batchNumber_] == BatchStatus.ACTIVE,
            "TokensSale: the sale is inactive"
        );

        BatchSaleInfo storage batchInfo = batchSaleInfos[batchNumber_];
        require(
            block.timestamp >= batchInfo.start,
            "TokensSale: the sale does not start"
        );
        require(
            block.timestamp < batchInfo.end || batchInfo.end == 0,
            "TokensSale: the sale is ended"
        );

        require(
            paymentAmount_ >= batchInfo.minAmount,
            "TokensSale: amount is too low"
        );

        IERC20(batchInfo.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            paymentAmount_
        );

        batchInfo.totalPaymentAmount += paymentAmount_;

        _users[batchNumber_].add(msg.sender);
        UserInfo storage userinfo = userInfos[batchNumber_][msg.sender];
        userinfo.paymentAmount += paymentAmount_;
        userinfo.harvested = false;

        emit Deposit(msg.sender, paymentAmount_);
    }

    function finalWithdrawRaisingToken(
        uint256 batchNumber_
    )
        public
        onlyRole(OPERATOR_ROLE)
        batchExisted(batchNumber_)
        batchNotCompleted(batchNumber_)
    {
        BatchSaleInfo storage batchInfo = batchSaleInfos[batchNumber_];
        require(
            block.timestamp >= batchInfo.end,
            "TokensSale: the sale is not ended"
        );
        batchStatus[batchNumber_] = BatchStatus.COMPLETED;
        uint256 totalAmountRaised = batchInfo.totalPaymentAmount <
            batchInfo.hardCap
            ? batchInfo.totalPaymentAmount
            : batchInfo.hardCap;

        if (totalAmountRaised > 0) {
            IERC20(batchInfo.paymentToken).safeTransfer(
                batchInfo.recipent,
                totalAmountRaised
            );
        }
    }

    function harvest(
        uint256 batchNumber_
    )
        external
        batchExisted(batchNumber_)
        whenHarvestable(batchNumber_)
        nonReentrant
    {
        (
            uint256 offeringAmount,
            uint256 refundAmount
        ) = getOfferingAndRefundAmount(batchNumber_, msg.sender);

        BatchSaleInfo storage batchInfo = batchSaleInfos[batchNumber_];
        UserInfo storage userInfo = userInfos[batchNumber_][msg.sender];
        userInfo.harvested = true;

        if (refundAmount > 0) {
            IERC20(batchInfo.paymentToken).safeTransfer(
                msg.sender,
                refundAmount
            );
        }

        IERC20WithMetadata tokenForSale = IERC20WithMetadata(
            address(tokensVesting.token())
        );
        uint256 totalTokenAmount = (offeringAmount *
            10 ** tokenForSale.decimals()) / batchInfo.price;

        uint256 _genesisTimestamp = batchInfo.releaseTimestamp == 0
            ? block.timestamp + batchInfo.tgeCliff
            : batchInfo.releaseTimestamp + batchInfo.tgeCliff;

        uint256[3] memory params;
        params[0] = batchNumber_;
        params[1] = totalTokenAmount;
        params[2] = _genesisTimestamp;
        uint256 index = _addBeneficiary(params, msg.sender);
        uint256 releasableAmount = tokensVesting.releasableAmountAt(index);
        if (releasableAmount > 0) {
            tokensVesting.release(index);
        }
    }

    function joined(
        uint256 batchNumber_,
        address user_
    ) public view returns (bool) {
        return _users[batchNumber_].contains(user_);
    }

    function harvestable(
        uint256 batchNumber_,
        address user_
    ) public view returns (bool) {
        return
            _users[batchNumber_].contains(user_) &&
            !userInfos[batchNumber_][user_].harvested &&
            block.timestamp >= batchSaleInfos[batchNumber_].end;
    }

    function usersCount(uint256 batchNumber_) public view returns (uint256) {
        return _users[batchNumber_].length();
    }

    function users(
        uint256 batchNumber_
    ) public view returns (address[] memory) {
        return _users[batchNumber_].values();
    }

    function getOfferingAndRefundAmount(
        uint256 batchNumber_,
        address user_
    ) public view returns (uint256 offeringAmount, uint256 refundAmount) {
        BatchSaleInfo storage batchInfo = batchSaleInfos[batchNumber_];
        UserInfo storage userInfo = userInfos[batchNumber_][user_];

        if (batchInfo.totalPaymentAmount <= batchInfo.hardCap) {
            offeringAmount = userInfo.paymentAmount;
            refundAmount = 0;
        } else {
            offeringAmount =
                (userInfo.paymentAmount * batchInfo.hardCap) /
                batchInfo.totalPaymentAmount;
            refundAmount = userInfo.paymentAmount - offeringAmount;
        }
    }

    function _updateTokensVesting(address tokensVestingAddress_) private {
        require(
            tokensVestingAddress_ != address(0),
            "TokensSale: tokensVestingAddress_ is zero address"
        );
        tokensVesting = ITokensVesting(tokensVestingAddress_);
        emit TokensVestingUpdated(tokensVestingAddress_);
    }

    function _updateBatchSaleInfo(
        uint256 batchNumber_,
        address recipient_,
        address paymentToken_,
        uint256 price_,
        uint256 minAmount_,
        uint256 hardCap_,
        uint256 start_,
        uint256 end_,
        uint256 releaseTimestamp_,
        uint256 tgeCliff_
    ) private {
        BatchSaleInfo storage _info = batchSaleInfos[batchNumber_];
        _info.recipent = recipient_;
        _info.paymentToken = paymentToken_;
        _info.price = price_;
        _info.minAmount = minAmount_;
        _info.hardCap = hardCap_;
        _info.start = start_;
        _info.end = end_;
        _info.releaseTimestamp = releaseTimestamp_;
        _info.tgeCliff = tgeCliff_;

        emit BatchSaleUpdated(
            batchNumber_,
            recipient_,
            paymentToken_,
            price_,
            minAmount_,
            hardCap_,
            start_,
            end_,
            releaseTimestamp_,
            tgeCliff_
        );
    }

    /**
     * call stack limit
     * param 0: batchNumber
     * param 1: totalAmount
     * param 2: genesisTimestamp
     */
    function _addBeneficiary(
        uint256[3] memory params_,
        address recipent_
    ) private returns (uint256) {
        ITokensVesting.VestingInfo memory info = ITokensVesting.VestingInfo({
            beneficiary: recipent_,
            role: bytes32(0),
            genesisTimestamp: params_[2],
            totalAmount: params_[1],
            tgeAmount: (vestingPlans[params_[0]].tgePercentage * params_[1]) /
                10 ** (vestingPlans[params_[0]].percentageDecimals + 2),
            basis: vestingPlans[params_[0]].basis,
            cliff: vestingPlans[params_[0]].cliff,
            duration: vestingPlans[params_[0]].duration,
            participant: vestingPlans[params_[0]].participant,
            releasedAmount: 0
        });

        return tokensVesting.addBeneficiary(info);
    }
}

