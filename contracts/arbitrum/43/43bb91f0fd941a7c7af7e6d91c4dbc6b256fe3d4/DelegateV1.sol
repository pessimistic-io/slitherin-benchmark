// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IDelegateV1.sol";
import "./LockHolder.sol";

contract DelegateV1 is 
    IDelegateV1,
    Initializable, 
    UUPSUpgradeable, 
    ERC721HolderUpgradeable,
    OwnableUpgradeable 
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    uint256 public constant INITIAL_LOCK_VALUE = 10_000_000 ether;
    uint256 public constant LOCK_DURATION = 63_072_000; // 2 years

    // V1
    IVotingEscrow public votingEscrow;
    IVoter public voter;
    IRewardsDistributor public rewardsDistributor;
    IERC20Upgradeable public horiza;

    EnumerableSetUpgradeable.AddressSet private _partners;

    mapping(address => uint256) public tokenIdByPartner;
    mapping(address => address) public lockHolderByPartner;

    /// @inheritdoc IDelegateV1
    function initialize(
        IVotingEscrow votingEscrow_, 
        IVoter voter_,
        IRewardsDistributor rewardsDistributor_,
        IERC20Upgradeable horiza_
    ) 
        external 
        initializer 
    {
        __UUPSUpgradeable_init();
        __ERC721Holder_init();
        __Ownable_init();
        votingEscrow = votingEscrow_;
        voter = voter_;
        rewardsDistributor = rewardsDistributor_;
        horiza = horiza_;
        horiza_.safeTransferFrom(msg.sender, address(this), INITIAL_LOCK_VALUE);
        horiza_.safeApprove(address(votingEscrow_), type(uint256).max);
        votingEscrow_.create_lock(INITIAL_LOCK_VALUE, LOCK_DURATION);
        tokenIdByPartner[msg.sender] = votingEscrow_.tokenOfOwnerByIndex(address(this), 0);
        lockHolderByPartner[msg.sender] = address(this);
        _partners.add(msg.sender);
    }

    /// @inheritdoc IDelegateV1
    function removePartner(address partner_) external onlyOwner {
        if (!_partners.contains(partner_) || partner_ == msg.sender) {
            revert InvalidPartnerAddress();
        }
        uint256 tokenId = tokenIdByPartner[partner_];
        IVotingEscrow m_votingEscrow = votingEscrow;
        if (m_votingEscrow.voted(tokenId)) {
            voter.reset(tokenId);
        }
        m_votingEscrow.merge(tokenId, tokenIdByPartner[msg.sender]);
        delete tokenIdByPartner[partner_];
        delete lockHolderByPartner[partner_];
        _partners.remove(partner_);
        emit PartnerRemoved(partner_);
    }

    /// @inheritdoc IDelegateV1
    function splitOwnerTokenId(address[] calldata partners_, uint256[] calldata amounts_) external onlyOwner {
        if (partners_.length != amounts_.length) {
            revert InvalidArrayLength();
        }
        uint256 sum;
        for (uint256 i = 0; i < partners_.length; ) {
            if (_partners.contains(partners_[i])) {
                revert InvalidPartnerAddress();
            }
            unchecked {
                sum += amounts_[i];
                i++;
            }
        }
        uint256 ownerTokenId = tokenIdByPartner[msg.sender];
        rewardsDistributor.claim(ownerTokenId);
        IVotingEscrow m_votingEscrow = votingEscrow;
        uint256 locked = uint256(int256(m_votingEscrow.locked(ownerTokenId).amount));
        if (sum >= locked || sum == 0) {
            revert InvalidSum();
        }
        uint256[] memory amounts = new uint256[](partners_.length + 1);
        for (uint256 i = 0; i < amounts_.length; ) {
            amounts[i] = amounts_[i]; 
            unchecked {
                i++;
            }
        }
        unchecked {
            amounts[partners_.length] = locked - sum;
        }
        m_votingEscrow.split(amounts, ownerTokenId);
        uint256[] memory tokenIds = new uint256[](partners_.length);
        for (uint256 i = 0; i < partners_.length; ) {
            tokenIds[i] = m_votingEscrow.tokenOfOwnerByIndex(address(this), i);
            unchecked {
                i++;
            }
        }
        for (uint256 i = 0; i < partners_.length; ) {
            tokenIdByPartner[partners_[i]] = tokenIds[i];
            address lockHolder = address(new LockHolder(partners_[i], m_votingEscrow));
            lockHolderByPartner[partners_[i]] = lockHolder;
            m_votingEscrow.safeTransferFrom(address(this), lockHolder, tokenIds[i]);
            _partners.add(partners_[i]);
            unchecked {
                i++;
            }
        }
        tokenIdByPartner[msg.sender] = m_votingEscrow.tokenOfOwnerByIndex(address(this), 0);
        emit Split(partners_, amounts_);
    }

    /// @inheritdoc IDelegateV1
    function createLockFor(address partner_, uint256 amount_) external onlyOwner {
        if (_partners.contains(partner_)) {
            revert InvalidPartnerAddress();
        }
        if (amount_ == 0) {
            revert InvalidSum();
        }
        horiza.safeTransferFrom(msg.sender, address(this), amount_);
        IVotingEscrow m_votingEscrow = votingEscrow;
        m_votingEscrow.create_lock(amount_, LOCK_DURATION);
        uint256 tokenId = m_votingEscrow.tokenOfOwnerByIndex(address(this), 1);
        tokenIdByPartner[partner_] = tokenId;
        address lockHolder = address(new LockHolder(partner_, m_votingEscrow));
        lockHolderByPartner[partner_] = lockHolder;
        m_votingEscrow.safeTransferFrom(address(this), lockHolder, tokenId);
        _partners.add(partner_);
        emit PartnerCreated(partner_, amount_);
    }

    /// @inheritdoc IDelegateV1
    function extendFor(address[] calldata partners_) external onlyOwner {
        IVotingEscrow m_votingEscrow = votingEscrow;
        for (uint256 i = 0; i < partners_.length; ) {
            if (!_partners.contains(partners_[i])) {
                revert InvalidPartnerAddress();
            }
            m_votingEscrow.increase_unlock_time(tokenIdByPartner[partners_[i]], LOCK_DURATION);
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IDelegateV1
    function increaseFor(address[] calldata partners_, uint256[] calldata amounts_) external onlyOwner {
        if (partners_.length != amounts_.length) {
            revert InvalidArrayLength();
        }
        uint256 sum;
        for (uint256 i = 0; i < amounts_.length; ) {
            unchecked {
                sum += amounts_[i];
                i++;
            }
        }
        horiza.safeTransferFrom(msg.sender, address(this), sum);
        IVotingEscrow m_votingEscrow = votingEscrow;
        for (uint256 i = 0; i < partners_.length; ) {
            if (!_partners.contains(partners_[i])) {
                revert InvalidPartnerAddress();
            }
            m_votingEscrow.increase_amount(tokenIdByPartner[partners_[i]], amounts_[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IDelegateV1
    function extend() external {
        if (!_partners.contains(msg.sender)) {
            revert InvalidCallee();
        }
        votingEscrow.increase_unlock_time(tokenIdByPartner[msg.sender], LOCK_DURATION);
    }

    /// @inheritdoc IDelegateV1
    function vote(address[] calldata pools_, uint256[] calldata weights_) external {
        if (!_partners.contains(msg.sender) || msg.sender == owner()) {
            revert InvalidCallee();
        }
        if (pools_.length != weights_.length) {
            revert InvalidArrayLength();
        }
        voter.vote(tokenIdByPartner[msg.sender], pools_, weights_);
    }

    /// @inheritdoc IDelegateV1
    function reset() external {
        if (!_partners.contains(msg.sender) || msg.sender == owner()) {
            revert InvalidCallee();
        }
        voter.reset(tokenIdByPartner[msg.sender]);
    }

    /// @inheritdoc IDelegateV1
    function poke() external {
        if (!_partners.contains(msg.sender) || msg.sender == owner()) {
            revert InvalidCallee();
        }
        voter.poke(tokenIdByPartner[msg.sender]);
    }

    /// @inheritdoc IDelegateV1
    function claimBribes(address[] calldata bribes_, address[][] calldata bribeTokens_) external {
        if (!_partners.contains(msg.sender) || msg.sender == owner()) {
            revert InvalidCallee();
        }
        if (bribes_.length != bribeTokens_.length) {
            revert InvalidArrayLength();
        }
        voter.claimBribes(bribes_, bribeTokens_, tokenIdByPartner[msg.sender]);
        ILockHolder(lockHolderByPartner[msg.sender]).sendRewards(bribeTokens_);
    }

    /// @inheritdoc IDelegateV1
    function claimFees(address[] calldata fees_, address[][] calldata feeTokens_) external {
        if (!_partners.contains(msg.sender) || msg.sender == owner()) {
            revert InvalidCallee();
        }
        if (fees_.length != feeTokens_.length) {
            revert InvalidArrayLength();
        }
        voter.claimFees(fees_, feeTokens_, tokenIdByPartner[msg.sender]);
        ILockHolder(lockHolderByPartner[msg.sender]).sendRewards(feeTokens_);
    }

    /// @inheritdoc IDelegateV1
    function claimRebaseRewards() external {
        if (!_partners.contains(msg.sender)) {
            revert InvalidCallee();
        }
        rewardsDistributor.claim(tokenIdByPartner[msg.sender]);
    }

    /// @inheritdoc IDelegateV1
    function numberOfPartners() external view returns (uint256) {
        return _partners.length();
    }

    /// @inheritdoc IDelegateV1
    function getPartnerAt(uint256 index_) external view returns (address) {
        return _partners.at(index_);
    }

    /// @inheritdoc OwnableUpgradeable
    function _transferOwnership(address newOwner_) internal override {
        if (newOwner_ == address(0)) {
            revert OwnershipCannotBeRenounced();
        }
        super._transferOwnership(newOwner_);
        uint256 tokenId = tokenIdByPartner[msg.sender];
        delete tokenIdByPartner[msg.sender];
        tokenIdByPartner[newOwner_] = tokenId;
        delete lockHolderByPartner[msg.sender];
        lockHolderByPartner[newOwner_] = address(this);
        _partners.remove(msg.sender);
        _partners.add(newOwner_);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
