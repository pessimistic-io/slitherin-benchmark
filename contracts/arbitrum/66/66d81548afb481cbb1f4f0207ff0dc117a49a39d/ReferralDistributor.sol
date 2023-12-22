// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";

import "./IBEP20.sol";
import "./IReferralDistributor.sol";

import "./SafeToken.sol";

contract ReferralDistributor is IReferralDistributor, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== STATE VARIABLES ========== */

    mapping(address => uint256) public claimed;
    mapping(address => uint256) public userReferral;

    address public paymentToken;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _paymentToken
    ) external initializer {
        require(_paymentToken != address(0), "ReferralDistributor: payment token is zero address");

        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        paymentToken = _paymentToken;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function emergencyWithdraw() external onlyOwner {
        uint256 tokenBalance = IBEP20(paymentToken).balanceOf(address(this));
        paymentToken.safeTransfer(msg.sender, tokenBalance);
    }

    function setUserReferral(address[] calldata _users, uint256[] calldata _referral) external onlyOwner {
        require(_users.length == _referral.length, "ReferralDistributor: invalid referral length");
        for (uint256 i = 0; i < _users.length; i++) {
            userReferral[_users[i]] = _referral[i];
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function withdrawTokens() external override nonReentrant {
        uint256 _tokensToClaim = tokensClaimable(msg.sender);
        require(_tokensToClaim > 0, "ReferralDistributor: No tokens to claim");

        claimed[msg.sender] = claimed[msg.sender].add(_tokensToClaim);

        paymentToken.safeTransfer(msg.sender, _tokensToClaim);
    }

    /* ========== VIEWS ========== */

    function tokensClaimable(address _user) public view override returns (uint256 claimableAmount) {
        if (userReferral[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(paymentToken).balanceOf(address(this));
        claimableAmount = userReferral[_user];
        claimableAmount = claimableAmount.sub(claimed[_user]);

        if (claimableAmount > unclaimedTokens) {
            claimableAmount = unclaimedTokens;
        }
    }
}

