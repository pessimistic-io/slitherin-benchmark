// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";

import "./IGrvPresale.sol";
import "./IPresaleDashboard.sol";
import "./IBEP20.sol";

contract PresaleDashboard is IPresaleDashboard {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    IGrvPresale public grvPresale;

    /* ========== INITIALIZER ========== */

    constructor(address _grvPresale) public {
        grvPresale = IGrvPresale(_grvPresale);
    }

    /* ========== VIEWS ========== */

    function receiveGrvAmount(uint256 _amount) external view override returns (uint256) {
        uint256 _adjustedAmount = _getAdjustedAmount(grvPresale.paymentCurrency(), _amount);
        uint256 _tokenPrice = grvPresale.tokenPrice();
        (uint256 _commitmentsTotal, , ) = grvPresale.marketStatus();
        uint256 _adjustedCommitmentsTotal = _getAdjustedAmount(grvPresale.paymentCurrency(), _commitmentsTotal);

        if (_tokenPrice == 0) {
            _tokenPrice = _adjustedAmount.mul(1e18).div(grvPresale.getTotalTokens());
        } else {
            _tokenPrice = _adjustedCommitmentsTotal.add(_adjustedAmount).mul(1e18).div(grvPresale.getTotalTokens());
        }

        return _adjustedAmount.mul(1e18).div(_tokenPrice);
    }

    function getPresaleInfo(address _user) external view override returns (PresaleData memory) {
        PresaleData memory presaleData;

        uint256 _commitments = grvPresale.commitments(_user);
        presaleData.commitmentAmount = _commitments;

        (uint256 _commitmentsTotal, uint256 _minimumCommitmentAmount, bool _finalized) = grvPresale.marketStatus();
        presaleData.commitmentsTotal = _commitmentsTotal;
        presaleData.minimumCommitmentAmount = _minimumCommitmentAmount;
        presaleData.finalized = _finalized;

        uint256 _tokenPrice = grvPresale.tokenPrice();

        if (_tokenPrice == 0) {
            _tokenPrice = uint256(1e18).mul(1e18).div(grvPresale.getTotalTokens());
        }

        uint256 _estimatedReceiveAmount;
        if (_commitmentsTotal == 0 || _commitments == 0) {
            _estimatedReceiveAmount = 0;
        } else {
            _estimatedReceiveAmount = _getAdjustedAmount(grvPresale.paymentCurrency(), _commitments).mul(1e18).div(_tokenPrice);
        }
        presaleData.estimatedReceiveAmount = _estimatedReceiveAmount;
        presaleData.exchangeRate = uint256(1e18).mul(1e18).div(_tokenPrice);
        presaleData.tokenPrice = _tokenPrice;
        presaleData.launchPrice = _tokenPrice.mul(20000).div(10000);

        (uint256 _startTime, uint256 _endTime, uint256 _totalTokens, ) = grvPresale.marketInfo();

        presaleData.startDate = _startTime;
        presaleData.endDate = _endTime;
        presaleData.totalTokens = _totalTokens;

        return presaleData;
    }

    function getVestingInfo(address _user) external view override returns (VestingData memory) {
        VestingData memory vestingData;

        (uint256 _commitmentsTotal, , ) = grvPresale.marketStatus();
        uint256 _commitments = grvPresale.commitments(_user);
        uint256 _tokenPrice = grvPresale.tokenPrice();

        if (_tokenPrice == 0) {
            _tokenPrice = uint256(1e18).mul(1e18).div(grvPresale.getTotalTokens());
        }

        if (_commitmentsTotal == 0 || _commitments == 0) {
            vestingData.totalPurchaseAmount = 0;
        } else {
            vestingData.totalPurchaseAmount = _getAdjustedAmount(grvPresale.paymentCurrency(), _commitments).mul(1e18).div(_tokenPrice);
        }

        vestingData.claimedAmount = grvPresale.claimed(_user);
        vestingData.claimableAmount = grvPresale.tokensClaimable(_user);

        return vestingData;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _getAdjustedAmount(address token, uint256 amount) private view returns (uint256) {
        if (token == address(0)) {
            return amount;
        } else {
            uint256 defaultDecimal = 18;
            uint256 tokenDecimal = IBEP20(token).decimals();

            if (tokenDecimal == defaultDecimal) {
                return amount;
            } else if (tokenDecimal < defaultDecimal) {
                return amount * (10**(defaultDecimal - tokenDecimal));
            } else {
                return amount / (10**(tokenDecimal - defaultDecimal));
            }
        }
    }
}

